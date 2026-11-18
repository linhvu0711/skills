#!/usr/bin/env python3
"""Per-repo conventions for typed issues (to-issue, to-epic).

Store: $GH_ISSUE_STORE or ~/.config/gh-issues/issue-conventions.json
Shape:
  { "owner/repo": {
      "style": "bracket" | "colon",        # "[FEAT] title" or "feat: title"
      "words": {"fix": "bug"},             # type word the repo uses when it differs from ours
      "size":  {"XS": "size/XS", "S": "size/S", "M": "size/M", "L": "size/L"},
      "sampled": N, "learned_at": "YYYY-MM-DD" } }

Priority labels live in the shared store next to this one
(~/.config/gh-issues/priority-labels.json), owned by the capture skill's
conventions.py. `get` merges them in when present.

Usage:
  conventions.py get <owner/repo>        JSON (exit 0) or "MISS" (exit 3)
  conventions.py set <owner/repo> --style bracket|colon
      --xs L --s L --m L --l L [--word fix=bug ...] [--sampled N]
  conventions.py forget <owner/repo>

A corrupt store is moved aside to <name>.bak-<timestamp> and treated as empty.
"""
import argparse
import json
import os
import sys
import time

STORE = os.environ.get("GH_ISSUE_STORE") or os.path.expanduser(
    "~/.config/gh-issues/issue-conventions.json"
)
PRIORITY_STORE = os.environ.get("GH_PRIORITY_STORE") or os.path.expanduser(
    "~/.config/gh-issues/priority-labels.json"
)


def load(store):
    if not os.path.exists(store):
        return {}
    try:
        with open(store) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
        return data
    except (ValueError, OSError) as e:
        bak = f"{store}.bak-{int(time.time())}"
        try:
            os.replace(store, bak)
            print(f"warning: store was corrupt ({e}); moved to {bak}", file=sys.stderr)
        except OSError:
            print(f"warning: store was corrupt ({e}) and could not be moved", file=sys.stderr)
        return {}


def save(store, data):
    os.makedirs(os.path.dirname(store), exist_ok=True)
    tmp = store + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, store)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("get")
    g.add_argument("repo")

    s = sub.add_parser("set")
    s.add_argument("repo")
    s.add_argument("--style", required=True, choices=("bracket", "colon"))
    for size in ("xs", "s", "m", "l"):
        s.add_argument(f"--{size}", required=True, help=f"label name for {size.upper()}")
    s.add_argument("--word", action="append", default=[],
                   help="type=repo_word, e.g. fix=bug. Repeatable.")
    s.add_argument("--sampled", type=int, default=0)

    f = sub.add_parser("forget")
    f.add_argument("repo")

    a = ap.parse_args()
    repo = a.repo.strip().lower()

    if a.cmd == "get":
        entry = load(STORE).get(repo)
        if not entry:
            print("MISS")
            sys.exit(3)
        merged = dict(entry)
        prio = load(PRIORITY_STORE).get(repo)
        if prio:
            merged["priority"] = prio
        print(json.dumps(merged, indent=2, sort_keys=True))
        return

    if a.cmd == "set":
        words = {}
        for w in a.word:
            k, _, v = w.partition("=")
            if not k or not v:
                ap.error(f"--word needs type=word, got {w!r}")
            words[k] = v
        data = load(STORE)
        data[repo] = {
            "style": a.style,
            "words": words,
            "size": {"XS": a.xs, "S": a.s, "M": a.m, "L": a.l},
            "sampled": a.sampled,
            "learned_at": time.strftime("%Y-%m-%d"),
        }
        save(STORE, data)
        merged = dict(data[repo])
        prio = load(PRIORITY_STORE).get(repo)
        if prio:
            merged["priority"] = prio
        print(json.dumps(merged, indent=2, sort_keys=True))
        return

    if a.cmd == "forget":
        data = load(STORE)
        if repo in data:
            del data[repo]
            save(STORE, data)
            print(f"forgot {repo}")
        else:
            print(f"nothing saved for {repo}")


if __name__ == "__main__":
    main()
