#!/usr/bin/env python3
"""List the sessions of this project on a topic, from every tool with an adapter.

    find.py <topic>

Runs the shared `find_all.py` for the current folder and the folders below
it, on the topic, and prints one line per session that matches, newest
first. A topic of only common words (`the`) matches nothing:

    <tool> <id> <age> · <n> prompts · <title or first prompt>

`<tool>` is the adapter's folder, as `claude`, `codex`, or `antigravity`. This session, every
earlier `/recall` or `$recall` run, and Codex runs a script started
(`codex exec`) are left out. Only the 10 newest are printed; with more, a
last line says `Skipped <k> older sessions.` A tool `find_all.py` says is
not installed is not searched, and a last line says so, as in
`Codex is not installed: Claude Code sessions only.` Exits 0.

With no session left, prints `No sessions on <topic>.` (after the not
installed line, when there is one) and exits 1.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SESSIONS = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "../../shared/sessions")
NEWEST = 10


def run(*args):
    """The JSON a sessions script prints, or None when it fails."""
    r = subprocess.run([sys.executable, *map(str, args)], capture_output=True, text=True)
    return json.loads(r.stdout) if r.returncode == 0 else None


def is_recall(r):
    """This session, or an earlier recall run."""
    return r.get("current") or (r.get("first_prompt") or "").startswith(("/recall", "$recall"))


def line(r):
    text = re.sub(r"\s+", " ", r.get("title") or "").strip()[:80]
    return f"{r['harness']} {r['id']} {r['age']} · {r['prompts']} prompts · {text}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("topic", help="words the sessions are about")
    topic = ap.parse_args().topic
    out = run(os.path.join(SESSIONS, "find_all.py"), "--root", ".", "--query", topic) or {}
    tools = [h for h in out.get("harnesses", []) if "error" not in h]
    # A topic with no word the finder keeps scores nothing, since the finder
    # then lists every session unscored.
    found = [r for r in out.get("sessions", [])
             if not r.get("unreadable") and (r.get("score") or 0) > 0 and not is_recall(r)]
    found.sort(key=lambda r: r["active"], reverse=True)
    for r in found[:NEWEST]:
        print(line(r))
    if len(found) > NEWEST:
        print(f"Skipped {len(found) - NEWEST} older sessions.")
    here = " and ".join(t["label"] for t in tools if t["installed"])
    for t in tools:
        if not t["installed"]:
            print(f"{t['label']} is not installed: {here} sessions only.")
    if not found:
        print(f"No sessions on {topic}.")
        sys.exit(1)


if __name__ == "__main__":
    main()
