#!/usr/bin/env python3
"""Claude Code's adapter: find and extract, per ../adapter_lib.py.

Reads ~/.claude/projects/ through find_sessions.py and extract_session.py,
next to this file.
"""

import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
# `python3 -I` leaves the script's folder off sys.path, so the sessions folder goes on it here.
sys.path.insert(0, os.path.dirname(here))
import adapter_lib as lib  # noqa: E402  # adapter_lib imports only after the sys.path line above


def flags(roots, days):
    where = ["--all-projects"] if roots is None else [f for r in roots for f in ("--project-dir", r)] + ["--include-subdirs"]
    return where + (["--days", str(days)] if days else []) + ["--json", "--limit", "0"]


HARNESS = lib.Harness(
    name=os.path.basename(here),
    label="Claude Code",
    data=[os.path.expanduser("~/.claude/projects")],
    finder=os.path.join(here, "find_sessions.py"),
    extractor=os.path.join(here, "extract_session.py"),
    flags=flags,
    title=lambda s: s.get("title") or s.get("first_prompt") or "",
    current="CLAUDE_CODE_SESSION_ID",
    extract_flags=("--summary", "--after-compact", "--max-result-chars"),
)


if __name__ == "__main__":
    raise SystemExit(lib.main(HARNESS))
