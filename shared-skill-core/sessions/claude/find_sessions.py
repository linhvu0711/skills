#!/usr/bin/env python3
"""Find Claude Code sessions in the current project that match a description.

Claude Code stores every conversation as a JSONL transcript at
    ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
where <encoded-cwd> is the absolute working directory with every
non-alphanumeric character replaced by '-'.

This script lists the sessions for one project (default: the current working
directory) with enough metadata — title, first/last human prompt, age, size —
for a model to judge which ones match a natural-language description. When a
query is given it also scores each session by keyword overlap and surfaces the
best-matching snippet, so the obvious matches float to the top. It does NOT
decide the final match or touch the clipboard — that judgment is left to the
caller, which is better at fuzzy/semantic matching than keyword counting.

Read-only: never modifies any .jsonl.

Usage:
    find_sessions.py "rewrite the landing page hero"   # score + rank by the query
    find_sessions.py --all                              # list everything, newest first
    find_sessions.py "..." --json                       # machine-readable output
    find_sessions.py "..." --project-dir /path/to/proj  # a different project
    find_sessions.py "..." --project-dir A --project-dir B --include-subdirs
                                                        # several roots, worktrees under them
    find_sessions.py --all-projects --days 3 --all      # every project, last 3 days
    find_sessions.py "..." --date yesterday | --days 30 # narrow by last activity
    find_sessions.py "..." --limit 12                   # show more candidates (0: all)
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
import time

WRAP_PREFIXES = (
    "<local-command-caveat>",
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<command-stdout>",
    "<local-command-stdout>",
    "<task-notification>",  # harness re-invocation when background work finishes — not a human prompt
)
PROMPT_DISPLAY_CAP = 500  # cap stored first/last prompt so a pasted wall-of-text can't flood output
BODY_CAP = 200_000  # cap chars indexed per session for scoring (keeps big files fast)
SNIPPET_LEN = 180


def encode_cwd(path):
    """Mirror Claude Code's project-dir encoding: every non-alphanumeric -> '-'."""
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def project_session_dir(project_dir):
    home = os.path.expanduser("~")
    return os.path.join(home, ".claude", "projects", encode_cwd(os.path.abspath(project_dir)))


def session_dirs(project_dirs, include_subdirs, all_projects):
    """The project folders to read. With include_subdirs, also every folder whose
    encoded name extends a root's, such as <root>/.claude/worktrees/<name>; the
    encoding is lossy, so in_scope() checks each session's real cwd after."""
    root = os.path.join(os.path.expanduser("~"), ".claude", "projects")
    if not os.path.isdir(root):
        return []
    names = sorted(n for n in os.listdir(root) if os.path.isdir(os.path.join(root, n)))
    if all_projects:
        return [os.path.join(root, n) for n in names]
    out = []
    for d in project_dirs:
        enc = encode_cwd(os.path.abspath(d))
        for n in names:
            if n == enc or (include_subdirs and n.startswith(enc + "-")):
                path = os.path.join(root, n)
                if path not in out:
                    out.append(path)
    return out


def in_scope(sess, project_dirs, include_subdirs, all_projects):
    """True when the session belongs to one of the roots: its recorded cwd is a
    root, or with include_subdirs below one. Two paths can share a folder name
    (/p/a-b and /p/a/b), so the cwd decides; a transcript with no cwd counts
    when its folder is a root's own folder."""
    if all_projects:
        return True
    folder = os.path.basename(os.path.dirname(sess["path"]))
    cwd = sess.get("cwd")
    for d in project_dirs:
        d = os.path.abspath(d)
        if not cwd:
            if folder == encode_cwd(d):
                return True
            continue
        if cwd == d or (include_subdirs and cwd.startswith(d.rstrip(os.sep) + os.sep)):
            return True
    return False


def resolve_day(value):
    if not value:
        return None
    v = value.lower()
    if v == "today":
        return dt.date.today()
    if v == "yesterday":
        return dt.date.today() - dt.timedelta(days=1)
    return dt.date.fromisoformat(value)


