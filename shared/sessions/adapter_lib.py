"""The adapter contract every harness folder under sessions/ keeps.

A harness folder with an ``adapter.py`` is one harness retro can read. Its
adapter calls this module's ``main`` with the harness's own finder and
extractor, and gets the same three subcommands as every other adapter:

    adapter.py probe   --root R... | --all-projects  [--since D] [--until D]
    adapter.py find    --root R... | --all-projects  [--since D] [--until D] [--query Q] [--id PREFIX]...
    adapter.py extract <path> [--max-result-chars N]

``probe`` prints {"harness", "sessions"}. ``find`` prints a JSON list of rows
{"harness", "id", "modified", "cwd", "title", "size", "path", "subagents",
"score", "current", "prompts", "first_prompt", "age", "active"}, plus
"unreadable" on a row the harness could not read. Dates are local YYYY-MM-DD
and count a session by its last activity. "score" is the finder's match score
for --query (0 with none), "current" is true for the session the command runs
in, "prompts" counts its prompts, "age" reads as "3h ago", and "active" is its
last activity in epoch seconds, for sorting. The finders keep their
own flags and keys for the skills that call them direct; this hides those
differences.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from typing import Callable


class Harness:
    """One harness: its name, its finder and extractor scripts, the finder
    flags for (roots, or None for every project; days, or None for all time),
    the finder row's title, and the environment variable that holds the id of
    the session a command runs in."""

    def __init__(self, name: str, finder: str, extractor: str,
                 flags: Callable[[list | None, int | None], list], title: Callable[[dict], str],
                 current: str):
        self.name, self.finder, self.extractor, self.flags, self.title = name, finder, extractor, flags, title
        self.current = current


def _day(value: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a YYYY-MM-DD date: {value}")


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="One harness's sessions, in the shape every adapter shares.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for cmd in ("probe", "find"):
        p = sub.add_parser(cmd)
        where = p.add_mutually_exclusive_group(required=True)
        where.add_argument("--root", action="append", help="a project folder; repeat for several, subfolders count")
        where.add_argument("--all-projects", action="store_true")
        p.add_argument("--since", type=_day, help="first day of last activity, YYYY-MM-DD")
        p.add_argument("--until", type=_day, help="last day of last activity, YYYY-MM-DD")
        if cmd == "find":
            p.add_argument("--query", default="", help="keywords the finder scores")
            p.add_argument("--id", action="append", default=[], help="keep sessions whose id starts with this")
    p = sub.add_parser("extract")
    p.add_argument("path")
    p.add_argument("--max-result-chars", type=int, default=300)
    return ap


def _find(h: Harness, args) -> list[dict]:
    roots = None if args.all_projects else [os.path.abspath(os.path.expanduser(r)) for r in args.root]
    days = (dt.date.today() - args.since).days + 1 if args.since else None
    if days is not None and days < 1:
        return []
    query = getattr(args, "query", "")
    ids = getattr(args, "id", [])
    cmd = [sys.executable, h.finder, query, *h.flags(roots, days), "--json", "--limit", "0"]
    if not query:
        cmd.append("--all")
    done = subprocess.run(cmd, capture_output=True, text=True)
    try:
        out = json.loads(done.stdout)
    except ValueError:
        last = (done.stderr or done.stdout).strip().splitlines()[-1:] or ["no output"]
        raise SystemExit(f"stop: {h.name} finder failed: {last[0]}")
    if out.get("error"):
        return []
    rows = []
    current = os.environ.get(h.current, "")
    for s in out.get("sessions", []):
        modified = dt.date.fromtimestamp(float(s["modified"]))
        if args.until and modified > args.until:
            continue
        if ids and not any(str(s.get("id", "")).startswith(i) for i in ids):
            continue
        rows.append({"harness": h.name, "id": s.get("id"), "modified": modified.isoformat(),
                     "cwd": s.get("cwd"), "title": h.title(s), "size": s.get("size"),
                     "path": s.get("path"), "subagents": s.get("subagents") or [],
                     "score": s.get("score"), "current": bool(current) and s.get("id") == current,
                     "prompts": s.get("n_prompts"), "first_prompt": s.get("first_prompt"),
                     "age": s.get("age"), "active": float(s["modified"])})
    # An unreadable session's id and project are inside it; its file name holds
    # the id, and the finder already kept it to the window's start.
    for u in out.get("unreadable", []):
        modified = dt.date.fromtimestamp(float(u["modified"]))
        if args.until and modified > args.until:
            continue
        if ids and not any(i in os.path.basename(u["path"]) for i in ids):
            continue
        rows.append({"harness": h.name, "id": None, "modified": modified.isoformat(), "cwd": None, "title": None,
                     "size": None, "path": u["path"], "subagents": [], "score": None, "current": False,
                     "prompts": None, "first_prompt": None, "age": None, "active": float(u["modified"]),
                     "unreadable": f"{u['why']}, project unknown"})
    return rows


def main(h: Harness) -> int:
    args = _parser().parse_args()
    if args.cmd == "extract":
        return subprocess.run([sys.executable, h.extractor, args.path,
                               "--max-result-chars", str(args.max_result_chars)]).returncode
    rows = _find(h, args)
    if args.cmd == "probe":
        print(json.dumps({"harness": h.name, "sessions": sum(1 for r in rows if not r.get("unreadable"))}))
    else:
        print(json.dumps(rows, indent=2, ensure_ascii=False))
    return 0
