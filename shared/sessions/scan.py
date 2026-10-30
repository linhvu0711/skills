#!/usr/bin/env python3
"""Which harnesses hold sessions for a project, and which ones nothing here can read.

Every folder next to this file that has an adapter.py is a harness retro can
read; scan runs each one's probe. no-adapter.tsv names, per harness with no
adapter, the file or folder under HOME where it keeps its data. Such a path
that changed in the window is reported, so a harness is never skipped
silently. It is never read.

    scan.py --root R... | --all-projects  [--since YYYY-MM-DD] [--until YYYY-MM-DD]

Prints {"adapters": [{"harness", "sessions"} or {"harness", "error"}],
        "unread": [{"harness", "path", "line"}]}.
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def probe(folder, args):
    cmd = [sys.executable, os.path.join(HERE, folder, "adapter.py"), "probe"]
    cmd += ["--all-projects"] if args.all_projects else [f for r in args.root for f in ("--root", r)]
    cmd += [f"--{k}={v}" for k, v in (("since", args.since), ("until", args.until)) if v]
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0:
        last = (done.stderr.strip().splitlines() or ["exit %d" % done.returncode])[-1]
        return {"harness": folder, "error": last}
    return json.loads(done.stdout)


def unread(args):
    since = dt.date.fromisoformat(args.since) if args.since else None
    out = []
    with open(os.path.join(HERE, "no-adapter.tsv"), encoding="utf-8") as h:
        for line in h:
            if not line.strip():
                continue
            name, rel = line.rstrip("\n").split("\t")
            path = os.path.join(os.path.expanduser("~"), rel)
            try:
                changed = dt.date.fromtimestamp(os.path.getmtime(path))
            except OSError:
                continue
            if since and changed < since:
                continue
            out.append({"harness": name, "path": path, "line": f"found {name} sessions, cannot read them yet"})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    where = ap.add_mutually_exclusive_group(required=True)
    where.add_argument("--root", action="append")
    where.add_argument("--all-projects", action="store_true")
    ap.add_argument("--since")
    ap.add_argument("--until")
    args = ap.parse_args()
    folders = sorted(f for f in os.listdir(HERE) if os.path.isfile(os.path.join(HERE, f, "adapter.py")))
    print(json.dumps({"adapters": [probe(f, args) for f in folders], "unread": unread(args)}, indent=2))


if __name__ == "__main__":
    main()
