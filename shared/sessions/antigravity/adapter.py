#!/usr/bin/env python3
"""Antigravity's adapter: probe, find, and extract, per ../adapter_lib.py.

Reads the chats in store.folders() through find_session.py and
extract_session.py, next to this file.
"""

import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    # Loaded by path: `python3 -I` leaves the script's folder off sys.path.
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    # Registered before it runs: dataclasses looks a module up in sys.modules, and
    # Python 3.11 and older fail on store.py's Chat without it.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


lib = load("adapter_lib", os.path.join(here, "..", "adapter_lib.py"))
store = load("store", os.path.join(here, "store.py"))


def flags(roots, days):
    where = ["--all-projects"] if roots is None else [f for r in roots for f in ("--cwd", r)] + ["--include-subdirs"]
    return where + (["--active-days", str(days)] if days else [])


if __name__ == "__main__":
    raise SystemExit(lib.main(lib.Harness(
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
    )))
