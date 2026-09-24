#!/usr/bin/env python3
"""Find Codex sessions for a project that match a description.

Codex stores every session as a rollout at
    ~/.codex/sessions/YYYY/MM/DD/rollout-<stamp>-<id>.jsonl
whose first line is a ``session_meta`` record carrying the session id, cwd,
and start time. The user's own prompts and the assistant's replies follow as
``response_item`` records.

The script lists the sessions whose cwd is the target project, scores each one
by keyword overlap with the query, and prints the top candidates. It leaves the
final call (which candidate the user meant) to the caller, and never touches
the clipboard.

Speed: a rollout never changes once its day is over, so parsed content is kept
in an index (``~/.cache/find-co-session/codex-index.json``, or
``/tmp/find-co-session/`` when the home cache is read-only) keyed by path, size,
and mtime. The first run over a new project parses that project's rollouts
once; later runs only parse files that are new or still growing. The cwd of
every rollout is read from line 1, so rollouts of other projects cost one
line each, never a full parse.

Read-only: never modifies any .jsonl.

Usage:
    find_session.py "rewrite the landing page hero"       # score + rank
    find_session.py --all                                  # newest first
    find_session.py "..." --cwd /path/to/proj              # other project
    find_session.py "..." --date yesterday | --days 30     # narrow by time
    find_session.py --show 01a0900b                        # one session's prompts
    find_session.py "..." --json                           # machine output
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
from pathlib import Path

SESSIONS_ROOT = Path.home() / ".codex" / "sessions"
INDEX_PATHS = (
    Path.home() / ".cache" / "find-co-session" / "codex-index.json",
    Path("/tmp") / "find-co-session" / "codex-index.json",  # Codex sandbox fallback
)
INDEX_PATH = INDEX_PATHS[0]
INDEX_VERSION = 2

PROMPT_DISPLAY_CAP = 500   # first/last prompt shown in output
PROMPTS_CAP = 20_000       # chars of user prompts kept per session for scoring
BODY_CAP = 5_000           # chars of assistant text kept per session (tiebreaker + snippet)
SNIPPET_LEN = 180

# Injected context, not a human prompt.
BLOB_MARKERS = (
    "<INSTRUCTIONS>",
    "<environment_context>",
    "AGENTS.md instructions for",
    "========= MEMORY_SUMMARY BEGINS =========",
    "<user_instructions>",
    "<recommended_plugins>",
)
BLOB_LEN = 20_000

STOP = {"the", "and", "for", "with", "that", "this", "from", "was", "were",
        "where", "when", "about", "into", "your", "you", "our", "are", "can",
        "session", "codex", "chat", "find"}


# ---------------------------------------------------------------- parsing

def content_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for block in content:
            if isinstance(block, dict):
                t = block.get("text") or block.get("input_text") or block.get("output_text")
                if isinstance(t, str):
                    out.append(t)
        return "\n".join(out)
    return ""


def is_blob(text: str) -> bool:
    return len(text) > BLOB_LEN or any(m in text for m in BLOB_MARKERS)


def read_meta(path: Path) -> dict | None:
    """Line 1 only: id, cwd, timestamp. Cheap enough to run over every rollout."""
    try:
        with path.open("rb") as h:
            first = h.readline()
        o = json.loads(first)
    except (OSError, ValueError):
        return None
    if o.get("type") != "session_meta":
        return None
    p = o.get("payload") or {}
    source = p.get("source")
    subagent = bool(p.get("parent_thread_id")) or (isinstance(source, dict) and "subagent" in source)
    return {"id": p.get("id"), "cwd": p.get("cwd"), "timestamp": p.get("timestamp"),
            "subagent": subagent}


def parse_content(path: Path) -> dict:
    """Full parse: user prompts and assistant text."""
    first = last = None
    n_user = 0
    prompts, plen = [], 0
    body, blen = [], 0
    try:
        with path.open("r", encoding="utf-8", errors="replace") as h:
            for line in h:
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if o.get("type") != "response_item":
                    continue
                item = o.get("payload") or {}
                kind = item.get("type")
                if kind == "message":
                    role = item.get("role")
                    text = content_text(item.get("content")).strip()
                    if not text:
                        continue
                    if role == "user":
                        if is_blob(text):
                            continue
                        n_user += 1
                        if first is None:
                            first = text
                        last = text
                        if plen < PROMPTS_CAP:
                            prompts.append(text)
                            plen += len(text)
                    elif role == "assistant" and blen < BODY_CAP:
                        body.append(text)
                        blen += len(text)
                elif kind == "agent_message" and blen < BODY_CAP:
                    text = content_text(item.get("content")) or str(item.get("message") or "")
                    if text.strip():
                        body.append(text)
                        blen += len(text)
    except OSError:
        pass

    def cap(t):
        if not t:
            return t
        return t[:PROMPT_DISPLAY_CAP] + ("…" if len(t) > PROMPT_DISPLAY_CAP else "")

    return {
        "first_prompt": cap(first),
        "last_prompt": cap(last),
        "n_prompts": n_user,
        "prompts": "\n".join(prompts),
        "body": "\n".join(body),
    }


# ---------------------------------------------------------------- index

def load_index() -> dict:
    for path in INDEX_PATHS:
        try:
            with path.open("r", encoding="utf-8") as h:
                idx = json.load(h)
            if idx.get("version") == INDEX_VERSION:
                return idx
        except (OSError, ValueError):
            continue
    return {"version": INDEX_VERSION, "files": {}}


def save_index(idx: dict) -> None:
    """Try each index location in order; the first writable one wins."""
    last = None
    for path in INDEX_PATHS:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(".tmp")
            with tmp.open("w", encoding="utf-8") as h:
                json.dump(idx, h, ensure_ascii=False)
            os.replace(tmp, path)
            return
        except OSError as e:
            last = e
    print(f"warning: could not save index: {last}", file=sys.stderr)


def rollout_paths(root: Path, day: dt.date | None, days: int | None):
    if day:
        dirs = [root / f"{day:%Y}" / f"{day:%m}" / f"{day:%d}"]
    elif days:
        today = dt.date.today()
        dirs = [root / f"{d:%Y}" / f"{d:%m}" / f"{d:%d}"
                for d in (today - dt.timedelta(days=i) for i in range(days))]
    else:
        dirs = [Path(dp) for dp, _, _ in os.walk(root)]
    for d in dirs:
        if not d.is_dir():
            continue
        for name in os.listdir(d):
            if name.startswith("rollout-") and name.endswith(".jsonl"):
                yield d / name


def cwd_matches(session_cwd, target: str, include_subdirs: bool) -> bool:
    if not session_cwd:
        return False
    s = os.path.normpath(os.path.expanduser(session_cwd))
    if s == target:
        return True
    return include_subdirs and s.startswith(target.rstrip(os.sep) + os.sep)


def collect(paths, target: str, include_subdirs: bool, include_subagents: bool, idx: dict) -> list[dict]:
    """Return sessions for the target cwd, parsing only what the index lacks.

    Subagent threads (spawned by another session) are skipped by default: the
    user never typed into them, so they only add noise."""
    files = idx["files"]
    out = []
    dirty = False
    for p in paths:
        key = str(p)
        try:
            st = p.stat()
        except OSError:
            continue
        ent = files.get(key)
        fresh = ent and ent["size"] == st.st_size and ent["mtime"] == st.st_mtime
        if not fresh:
            meta = read_meta(p)
            if not meta:
                continue
            ent = {"size": st.st_size, "mtime": st.st_mtime, **meta}
            files[key] = ent
            dirty = True
        if not cwd_matches(ent.get("cwd"), target, include_subdirs):
            continue
        if ent.get("subagent") and not include_subagents:
            continue
        if "prompts" not in ent:
            ent.update(parse_content(p))
            dirty = True
        out.append({"path": key, "modified": st.st_mtime, **ent})
    if dirty:
        save_index(idx)
    return out


# ---------------------------------------------------------------- scoring

def tokenize(query: str) -> list[str]:
    toks = [w for w in re.findall(r"[a-z0-9]+", query.lower()) if len(w) >= 2]
    return [t for t in toks if t not in STOP]


def score_session(s: dict, tokens: list[str], phrase: str) -> int:
    """Presence of query words in the user's prompts is the signal; the assistant
    body is a faint tiebreaker so volume cannot win."""
    prompts = s["prompts"].lower()
    body = s["body"].lower()
    score = 0
    matched = 0
    for tok in tokens:
        hit = False
        if tok in prompts:
            score += 4 + min(prompts.count(tok) - 1, 3)
            hit = True
        if tok in body:
            score += 1
            hit = True
        matched += hit
    score += matched * matched
    if phrase and len(phrase) > 3:
        if phrase in prompts:
            score += 20
        elif phrase in body:
            score += 6
    return score


def best_snippet(s: dict, tokens: list[str]) -> str:
    lines = []
    for key in ("first_prompt", "last_prompt"):
        if s.get(key):
            lines.extend(s[key].splitlines())
    lines.extend(s["body"].splitlines())
    best, best_hits = "", 0
    for line in lines:
        line = line.strip()
        if not line:
            continue
        low = line.lower()
        hits = sum(1 for t in tokens if t in low)
        if hits > best_hits:
            best, best_hits = line, hits
            if hits == len(tokens):
                break
    snip = re.sub(r"\s+", " ", best or s.get("first_prompt") or "").strip()
    return snip[:SNIPPET_LEN] + ("…" if len(snip) > SNIPPET_LEN else "")


def humanize_age(mtime: float) -> str:
    mins = max(0.0, time.time() - mtime) / 60
    if mins < 60:
        return f"{int(mins)}m ago"
    if mins < 60 * 24:
        return f"{int(mins / 60)}h ago"
    days = mins / 60 / 24
    if days < 14:
        return f"{int(days)}d ago"
    return f"{int(days / 7)}w ago"


# ---------------------------------------------------------------- cli

def resolve_day(value: str | None) -> dt.date | None:
    if not value:
        return None
    v = value.lower()
    if v == "today":
        return dt.date.today()
    if v == "yesterday":
        return dt.date.today() - dt.timedelta(days=1)
    return dt.date.fromisoformat(value)


def show_session(id_prefix: str, idx: dict) -> int:
    """Print the user prompts of one session (by id prefix) for verification."""
    hits = [(k, e) for k, e in idx["files"].items()
            if (e.get("id") or "").startswith(id_prefix)]
    if not hits:
        print(f"No indexed session id starts with {id_prefix!r}. Run a search for its project first.")
        return 1
    if len(hits) > 1:
        print("Ambiguous prefix:", ", ".join(e["id"] for _, e in hits))
        return 1
    key, e = hits[0]
    if "prompts" not in e:
        e.update(parse_content(Path(key)))
    print(f"{e['id']}  cwd={e.get('cwd')}  started={e.get('timestamp')}  prompts={e.get('n_prompts')}")
    print(f"path: {key}\n")
    for i, p in enumerate(e["prompts"].split("\n"), 1):
        p = p.strip()
        if p:
            print(f"[{i}] {p[:600]}{'…' if len(p) > 600 else ''}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Find Codex sessions for a project by description.")
    ap.add_argument("query", nargs="?", default="", help="natural-language description to match")
    ap.add_argument("--cwd", default=os.getcwd(), help="project working dir (default: cwd)")
    ap.add_argument("--include-subdirs", action="store_true", help="also match sessions started below --cwd")
    ap.add_argument("--include-subagents", action="store_true", help="also list subagent threads spawned by other sessions")
    ap.add_argument("--all", action="store_true", help="list every session newest first, no scoring")
    ap.add_argument("--date", help="one local calendar day: today, yesterday, or YYYY-MM-DD")
    ap.add_argument("--days", type=int, help="only the last N days (default: all time)")
    ap.add_argument("--limit", type=int, default=8, help="max candidates to show (default 8)")
    ap.add_argument("--show", metavar="ID", help="print the user prompts of one session (id or prefix)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    ap.add_argument("--sessions-root", default=str(SESSIONS_ROOT))
    args = ap.parse_args()

    idx = load_index()
    if args.show:
        return show_session(args.show, idx)

    root = Path(args.sessions_root).expanduser()
    if not root.is_dir():
        print(f"No Codex sessions root at {root}")
        return 1
    target = os.path.normpath(os.path.expanduser(args.cwd))
    paths = rollout_paths(root, resolve_day(args.date), args.days)
    sessions = collect(paths, target, args.include_subdirs, args.include_subagents, idx)

    tokens = tokenize(args.query)
    phrase = args.query.strip().lower()
    use_query = bool(tokens) and not args.all

    for s in sessions:
        s["score"] = score_session(s, tokens, phrase) if use_query else 0
        s["snippet"] = best_snippet(s, tokens if use_query else [])
    if use_query:
        ranked = [s for s in sessions if s["score"] > 0]
        ranked.sort(key=lambda s: (s["score"], s["modified"]), reverse=True)
    else:
        ranked = sorted(sessions, key=lambda s: s["modified"], reverse=True)
    shown = ranked[: max(args.limit, 1)]

    if args.json:
        keys = ("id", "cwd", "timestamp", "first_prompt", "last_prompt", "n_prompts", "score", "snippet", "path")
        print(json.dumps({
            "cwd": target, "query": args.query,
            "total_sessions": len(sessions), "matched": len(ranked),
            "sessions": [{k: s.get(k) for k in keys} | {"age": humanize_age(s["modified"])} for s in shown],
        }, indent=2, ensure_ascii=False))
        return 0

    print(f"Project: {target}{' (+subdirs)' if args.include_subdirs else ''}")
    print(f"Sessions for this project: {len(sessions)}")
    if use_query:
        print(f'Query: "{args.query}"  →  {len(ranked)} with keyword overlap (showing top {len(shown)})')
    else:
        print(f"Listing {len(shown)} most recent")
    if not shown:
        print("\nNo candidates. Try a broader description, --all, --include-subdirs, or another --cwd.")
        return 1
    print()
    for i, s in enumerate(shown, 1):
        score = f"  [score {s['score']}]" if use_query else ""
        print(f"{i}. {s['id']}")
        print(f"   {humanize_age(s['modified'])} · {s['n_prompts']} prompts{score}")
        if args.include_subdirs:
            print(f"   cwd:    {s.get('cwd')}")
        if s.get("first_prompt"):
            fp = re.sub(r"\s+", " ", s["first_prompt"]).strip()
            print(f"   opened: {fp[:160]}{'…' if len(fp) > 160 else ''}")
        if s["snippet"] and s["snippet"] != (s.get("first_prompt") or ""):
            print(f"   match:  {s['snippet']}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
