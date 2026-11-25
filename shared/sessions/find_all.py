#!/usr/bin/env python3
"""Every harness's sessions for a project, in one call.

Every folder next to this file that has an adapter.py is a harness; each
installed one's finder runs once. no-adapter.tsv names, per harness with no
adapter, the file or folder under HOME where it keeps its data. Such a path
that changed in the window is reported, so a harness is never skipped
silently. It is never read.

    find_all.py --root R... | --all-projects  [--since D] [--until D] [--query Q] [--id PREFIX]...

Prints {"harnesses": [{"harness", "label", "installed"}, plus "error" when its finder failed],
        "sessions": [adapter find rows, harness by harness, each in its finder's order],
        "unread": [{"harness", "path", "line"}]}.
"""

import argparse
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    # Loaded by path: `python3 -I` leaves the script's folder off sys.path.
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


lib = load("adapter_lib", os.path.join(HERE, "adapter_lib.py"))


def unread(args):
    scope = lib.scope_of(args)
    out = []
    with open(os.path.join(HERE, "no-adapter.tsv"), encoding="utf-8") as h:
        for line in h:
            if not line.strip():
                continue
            name, rel = line.rstrip("\n").split("\t")
            path = os.path.join(os.path.expanduser("~"), rel)
            try:
                changed = os.path.getmtime(path)
            except OSError:
                continue
            if not scope.in_window(changed):
                continue
            out.append({"harness": name, "path": path, "line": f"found {name} sessions, cannot read them yet"})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    lib.find_args(ap)
    args = ap.parse_args()
    folders = sorted(f for f in os.listdir(HERE) if os.path.isfile(os.path.join(HERE, f, "adapter.py")))
    harnesses, rows = [], []
    for folder in folders:
        h = load(f"{folder}_adapter", os.path.join(HERE, folder, "adapter.py")).HARNESS
        entry = {"harness": h.name, "label": h.label, "installed": lib.installed(h)}
        if entry["installed"]:
            try:
                rows += lib.find(h, args)
            except lib.Failed as e:
                entry["error"] = str(e)
        harnesses.append(entry)
    print(json.dumps({"harnesses": harnesses, "sessions": rows, "unread": unread(args)}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
