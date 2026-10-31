#!/usr/bin/env python3
"""Claude Code's adapter: probe, find, and extract, per ../adapter_lib.py.

Reads ~/.claude/projects/ through find_sessions.py and extract_session.py,
next to this file.
"""

import importlib.util
import os

here = os.path.dirname(os.path.abspath(__file__))
# Loaded by path: `python3 -I` leaves the script's folder off sys.path.
spec = importlib.util.spec_from_file_location("adapter_lib", os.path.join(here, "..", "adapter_lib.py"))
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)


def flags(roots, days):
    where = ["--all-projects"] if roots is None else [f for r in roots for f in ("--project-dir", r)] + ["--include-subdirs"]
    return where + (["--days", str(days)] if days else [])


if __name__ == "__main__":
    raise SystemExit(lib.main(lib.Harness(
        name=os.path.basename(here),
        finder=os.path.join(here, "find_sessions.py"),
        extractor=os.path.join(here, "extract_session.py"),
        flags=flags,
        title=lambda s: s.get("title") or s.get("first_prompt") or "",
        current="CLAUDE_CODE_SESSION_ID",
    )))
