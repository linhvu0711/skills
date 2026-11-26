#!/usr/bin/env python3
"""Find Codex sessions for a project that match a description.

Codex stores every session as a rollout at
    ~/.codex/sessions/YYYY/MM/DD/rollout-<stamp>-<id>.jsonl
and moves an archived one, under the same name, to
    ~/.codex/archived_sessions/rollout-<stamp>-<id>.jsonl
Both folders come from rollout_io.data_folders(). Each rollout (older ones
compressed as .jsonl.zst) starts with a ``session_meta`` record carrying the
session id, cwd, and start time. The user's own prompts and the assistant's replies follow as
``response_item`` records.

The script lists the sessions whose cwd is the target project, scores each one
against the query (../rank.py), and prints the top candidates. It leaves the
final call (which candidate the user meant) to the caller, and never touches
the clipboard.

Speed: a rollout never changes once its day is over, so parsed content is kept
in an index (``~/.cache/find-co-session/codex-index.json``, or
``/tmp/find-co-session/`` when the home cache is read-only) keyed by path, size,
and mtime. The first run over a new project parses that project's rollouts
once; later runs only parse files that are new or still growing. The cwd of
every rollout is read from line 1, so rollouts of other projects cost one
line each, never a full parse.

Read-only: never modifies any rollout. A compressed rollout this machine
cannot read (no Python 3.14+, no zstd) is listed under "unreadable".

Usage:
    find_session.py "rewrite the landing page hero"       # score + rank
    find_session.py --all                                  # newest first
    find_session.py "..." --cwd /path/to/proj              # other project
    find_session.py "..." --cwd A --cwd B --include-subdirs # several roots and below
    find_session.py --all-projects --active-days 3 --all   # every project, used in the last 3 days
    find_session.py "..." --active-days 3                  # used in the last 3 days
    find_session.py "..." --json                           # machine output
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
# `python3 -I` leaves the script's folder off sys.path, so the sessions folder goes on it here.
sys.path.insert(0, os.path.dirname(here))
import adapter_lib  # noqa: E402

rollout_io = adapter_lib.load("rollout_io", os.path.join(here, "rollout_io.py"))
rank = adapter_lib.load("rank", os.path.join(here, "..", "rank.py"))
chat_log = adapter_lib.load("chat_log", os.path.join(here, "..", "chat_log.py"))

INDEX_PATHS = (
    os.path.join(os.path.expanduser("~"), ".cache", "find-co-session", "codex-index.json"),
    os.path.join("/tmp", "find-co-session", "codex-index.json"),  # Codex sandbox fallback
)
INDEX_VERSION = 7  # 7: prompts skip injected text by prefix; 6: body keeps 50k chars; 5: meta keeps the parent of a helper thread; 4: the source; 3: prompts is a list

PROMPTS_CAP = 20_000       # chars of user prompts kept per session for scoring
BODY_CAP = 50_000          # chars of assistant text kept per session: a chat another skill started holds its topic here

BLOB_LEN = 20_000

# A word the user typed says what they steered toward; the agent's replies
# still count, since a chat another skill started holds its topic only there.
WEIGHTS = {"prompts": 2.0, "body": 1.0}


# ---------------------------------------------------------------- parsing

def is_blob(text: str) -> bool:
    return len(text) > BLOB_LEN or adapter_lib.injected(text)


def read_meta(path: str) -> dict | None:
    """Line 1 only: id, cwd, timestamp. Cheap enough to run over every rollout."""
    try:
        with rollout_io.open_rollout(path) as h:
            first = h.readline()
        o = json.loads(first)
    except (OSError, ValueError):
        return None
    if o.get("type") != "session_meta":
        return None
    p = o.get("payload") or {}
    source = p.get("source")
    subagent = bool(p.get("parent_thread_id")) or (isinstance(source, dict) and "subagent" in source)
    parent = p.get("parent_thread_id")
    if not parent and isinstance(source, dict):
        sub = source.get("subagent")
        # Older rollouts name the helper kind as a plain string here, with no parent.
        spawn = (sub.get("thread_spawn") or {}) if isinstance(sub, dict) else {}
        parent = spawn.get("parent_thread_id")
    return {"id": p.get("id"), "cwd": p.get("cwd"), "timestamp": p.get("timestamp"),
            "subagent": subagent, "parent": parent,
            "source": source if isinstance(source, str) else None}


def parse_content(path: str) -> dict:
    """Full parse: user prompts and assistant text."""
    first = last = None
    n_user = 0
    prompts, plen = [], 0
    body, blen = [], 0
    try:
        with rollout_io.open_rollout(path) as h:
            for o in chat_log.rows(h):
                if o.get("type") != "response_item":
                    continue
                item = o.get("payload") or {}
                kind = item.get("type")
                if kind == "message":
                    role = item.get("role")
                    text = chat_log.text_of(item.get("content")).strip()
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
                    text = chat_log.text_of(item.get("content")) or str(item.get("message") or "")
                    if text.strip():
                        body.append(text)
                        blen += len(text)
    except OSError:
        pass

    return {
        "first_prompt": rank.cap(first),
        "last_prompt": rank.cap(last),
        "n_prompts": n_user,
        "prompts": prompts,
        "body": "\n".join(body),
    }


# ---------------------------------------------------------------- index

def load_index() -> dict:
    for path in INDEX_PATHS:
        try:
            with open(path, encoding="utf-8") as h:
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
            os.makedirs(os.path.dirname(path), exist_ok=True)
            # A name of its own, so a search that runs at the same time keeps its file.
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=os.path.basename(path) + ".")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as h:
                    json.dump(idx, h, ensure_ascii=False)
                os.replace(tmp, path)
            finally:
                if os.path.exists(tmp):
                    os.remove(tmp)
            return
        except OSError as e:
            last = e
    print(f"warning: could not save index: {last}", file=sys.stderr)


def rollout_paths():
    """Every rollout in Codex's data folders."""
    for root in rollout_io.data_folders():
        for dp, _, names in os.walk(root):
            for name in names:
                if rollout_io.is_rollout_name(name):
                    yield os.path.join(dp, name)


