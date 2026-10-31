#!/usr/bin/env python3
"""List the sessions of this project on a topic, from every tool with an adapter.

    find.py <topic>

Asks the shared `scan.py` which tools have a session adapter and sessions in
the current folder and the folders below it, runs each one's adapter `find`
on the topic, and prints one line per session that matches, newest first. A
topic of only common words (`the`) matches nothing:

    <tool> <id> <age> · <n> prompts · <title or first prompt>

`<tool>` is the adapter's folder, as `claude` or `codex`. This session, every
earlier `/recall` or `$recall` run, and Codex runs a script started
(`codex exec`) are left out. Only the 10 newest are printed; with more, a
last line says `Skipped <k> older sessions.` A tool whose probe says it is
not installed is not searched, and a last line says so, as in
`Codex is not installed: Claude Code sessions only.` Exits 0.

With no session left, prints `No sessions on <topic>.` (after the not
installed line, when there is one) and exits 1.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

SESSIONS = Path(__file__).resolve().parents[1] / "../../shared/sessions"
NEWEST = 10


def run(*args):
    """The JSON a sessions script prints, or None when it fails."""
    r = subprocess.run([sys.executable, *map(str, args)], capture_output=True, text=True)
    return json.loads(r.stdout) if r.returncode == 0 else None


def sessions(harness, topic):
    """The rows the tool's adapter scores above 0 on the topic. A topic with no
    word the finder keeps scores nothing, since the finder then lists every
    session unscored."""
    rows = run(SESSIONS / harness / "adapter.py", "find", "--root", ".", "--query", topic) or []
    return [r for r in rows if not r.get("unreadable") and (r.get("score") or 0) > 0]


def is_recall(r):
    """This session, or an earlier recall run."""
    return r.get("current") or (r.get("first_prompt") or "").startswith(("/recall", "$recall"))


def line(r):
    text = re.sub(r"\s+", " ", r.get("title") or "").strip()[:80]
    return f"{r['harness']} {r['id']} {r['age']} · {r['prompts']} prompts · {text}"


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: find.py <topic>")
    topic = sys.argv[1]
    tools = [a for a in (run(SESSIONS / "scan.py", "--root", ".") or {}).get("adapters", []) if "error" not in a]
    found = [r for t in tools if t["installed"] and t["sessions"] for r in sessions(t["harness"], topic)]
    found = [r for r in found if not is_recall(r)]
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