def in_window(mtime, day, days):
    """By last activity, in local time: on one day, or within the last N days
    counting today as the first."""
    when = dt.date.fromtimestamp(mtime)
    if day:
        return when == day
    if days:
        return when >= dt.date.today() - dt.timedelta(days=days - 1)
    return True


def text_of(message):
    """Extract human-readable text from a message's content (str or block list)."""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return "\n".join(parts)
    return ""


def strip_wrappers(text):
    """Drop slash-command/caveat/system-reminder scaffolding, return real text or ''."""
    if not text:
        return ""
    stripped = text.strip()
    # Whole message is just command/caveat/reminder scaffolding -> not a human prompt.
    if stripped.startswith(WRAP_PREFIXES):
        # A slash-command invocation: pull the command name out so it's still searchable.
        m = re.search(r"<command-name>([^<]+)</command-name>", text)
        return m.group(1).strip() if m else ""
    if stripped.startswith("<system-reminder>") and stripped.endswith("</system-reminder>"):
        return ""
    # Remove any embedded reminder/caveat blocks but keep surrounding prose.
    cleaned = re.sub(r"<system-reminder>.*?</system-reminder>", " ", text, flags=re.S)
    cleaned = re.sub(r"<local-command-caveat>.*?</local-command-caveat>", " ", cleaned, flags=re.S)
    return cleaned.strip()


def is_bare_command(text):
    """True for a prompt that is just a slash-command token like '/clear' (no real prose)."""
    return bool(re.fullmatch(r"/[\w:-]+", text.strip()))


def parse_session(path):
    """Return a dict of metadata for one .jsonl transcript, or None if unreadable.

    Scoring leans on what the *human* steered the session toward (title + prompts);
    the assistant's output (``body``) is kept only for snippet display, because its
    sheer volume would otherwise let incidental word hits drown out the real topic.
    """
    sid = os.path.basename(path)[: -len(".jsonl")]
    title = None
    cwd = None
    created = None
    first_prompt = None      # first prompt of any kind (may be a bare slash command)
    first_substantive = None  # first prompt with real prose, for display
    last_prompt = None
    n_prompts = 0
    prompt_parts = []
    prompt_len = 0
    body_parts = []
    body_len = 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                t = d.get("type")
                if t in ("ai-title", "summary"):
                    # Current Claude Code writes {"type":"ai-title","aiTitle":...};
                    # older transcripts used {"type":"summary","summary":...}.
                    s = d.get("aiTitle") or d.get("summary")
                    if s:
                        title = s  # keep the latest one as the title
                    continue
                if t == "last-prompt":
                    lp = d.get("lastPrompt")
                    if isinstance(lp, str) and lp.strip():
                        last_prompt = strip_wrappers(lp) or last_prompt
                    continue
                ts = d.get("timestamp")
                if ts and created is None:
                    created = ts
                if cwd is None and d.get("cwd"):
                    cwd = d["cwd"]
                if t == "user":
                    if d.get("isMeta") or d.get("isSidechain"):
                        continue
                    human = strip_wrappers(text_of(d.get("message", {})))
                    if human:
                        n_prompts += 1
                        if first_prompt is None:
                            first_prompt = human
                        if first_substantive is None and not is_bare_command(human):
                            first_substantive = human
                        last_prompt = human
                        if prompt_len < BODY_CAP:
                            prompt_parts.append(human)
                            prompt_len += len(human)
                elif t == "assistant":
                    if d.get("isSidechain"):
                        continue
                    txt = text_of(d.get("message", {}))
                    if txt and body_len < BODY_CAP:
                        body_parts.append(txt)
                        body_len += len(txt)
    except OSError:
        return None

    def cap(text):
        if not text:
            return text
        text = text.strip()
        return text[:PROMPT_DISPLAY_CAP] + ("…" if len(text) > PROMPT_DISPLAY_CAP else "")

    return {
        "id": sid,
        "title": title,
        # Display fields are capped; the full text still lives in ``prompts`` for scoring.
        "first_prompt": cap(first_substantive or first_prompt),
        "last_prompt": cap(last_prompt),
        "n_prompts": n_prompts,
        "modified": os.path.getmtime(path),
        "created": created,
        "path": path,
        "size": os.path.getsize(path),
        "cwd": cwd,
        # Helper agents' transcripts sit next to the session, in <id>/subagents/.
        "subagents": sorted(glob.glob(os.path.join(os.path.dirname(path), sid, "subagents", "*.jsonl"))),
        "prompts": "\n".join(prompt_parts),
        "body": "\n".join(body_parts),
    }


