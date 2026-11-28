"""The adapter contract every harness folder under sessions/ keeps.

A harness folder with an ``adapter.py`` is one harness retrospect can read. Its
adapter calls this module's ``main`` with the harness's own finder and
extractor, and gets the same two subcommands as every other adapter:

    adapter.py find    --root R... | --all-projects  [--since D] [--until D] [--query Q] [--id PREFIX]...
    adapter.py extract <id or path> [--summary] [--after-compact] [--max-result-chars N]

A harness that keeps none of its folders on this machine is not installed,
and its ``find`` prints []. ``find`` prints a JSON list of rows
{"harness", "id", "modified", "cwd", "title", "size", "path", "subagents",
"score", "current", "prompts", "first_prompt", "age", "active"}, plus
"unreadable" on a row the harness could not read. Dates are local YYYY-MM-DD
and count a session by its last activity. "score" is the finder's match score
for --query (0 with none), "current" is true for the session the command runs
in, "prompts" counts its prompts, "age" reads as "3h ago", and "active" is its
last activity in epoch seconds, for sorting. ``extract --summary`` renders
only the prompts and the replies; ``--after-compact`` starts at the last
compaction summary in a harness that has one, and a harness with none renders
the whole session. The finders keep their own flags and keys; this hides
those differences. find_all.py, next to
this file, runs every adapter's find in one call through ``find`` and
``installed``. ``load`` loads a sibling module by its path, and ``injected`` says whether
a user message is text a harness put there.
"""

from __future__ import annotations

import argparse
import codecs
import datetime as dt
import importlib.util
import json
import os
import subprocess
import sys
import time
from typing import Callable


class Harness:
    """One harness: its name and its name for people, the folders it keeps
    sessions in, its finder and extractor scripts, every flag its finder takes
    for (roots, or None for every project; days, or None for all time), the
    output flags too, the finder row's title, the environment variable that
    holds the id of the session a command runs in, and the extract flags its
    extractor takes, --max-result-chars among them."""

    def __init__(self, name: str, label: str, data: list, finder: str, extractor: str,
                 flags: Callable[[list | None, int | None], list], title: Callable[[dict], str],
                 current: str, extract_flags: tuple[str, ...]):
        self.name, self.label, self.data = name, label, data
        self.finder, self.extractor, self.flags, self.title = finder, extractor, flags, title
        self.current, self.extract_flags = current, extract_flags


def first_day(days: int | None) -> dt.date | None:
    """The first day of the last N days, today counted as the first."""
    return dt.date.today() - dt.timedelta(days=days - 1) if days else None


class Scope:
    """Which sessions a find keeps: those whose cwd is a root, or below one
    with subdirs (roots None: every project), and whose last activity falls
    from since to until, in local days, both ends kept."""

    # A plain class, not a dataclass: most loaders run this file without
    # putting it in sys.modules, and a dataclass fails that way on Python 3.11
    # and older.
    def __init__(self, roots, subdirs: bool = False, since: dt.date | None = None,
                 until: dt.date | None = None):
        self.roots = None if roots is None else tuple(os.path.abspath(os.path.expanduser(r)) for r in roots)
        self.subdirs, self.since, self.until = subdirs, since, until

    @classmethod
    def last_days(cls, roots, subdirs: bool, days: int | None) -> "Scope":
        return cls(roots, subdirs, first_day(days))

    def days(self) -> int | None:
        """The window as the day count a finder's flag takes."""
        return (dt.date.today() - self.since).days + 1 if self.since else None

    def in_roots(self, cwd) -> bool:
        if self.roots is None:
            return True
        if not cwd:
            return False
        c = os.path.normpath(os.path.expanduser(cwd))
        return any(c == r or (self.subdirs and c.startswith(r.rstrip(os.sep) + os.sep)) for r in self.roots)

    def in_window(self, when: float) -> bool:
        d = dt.date.fromtimestamp(when)
        return not (self.since and d < self.since) and not (self.until and d > self.until)


def scope_of(args) -> Scope:
    """A find's scope. Subfolders count, since every adapter asks its finder
    for them."""
    return Scope(None if args.all_projects else args.root, True, args.since, args.until)


def age(mtime: float) -> str:
    """The row's "age": how long ago mtime was, as "3h ago"."""
    mins = max(0.0, time.time() - mtime) / 60
    if mins < 60:
        return f"{int(mins)}m ago"
    if mins < 60 * 24:
        return f"{int(mins / 60)}h ago"
    days = mins / 60 / 24
    if days < 14:
        return f"{int(days)}d ago"
    return f"{int(days / 7)}w ago"


