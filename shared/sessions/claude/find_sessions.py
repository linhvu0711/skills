#!/usr/bin/env python3
"""Find Claude Code sessions in the current project that match a description.

Claude Code stores every conversation as a JSONL transcript at
    ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
where <encoded-cwd> is the absolute working directory with every
non-alphanumeric character replaced by '-'.

This script lists the sessions for one project (default: the current working
directory) with enough metadata — title, first/last human prompt, age, size —
for a model to judge which ones match a natural-language description. When a
query is given it also scores each session against it (../rank.py) and surfaces
the best-matching snippet, so the obvious matches float to the top. It does NOT
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
    find_sessions.py "..." --days 30                     # narrow by last activity
    find_sessions.py "..." --limit 40                   # show more candidates (0: all)
"""
import argparse
import glob
import json
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
# `python3 -I` leaves the script's folder off sys.path, so the sessions folder goes on it here.
sys.path.insert(0, os.path.dirname(here))
import adapter_lib  # noqa: E402  # adapter_lib imports only after the sys.path line above

rank = adapter_lib.load("rank", os.path.join(here, "..", "rank.py"))
chat_log = adapter_lib.load("chat_log", os.path.join(here, "..", "chat_log.py"))

COMMAND_TAGS = (
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<task-notification>",  # harness re-invocation when background work finishes — not a human prompt
)
BODY_CAP = 200_000  # cap chars indexed per session for scoring (keeps big files fast)
# A word in the title or a prompt says what the user steered toward; the
# agent's replies still count, since a chat another skill started (a lone
# "/ship 237") holds its topic only there.
WEIGHTS = {"title": 3.0, "prompts": 2.0, "body": 1.0}


def encode_cwd(path):
    """Mirror Claude Code's project-dir encoding: every non-alphanumeric -> '-'."""
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def project_session_dir(project_dir):
    home = os.path.expanduser("~")
    return os.path.join(home, ".claude", "projects", encode_cwd(os.path.abspath(project_dir)))


def session_dirs(project_dirs, include_subdirs, all_projects):
    """The project folders to read. With include_subdirs, also every folder whose
    encoded name extends a root's, such as <root>/.claude/worktrees/<name>; the
    encoding is lossy, so each session's real cwd is checked after."""
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


def folder_is_root(sess, roots):
    """A transcript with no cwd counts when its folder is a root's own folder.
    With a cwd, the cwd decides, since two paths can share a folder name
    (/p/a-b and /p/a/b)."""
    return os.path.basename(os.path.dirname(sess["path"])) in {encode_cwd(r) for r in roots}


def strip_wrappers(text):
    """Drop slash-command/caveat/system-reminder scaffolding, return real text or ''."""
    if not text:
        return ""
    stripped = text.strip()
    # Command, caveat, or reminder markup is not a human prompt, but a slash command is kept.
    if stripped.startswith(COMMAND_TAGS) or adapter_lib.injected(stripped):
        # A slash-command invocation: keep its name and arguments, as "/ship 237".
        m = re.search(r"<command-name>([^<]+)</command-name>", text)
        if not m:
            return ""
        a = re.search(r"<command-args>([^<]*)</command-args>", text)
        return f"{m.group(1).strip()} {a.group(1).strip() if a else ''}".strip()
    if stripped.startswith("<system-reminder>") and stripped.endswith("</system-reminder>"):
        return ""
    cleaned = re.sub(r"<system-reminder>.*?</system-reminder>", " ", text, flags=re.S)
    cleaned = re.sub(r"<local-command-caveat>.*?</local-command-caveat>", " ", cleaned, flags=re.S)
    return cleaned.strip()


def is_bare_command(text):
    """True for a prompt that is just a slash-command token like '/clear' (no real prose)."""
    return bool(re.fullmatch(r"/[\w:-]+", text.strip()))


def parse_session(path):
    """Return a dict of metadata for one .jsonl transcript, or None if unreadable."""
    sid = os.path.basename(path)[: -len(".jsonl")]
    title = None
    cwd = None
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
            for d in chat_log.rows(f):
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
                if cwd is None and d.get("cwd"):
                    cwd = d["cwd"]
                if t == "user":
                    if d.get("isMeta") or d.get("isSidechain"):
                        continue
                    human = strip_wrappers(chat_log.text_of(d.get("message", {}).get("content")))
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
                    txt = chat_log.text_of(d.get("message", {}).get("content"))
                    if txt and body_len < BODY_CAP:
                        body_parts.append(txt)
                        body_len += len(txt)
    except OSError:
        return None

    return {
        "id": sid,
        "title": title,
        # Display fields are capped; scoring reads ``prompts``, up to BODY_CAP characters.
        "first_prompt": rank.cap(first_substantive or first_prompt),
        "last_prompt": rank.cap(last_prompt),
        "n_prompts": n_prompts,
        "modified": os.path.getmtime(path),
        "path": path,
        "size": os.path.getsize(path),
        "cwd": cwd,
        # Helper agents' transcripts sit next to the session, in <id>/subagents/.
        "subagents": sorted(glob.glob(os.path.join(os.path.dirname(path), sid, "subagents", "*.jsonl"))),
        "prompts": "\n".join(prompt_parts),
        "body": "\n".join(body_parts),
    }


def main():
    ap = argparse.ArgumentParser(description="Find Claude Code sessions in a project by description.")
    ap.add_argument("query", nargs="?", default="", help="natural-language description to match")
    ap.add_argument("--project-dir", action="append",
                    help="project working dir (default: cwd); repeat for several roots")
    ap.add_argument("--include-subdirs", action="store_true",
                    help="also sessions started below a --project-dir, such as its worktrees")
    ap.add_argument("--all-projects", action="store_true", help="every project on this machine")
    ap.add_argument("--days", type=int, help="only sessions active in the last N days (default: all time)")
    ap.add_argument("--all", action="store_true", help="list every session (newest first), ignore scoring")
    # The caller judges the list by meaning, and judges well once the session is
    # in it; 20 holds the right one far more often than 8 for a word search.
    ap.add_argument("--limit", type=int, default=20, help="max candidates to show (default 20, 0 for all)")
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
    files = [os.path.join(d, f) for d in dirs for f in os.listdir(d) if f.endswith(".jsonl")]
    scope = adapter_lib.Scope.last_days(None if args.all_projects else project_dirs, args.include_subdirs, args.days)
    files = [p for p in files if scope.in_window(os.path.getmtime(p))]
    sessions = [s for s in (parse_session(p) for p in files)
                if s and (scope.in_roots(s.get("cwd")) or (not s.get("cwd") and folder_is_root(s, scope.roots)))]

    ranked, use_query = rank.pick(sessions, sessions, args.query, WEIGHTS, args.all)

    for s in sessions:
        s["is_current"] = (s["id"] == current_id)
        s["snippet"] = rank.best_snippet(s, args.query if use_query else "")

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
                | {"age": adapter_lib.age(s["modified"]), "modified": s["modified"]}
                for s in shown
            ],
        }
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    print(f"Project session dir: {sess_dir}" if len(dirs) == 1 and dirs[0] == sess_dir
          else f"Project session dirs: {len(dirs)}")
    print(f"Total sessions in project: {len(sessions)}")
    if use_query:
        print(f'Query: "{args.query}"  →  {len(ranked)} with a search word '
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
        print(f"   {adapter_lib.age(s['modified'])} · {s['n_prompts']} prompts{score}")
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