def start_day(path: str) -> dt.date | None:
    """The day a rollout started: its YYYY/MM/DD folder, or in the flat
    archive the rollout-YYYY-MM-DD stamp of its name."""
    try:
        y, m, d = os.path.normpath(path).split(os.sep)[-4:-1]
        return dt.date(int(y), int(m), int(d))
    except (ValueError, TypeError):
        pass
    try:
        return dt.date.fromisoformat(os.path.basename(path)[len("rollout-"):len("rollout-YYYY-MM-DD")])
    except ValueError:
        return None


def collect(paths, scope, idx: dict,
            interactive_only: bool = False, skipped: dict | None = None, keep=None) -> list[dict]:
    """Return sessions for the target cwd, parsing only what the index lacks.

    Subagent threads (spawned by another session) are skipped: the
    user never typed into them, so they only add noise. With interactive_only,
    headless `codex exec` runs are skipped too and counted in skipped["exec"].
    keep(key, stat) picks the sessions returned; every path still feeds the
    helper map, since a helper can sit in another day folder than its parent or
    be older than a resumed parent. Each session row lists the rollouts of its
    helper threads, and of their helpers, in "subagents"."""
    files = idx["files"]
    out = []
    helpers = {}
    dirty = False
    for p in paths:
        key = str(p)
        try:
            st = os.stat(p)
        except OSError:
            continue
        ent = files.get(key)
        fresh = ent and ent["size"] == st.st_size and ent["mtime"] == st.st_mtime
        if not fresh:
            try:
                meta = read_meta(p)
            except rollout_io.NoZstd as e:
                # Its cwd is inside the file, so only the window can filter it.
                if skipped is not None and (not keep or keep(key, st)):
                    skipped.setdefault("unreadable", []).append({"path": key, "modified": st.st_mtime, "why": str(e)})
                continue
            if not meta:
                continue
            ent = {"size": st.st_size, "mtime": st.st_mtime, **meta}
            files[key] = ent
            dirty = True
        if ent.get("parent"):
            helpers.setdefault(ent["parent"], []).append(key)
        if keep and not keep(key, st):
            continue
        if not scope.in_roots(ent.get("cwd")):
            continue
        if ent.get("subagent"):
            continue
        if interactive_only and ent.get("source") == "exec":
            if skipped is not None:
                skipped["exec"] = skipped.get("exec", 0) + 1
            continue
        if "prompts" not in ent:
            ent.update(parse_content(p))
            dirty = True
        out.append({"path": key, "modified": st.st_mtime, "size": st.st_size, **ent})
    if dirty:
        save_index(idx)
    for s in out:
        s["subagents"] = helper_paths(s.get("id"), helpers, files)
    return out


