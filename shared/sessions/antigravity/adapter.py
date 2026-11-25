#!/usr/bin/env python3
"""Antigravity's adapter: find and extract, per ../adapter_lib.py.

Reads the chats in store.folders() through find_session.py and
extract_session.py, next to this file.
"""

import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
# `python3 -I` leaves the script's folder off sys.path, so the sessions folder goes on it here.
sys.path.insert(0, os.path.dirname(here))
import adapter_lib as lib  # noqa: E402

store = lib.load("store", os.path.join(here, "store.py"))


def flags(roots, days):
    where = ["--all-projects"] if roots is None else [f for r in roots for f in ("--cwd", r)] + ["--include-subdirs"]
    return where + (["--active-days", str(days)] if days else [])


HARNESS = lib.Harness(
    name=os.path.basename(here),
    label="Antigravity",
    data=store.folders(),
    finder=os.path.join(here, "find_session.py"),
    extractor=os.path.join(here, "extract_session.py"),
    flags=flags,
    title=lambda s: s.get("title") or s.get("first_prompt") or "",
    # agy sets no environment variable with the chat's id, so no row is this session.
    current="",
    extract_flags=(),
)


if __name__ == "__main__":
    raise SystemExit(lib.main(HARNESS))
