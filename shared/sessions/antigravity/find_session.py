#!/usr/bin/env python3
"""Find Antigravity chats for ../adapter_lib.py's `find`.

    find_session.py <query> (--cwd R... [--include-subdirs] | --all-projects)
                    [--active-days N] [--all] [--limit N] [--json]

Prints {"sessions": [...], "unreadable": [...]} and nothing else, since only
the adapter calls it. A row holds id, cwd, title, first_prompt, n_prompts,
score, path, size, modified (last activity), subagents, and age. A file that is
not a chat is an unreadable item {path, modified, why}.
"""

import argparse
import datetime as dt
import importlib.util
import json
import os

here = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    # Loaded by path: `python3 -I` leaves the script's folder off sys.path.
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


store = load("store", os.path.join(here, "store.py"))
rank = load("rank", os.path.join(here, "..", "rank.py"))
adapter_lib = load("adapter_lib", os.path.join(here, "..", "adapter_lib.py"))

WEIGHTS = {"prompts": 2.0, "body": 1.0}


def in_scope(cwd, roots, subdirs):
    if roots is None:
        return True
    return any(cwd == r or (subdirs and cwd.startswith(r.rstrip("/") + "/")) for r in roots)


def main():
    ap = argparse.ArgumentParser(description="Find Antigravity chats.")
    ap.add_argument("query", nargs="?", default="")
    ap.add_argument("--cwd", action="append", default=[])
    ap.add_argument("--all-projects", action="store_true")
    ap.add_argument("--include-subdirs", action="store_true")
    ap.add_argument("--active-days", type=int)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    roots = None if args.all_projects else [os.path.abspath(r) for r in args.cwd]
    since = dt.date.today() - dt.timedelta(days=args.active_days - 1) if args.active_days else None

    def in_window(t):
        return since is None or dt.date.fromtimestamp(t) >= since

    rows, docs, unreadable = [], [], []
    for folder in store.folders():
        try:
            names = sorted(n for n in os.listdir(folder) if n.endswith(".db"))
        except OSError:
            continue
        for name in names:
            path = os.path.join(folder, name)
            try:
                chat = store.read(path)
            except store.Unreadable as e:
                if in_window(os.path.getmtime(path)):
                    unreadable.append({"path": path, "modified": os.path.getmtime(path), "why": str(e)})
                continue
            if chat is None or not in_window(chat.last) or not in_scope(chat.cwd, roots, args.include_subdirs):
                continue
            prompts = [t for role, t in chat.turns if role == "user"]
            replies = [t for role, t in chat.turns if role == "assistant"]
            rows.append({"id": chat.id, "cwd": chat.cwd, "title": chat.title,
                         "first_prompt": prompts[0] if prompts else "", "n_prompts": len(prompts),
                         "path": chat.path, "size": chat.size, "modified": chat.last, "subagents": []})
            docs.append({"prompts": "\n".join(prompts), "body": "\n".join(replies)})

    kept, _ = rank.pick(rows, docs, args.query, WEIGHTS, args.all)
    shown = kept[: args.limit] if args.limit > 0 else kept
    for r in shown:
        r["age"] = adapter_lib.age(r["modified"])
    print(json.dumps({"sessions": shown, "unreadable": unreadable}, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
