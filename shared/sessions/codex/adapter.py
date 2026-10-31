#!/usr/bin/env python3
"""Codex CLI's adapter: probe, find, and extract, per ../adapter_lib.py.

Reads ~/.codex/sessions/ and ~/.codex/archived_sessions/ through
find_session.py and extract_session.py, next to this file. Headless
`codex exec` runs are left out, and a resumed session counts by its last
activity, not the day folder it started in.
"""

import importlib.util
import os

here = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    # Loaded by path: `python3 -I` leaves the script's folder off sys.path.
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


lib = load("adapter_lib", os.path.join(here, "..", "adapter_lib.py"))
rollout_io = load("rollout_io", os.path.join(here, "rollout_io.py"))


def flags(roots, days):
    where = ["--all-projects"] if roots is None else [f for r in roots for f in ("--cwd", r)] + ["--include-subdirs"]
    return where + ["--interactive"] + (["--active-days", str(days)] if days else [])


if __name__ == "__main__":
    raise SystemExit(lib.main(lib.Harness(
        name=os.path.basename(here),
        label="Codex",
        data=rollout_io.data_folders(),
        finder=os.path.join(here, "find_session.py"),
        extractor=os.path.join(here, "extract_session.py"),
        flags=flags,
        title=lambda s: s.get("first_prompt") or "",
        current="CODEX_THREAD_ID",
        extract_flags=("--summary",),
    )))