def load(name, path):
    """The module at path, under name."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    # Registered before it runs: dataclasses looks a module up in sys.modules, and
    # Python 3.11 and older fail on a dataclass in it without this.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# What a harness puts at the start of a user message the user did not type:
# Claude Code's command output and shell wrappers, then Codex's instructions
# and context blocks.
INJECTED = (
    "<local-command-caveat>",
    "<local-command-stdout>",
    "<command-stdout>",
    "<bash-stdout>",
    "<bash-input>",
    "# AGENTS.md instructions",
    "AGENTS.md instructions for",
    "<INSTRUCTIONS>",
    "<environment_context>",
    "<user_instructions>",
    "# Collaboration Mode",
    "<user_shell_environment>",
    "<recommended_plugins>",
    "========= MEMORY_SUMMARY BEGINS =========",
)


def injected(text: str) -> bool:
    """True when a user message is text a harness injected, not a prompt."""
    return text.lstrip().startswith(INJECTED)


def _day(value: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a YYYY-MM-DD date: {value}")


def find_args(p: argparse.ArgumentParser) -> None:
    """The arguments of a find: where, when, and what."""
    where = p.add_mutually_exclusive_group(required=True)
    where.add_argument("--root", action="append", help="a project folder; repeat for several, subfolders count")
    where.add_argument("--all-projects", action="store_true")
    p.add_argument("--since", type=_day, help="first day of last activity, YYYY-MM-DD")
    p.add_argument("--until", type=_day, help="last day of last activity, YYYY-MM-DD")
    p.add_argument("--query", default="", help="keywords the finder scores")
    p.add_argument("--id", action="append", default=[], help="keep sessions whose id starts with this")


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="One harness's sessions, in the shape every adapter shares.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    find_args(sub.add_parser("find"))
    p = sub.add_parser("extract")
    p.add_argument("path", help="a session id or the path of its file")
    p.add_argument("--summary", action="store_true", help="only the prompts and the replies")
    p.add_argument("--after-compact", action="store_true",
                   help="start at the last compaction summary, where the harness has one")
    p.add_argument("--max-result-chars", type=int, default=300)
    return ap


class Failed(Exception):
    """A finder that printed no JSON."""


def installed(h: Harness) -> bool:
    """With none of its folders here the harness is not installed, and its finder is not run."""
    return any(os.path.isdir(d) for d in h.data)


def find(h: Harness, args) -> list[dict]:
    scope = scope_of(args)
    if scope.since and scope.since > dt.date.today():
        return []
    query = getattr(args, "query", "")
    ids = getattr(args, "id", [])
    cmd = [sys.executable, h.finder, query, *h.flags(None if scope.roots is None else list(scope.roots), scope.days())]
    if not query:
        cmd.append("--all")
    # Both ends pinned to UTF-8: an inherited PYTHONIOENCODING or locale would
    # make the finder write in one encoding and this side read in another.
    try:
        done = subprocess.run(cmd, capture_output=True, encoding="utf-8",
                              env={**os.environ, "PYTHONIOENCODING": "utf-8"})
    except UnicodeDecodeError:
        raise Failed(f"{h.name} finder failed: output is not UTF-8")
    try:
        out = json.loads(done.stdout)
    except ValueError:
        last = (done.stderr or done.stdout).strip().splitlines()[-1:] or ["no output"]
        raise Failed(f"{h.name} finder failed: {last[0]}")
    rows = []
    current = os.environ.get(h.current, "")
    for s in out.get("sessions", []):
        if not scope.in_window(float(s["modified"])):
            continue
        modified = dt.date.fromtimestamp(float(s["modified"]))
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
        if not scope.in_window(float(u["modified"])):
            continue
        modified = dt.date.fromtimestamp(float(u["modified"]))
        if ids and not any(i in os.path.basename(u["path"]) for i in ids):
            continue
        rows.append({"harness": h.name, "id": None, "modified": modified.isoformat(), "cwd": None, "title": None,
                     "size": None, "path": u["path"], "subagents": [], "score": None, "current": False,
                     "prompts": None, "first_prompt": None, "age": None, "active": float(u["modified"]),
                     "unreadable": f"{u['why']}, project unknown"})
    return rows


def print_json(obj) -> None:
    # Raw text only when stdout is UTF-8: a Latin-1 PYTHONIOENCODING cannot
    # write an emoji, and JSON's \u escapes read the same under any encoding.
    utf8 = codecs.lookup(sys.stdout.encoding or "ascii").name == "utf-8"
    print(json.dumps(obj, indent=2, ensure_ascii=not utf8))


def main(h: Harness) -> int:
    args = _parser().parse_args()
    if args.cmd == "extract":
        # A flag this harness's extractor lacks is dropped, so one call fits every harness.
        asked = [f for f, on in (("--summary", args.summary), ("--after-compact", args.after_compact))
                 if on and f in h.extract_flags]
        if "--max-result-chars" in h.extract_flags:
            asked += ["--max-result-chars", str(args.max_result_chars)]
        return subprocess.run([sys.executable, h.extractor, args.path, *asked]).returncode
    try:
        rows = find(h, args) if installed(h) else []
    except Failed as e:
        sys.exit(f"stop: {e}")
    print_json(rows)
    return 0