def score_session(sess, tokens, phrase):
    """Relevance by how well the query overlaps the session's *topic*.

    Topic lives in the title (summary) and the human prompts — those are what the
    user steered toward. We score by token *presence* there (not raw frequency) so a
    short, on-topic session isn't beaten by a long, sprawling one that mentions the
    words in passing. The assistant body counts only as a faint tiebreaker, by
    distinct tokens present, so volume can't dominate. Returns (score, snippet).
    """
    if not tokens:
        return 0, ""
    title = (sess["title"] or "").lower()
    prompts = sess["prompts"].lower()
    body = sess["body"].lower()

    score = 0
    matched = set()
    for tok in tokens:
        hit = False
        if tok in title:
            score += 6
            hit = True
        if tok in prompts:
            # presence is the main signal; a little extra for repeated emphasis
            score += 4 + min(prompts.count(tok) - 1, 3)
            hit = True
        if tok in body:
            score += 1  # distinct-token presence only — no frequency multiplier
            hit = True
        if hit:
            matched.add(tok)
    # Reward breadth: matching many distinct query words beats hammering one.
    score += len(matched) * len(matched)
    # Exact phrase is a strong signal of a real match.
    if phrase and len(phrase) > 3:
        if phrase in title:
            score += 40
        elif phrase in prompts:
            score += 20
        elif phrase in body:
            score += 6
    return score, best_snippet(sess, tokens)


def best_snippet(sess, tokens):
    """Pick the most query-dense line from the prompts/title/body for display."""
    candidates = []
    if sess["title"]:
        candidates.append(sess["title"])
    for key in ("first_prompt", "last_prompt"):
        if sess[key]:
            candidates.extend(sess[key].splitlines())
    candidates.extend(sess["body"].splitlines())
    best, best_hits = "", 0
    for line in candidates:
        line = line.strip()
        if not line:
            continue
        low = line.lower()
        hits = sum(1 for tok in tokens if tok in low)
        if hits > best_hits:
            best, best_hits = line, hits
            if best_hits == len(tokens):
                break
    snippet = best or (sess["first_prompt"] or sess["title"] or "")
    snippet = re.sub(r"\s+", " ", snippet).strip()
    return snippet[:SNIPPET_LEN] + ("…" if len(snippet) > SNIPPET_LEN else "")


def humanize_age(mtime):
    delta = max(0, time.time() - mtime)
    mins = delta / 60
    if mins < 60:
        return f"{int(mins)}m ago"
    hours = mins / 60
    if hours < 24:
        return f"{int(hours)}h ago"
    days = hours / 24
    if days < 14:
        return f"{int(days)}d ago"
    return f"{int(days / 7)}w ago"


def tokenize(query):
    toks = [w for w in re.findall(r"[a-z0-9]+", query.lower()) if len(w) >= 2]
    # Drop a few ultra-common words that add noise to keyword scoring.
    stop = {"the", "and", "for", "with", "that", "this", "from", "was", "were",
            "where", "when", "about", "into", "your", "you", "our", "are", "can"}
    return [t for t in toks if t not in stop]


