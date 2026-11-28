#!/usr/bin/env python3
"""Codex CLI's adapter: find and extract, per ../adapter_lib.py.

Reads ~/.codex/sessions/ and ~/.codex/archived_sessions/ through
find_session.py and extract_session.py, next to this file. Headless
`codex exec` runs are left out, and a resumed session counts by its last
activity, not the day folder it started in.
"""

import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
# `python3 -I` leaves the script's folder off sys.path, so the sessions folder goes on it here.
sys.path.insert(0, os.path.dirname(here))
import adapter_lib as lib  # noqa: E402  # adapter_lib imports only after the sys.path line above

rollout_io = lib.load("rollout_io", os.path.join(here, "rollout_io.py"))


def flags(roots, days):
    where = ["--all-projects"] if roots is None else [f for r in roots for f in ("--cwd", r)] + ["--include-subdirs"]
    return where + ["--interactive"] + (["--active-days", str(days)] if days else []) + ["--json", "--limit", "0"]


HARNESS = lib.Harness(
    name=os.path.basename(here),
    label="Codex",
    data=rollout_io.data_folders(),
    finder=os.path.join(here, "find_session.py"),
    extractor=os.path.join(here, "extract_session.py"),
    flags=flags,
    title=lambda s: s.get("first_prompt") or "",
    current="CODEX_THREAD_ID",
    extract_flags=("--summary", "--max-result-chars"),
)


if __name__ == "__main__":
    raise SystemExit(lib.main(HARNESS))