def helper_paths(sid, helpers: dict, files: dict) -> list[str]:
    """Every rollout spawned under sid, a helper's own helpers included."""
    seen, todo, found = {sid}, [sid], []
    while todo:
        for key in helpers.get(todo.pop(), []):
            found.append(key)
            hid = files.get(key, {}).get("id")
            if hid and hid not in seen:
                seen.add(hid)
                todo.append(hid)
    return sorted(found)


# ---------------------------------------------------------------- cli

def main() -> int:
    ap = argparse.ArgumentParser(description="Find Codex sessions for a project by description.")
    ap.add_argument("query", nargs="?", default="", help="natural-language description to match")
    ap.add_argument("--cwd", action="append", help="project working dir (default: cwd); repeat for several roots")
    ap.add_argument("--all-projects", action="store_true", help="every project on this machine")
    ap.add_argument("--include-subdirs", action="store_true", help="also match sessions started below --cwd")
    ap.add_argument("--interactive", action="store_true", help="leave out headless `codex exec` runs")
    ap.add_argument("--all", action="store_true", help="list every session newest first, no scoring")
    ap.add_argument("--active-days", type=int,
                    help="only sessions used in the last N days, wherever they started (by the rollout's mtime)")
    # The caller judges the list by meaning, and judges well once the session is
    # in it; 20 holds the right one far more often than 8 for a word search.
    ap.add_argument("--limit", type=int, default=20, help="max candidates to show (default 20, 0 for all)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    args = ap.parse_args()

    idx = load_index()

    folders = rollout_io.data_folders()
    if not any(os.path.isdir(f) for f in folders):
        print(f"No Codex sessions under {' or '.join(folders)}")
        return 1
    roots = [os.path.normpath(os.path.expanduser(c)) for c in (args.cwd or [os.getcwd()])]
    target = "all projects" if args.all_projects else ", ".join(roots)
    # A resumed rollout stays in its start-day folder, so --active-days goes by
    # the file's mtime instead of the folder.
    scope = adapter_lib.Scope.last_days(None if args.all_projects else roots, args.include_subdirs, args.active_days)

    def keep(key, st):
        return scope.in_window(st.st_mtime)

    # Helpers can sit outside the window (filed under a later day, or older than
    # a resumed parent), but a helper never starts before its parent. So read
    # every folder from the earliest day a picked session started; with no
    # window, that is every folder.
    paths = list(rollout_paths())
    if scope.since is not None:
        picked = []
        for p in paths:
            try:
                st = os.stat(p)
            except OSError:
                continue
            if keep(str(p), st):
                picked.append(start_day(p))
        first = min((d for d in picked if d), default=None)
        paths = [p for p in paths if first and (start_day(p) or first) >= first]

    skipped = {}
    sessions = collect(paths, scope, idx,
                       interactive_only=args.interactive, skipped=skipped, keep=keep)

    docs = [{"prompts": "\n".join(s["prompts"]), "body": s["body"]} for s in sessions]
    ranked, use_query = rank.pick(sessions, docs, args.query, WEIGHTS, args.all)
    for s in sessions:
        s["snippet"] = rank.best_snippet(s, args.query if use_query else "")
    shown = ranked[: args.limit] if args.limit > 0 else ranked

    if args.json:
        keys = ("id", "cwd", "timestamp", "source", "first_prompt", "last_prompt", "n_prompts", "score", "snippet", "path", "size", "modified", "subagents")
        print(json.dumps({
            "cwd": target, "query": args.query,
            "total_sessions": len(sessions), "matched": len(ranked), "skipped_exec": skipped.get("exec", 0),
            "unreadable": skipped.get("unreadable", []),
            "sessions": [{k: s.get(k) for k in keys} | {"age": adapter_lib.age(s["modified"])} for s in shown],
        }, indent=2, ensure_ascii=False))
        return 0

    print(f"Project: {target}{' (+subdirs)' if args.include_subdirs else ''}")
    print(f"Sessions for this project: {len(sessions)}")
    if use_query:
        print(f'Query: "{args.query}"  →  {len(ranked)} with a search word (showing top {len(shown)})')
    else:
        print(f"Listing {len(shown)} most recent")
    if not shown:
        print("\nNo candidates. Try a broader description, --all, --include-subdirs, or another --cwd.")
        return 1
    print()
    for i, s in enumerate(shown, 1):
        score = f"  [score {s['score']}]" if use_query else ""
        print(f"{i}. {s['id']}")
        print(f"   {adapter_lib.age(s['modified'])} · {s['n_prompts']} prompts{score}")
        if args.include_subdirs or args.all_projects or len(roots) > 1:
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
