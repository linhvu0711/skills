#!/usr/bin/env python3
"""List the Claude Code and Codex sessions of this project on a topic.

    find.py <topic>

Runs the shared Claude Code and Codex finders on the topic, in the current
folder and the folders below it, and prints one line per session that
matches, newest first:

    <tool> <id> <age> · <n> prompts · <title or first prompt>

`<tool>` is `claude` or `codex`. This session, and every earlier `/recall`
or `$recall` run, is left out. Only the 10 newest are printed; with more,
a last line says `Skipped <k> older sessions.` With no `~/.codex/sessions`
folder, only Claude Code is searched, and a last line says
`Codex is not installed: Claude Code sessions only.` Exits 0.

With no session left, prints `No sessions on <topic>.` (after the Codex
line, when there is one) and exits 1.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
CLAUDE = SKILL / "../../shared-skill-core/sessions/claude/find_sessions.py"
CODEX = SKILL / "../../shared-skill-core/sessions/codex/find_session.py"
NEWEST = 10


def sessions(finder, topic):
    """The sessions the finder matches on the topic; none when it has none."""
    r = subprocess.run([sys.executable, str(finder), topic, "--json", "--limit", "0", "--include-subdirs"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return []
    found = json.loads(r.stdout)
    return [] if "error" in found else found["sessions"]


def is_recall(s):
    """This session, or an earlier recall run."""
    return s.get("is_current") or (s.get("first_prompt") or "").startswith(("/recall", "$recall"))


def line(tool, s):
    text = re.sub(r"\s+", " ", s.get("title") or s.get("first_prompt") or "").strip()[:80]
    return f"{tool} {s['id']} {s['age']} · {s['n_prompts']} prompts · {text}"


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: find.py <topic>")
    topic = sys.argv[1]
    codex = (Path.home() / ".codex" / "sessions").is_dir()
    found = [("claude", s) for s in sessions(CLAUDE, topic)]
    if codex:
        found += [("codex", s) for s in sessions(CODEX, topic)]
    found = [(tool, s) for tool, s in found if not is_recall(s)]
    found.sort(key=lambda f: f[1]["modified"], reverse=True)
    for tool, s in found[:NEWEST]:
        print(line(tool, s))
    if len(found) > NEWEST:
        print(f"Skipped {len(found) - NEWEST} older sessions.")
    if not codex:
        print("Codex is not installed: Claude Code sessions only.")
    if not found:
        print(f"No sessions on {topic}.")
        sys.exit(1)


if __name__ == "__main__":
    main()