def main():
    ap = argparse.ArgumentParser(description="Find Claude Code sessions in a project by description.")
    ap.add_argument("query", nargs="?", default="", help="natural-language description to match")
    ap.add_argument("--project-dir", action="append",
                    help="project working dir (default: cwd); repeat for several roots")
    ap.add_argument("--include-subdirs", action="store_true",
                    help="also sessions started below a --project-dir, such as its worktrees")
    ap.add_argument("--all-projects", action="store_true", help="every project on this machine")
    ap.add_argument("--date", help="one local calendar day of last activity: today, yesterday, or YYYY-MM-DD")
    ap.add_argument("--days", type=int, help="only sessions active in the last N days (default: all time)")
    ap.add_argument("--all", action="store_true", help="list every session (newest first), ignore scoring")
    ap.add_argument("--limit", type=int, default=8, help="max candidates to show (default 8, 0 for all)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    args = ap.parse_args()

    project_dirs = args.project_dir or [os.getcwd()]
    sess_dir = project_session_dir(project_dirs[0])
    dirs = session_dirs(project_dirs, args.include_subdirs, args.all_projects)
    if not dirs:
        msg = (f"No session history found for this project.\n"
               f"Looked in: {sess_dir}\n"
               f"(Derived from project dir: {os.path.abspath(project_dirs[0])})")
        if args.json:
            print(json.dumps({"error": "no_project_dir", "session_dir": sess_dir, "sessions": []}))
        else:
            print(msg)
        return

    current_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    day = resolve_day(args.date)
    files = [os.path.join(d, f) for d in dirs for f in os.listdir(d) if f.endswith(".jsonl")]
    files = [p for p in files if in_window(os.path.getmtime(p), day, args.days)]
    sessions = [s for s in (parse_session(p) for p in files)
                if s and in_scope(s, project_dirs, args.include_subdirs, args.all_projects)]

    tokens = tokenize(args.query)
    phrase = args.query.strip().lower()
    use_query = bool(tokens) and not args.all

    for s in sessions:
        s["is_current"] = (s["id"] == current_id)
        if use_query:
            s["score"], s["snippet"] = score_session(s, tokens, phrase)
        else:
            s["score"], s["snippet"] = 0, best_snippet(s, [])

    if use_query:
        ranked = [s for s in sessions if s["score"] > 0]
        ranked.sort(key=lambda s: (s["score"], s["modified"]), reverse=True)
    else:
        ranked = sorted(sessions, key=lambda s: s["modified"], reverse=True)

    shown = ranked[: args.limit] if args.limit > 0 else ranked

    if args.json:
        out = {
            "session_dir": sess_dir,
            "session_dirs": dirs,
            "query": args.query,
            "current_session_id": current_id,
            "total_sessions": len(sessions),
            "matched": len(ranked) if use_query else len(sessions),
            "sessions": [
                {k: s[k] for k in ("id", "title", "first_prompt", "last_prompt",
                                   "n_prompts", "score", "snippet", "is_current",
                                   "path", "size", "cwd", "subagents")}
                | {"age": humanize_age(s["modified"]), "modified": s["modified"]}
                for s in shown
            ],
        }
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    # Pretty text output
    print(f"Project session dir: {sess_dir}" if len(dirs) == 1 and dirs[0] == sess_dir
          else f"Project session dirs: {len(dirs)}")
    print(f"Total sessions in project: {len(sessions)}")
    if use_query:
        print(f'Query: "{args.query}"  →  {len(ranked)} with keyword overlap '
              f'(showing top {len(shown)})')
    else:
        print(f"Listing {len(shown)} most recent (no query / --all)")
    if not shown:
        print("\nNo candidates. Try --all to list everything, or a broader description.")
        return
    print()
    for i, s in enumerate(shown, 1):
        flag = "  ← current session" if s["is_current"] else ""
        score = f"  [score {s['score']}]" if use_query else ""
        print(f"{i}. {s['id']}{flag}")
        print(f"   {humanize_age(s['modified'])} · {s['n_prompts']} prompts{score}")
        if s["title"]:
            print(f"   title:  {s['title']}")
        if s["first_prompt"]:
            fp = re.sub(r"\s+", " ", s["first_prompt"]).strip()
            print(f"   opened: {fp[:160]}{'…' if len(fp) > 160 else ''}")
        if s["snippet"] and s["snippet"] not in (s["title"] or ""):
            print(f"   match:  {s['snippet']}")
        print()


if __name__ == "__main__":
    main()
