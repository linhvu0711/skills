#!/usr/bin/env python3
"""Per-repo issue conventions, for every skill that files or reads issues.

Three stores, one per kind of fact. An env var moves each one.

  Issue types: $GH_ISSUE_STORE or ~/.config/gh-issues/issue-conventions.json
    { "owner/repo": {
        "style": "bracket" | "colon",        # "[FEAT] title" or "feat: title"
        "words": {"fix": "bug"},             # type word the repo uses when it differs from ours
        "size":  {"XS": "size/XS", "S": "size/S", "M": "size/M", "L": "size/L"},
        "sampled": N, "learned_at": "YYYY-MM-DD" } }

  Priority: $GH_PRIORITY_STORE or ~/.config/gh-issues/priority-labels.json
    { "owner/repo": {"p0": "...", "p1": "...", "p2": "...", "p3": "..."} }

  Seed (how a repo names a capture seed or bug):
    $CAPTURE_STORE or ~/.config/capture/conventions.json
    { "owner/repo": {"prefix": "...", "seed_label": "...", "bug_label": "...",
                     "sampled": N, "learned_at": "YYYY-MM-DD"} }
    An entry saved before bug_label existed reads back with "bug".

Usage:
  issue_conventions.py get <owner/repo>
      The issue type entry, with "priority" merged in when the repo has
      priority labels, as JSON (exit 0), or "MISS" (exit 3).
  issue_conventions.py set <owner/repo> --style bracket|colon
      --xs L --s L --m L --l L [--word fix=bug ...] [--sampled N]
  issue_conventions.py forget <owner/repo>
      Remove the issue type entry only.
  issue_conventions.py priority-get <owner/repo>
      Only the priority labels as JSON (exit 0), or "MISS" (exit 3).
  issue_conventions.py priority-set <owner/repo> --p0 L0 --p1 L1 --p2 L2 --p3 L3
  issue_conventions.py seed-get <owner/repo>
      The seed entry, with "priority" merged in, as JSON (exit 0), or "MISS"
      (exit 3). A hit needs the seed entry; priority may be absent.
  issue_conventions.py seed-set <owner/repo> --prefix P --seed-label L [--bug-label B] \
      --p0 L0 --p1 L1 --p2 L2 --p3 L3 [--sampled N]
      Save the seed entry and the priority labels. Prints the merged entry.
  issue_conventions.py seed-forget <owner/repo>
      Remove the repo's seed entry and its priority labels. Always exits 0.

A corrupt store is moved aside to <name>.bak-<timestamp> and treated as
empty, so a bad file never blocks a caller.
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
SEED_STORE = os.environ.get("CAPTURE_STORE") or os.path.expanduser(
    "~/.config/capture/conventions.json"
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
    try:
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, store)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def with_priority(repo, entry):
    merged = dict(entry)
    prio = load(PRIORITY_STORE).get(repo)
    if prio:
        merged["priority"] = prio
    return merged


def show(entry):
    print(json.dumps(entry, indent=2, sort_keys=True))


def miss():
    print("MISS")
    sys.exit(3)


def priority_args(p):
    for lvl in ("p0", "p1", "p2", "p3"):
        p.add_argument(f"--{lvl}", required=True, help=f"label name for {lvl}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("get").add_argument("repo")

    s = sub.add_parser("set")
    s.add_argument("repo")
    s.add_argument("--style", required=True, choices=("bracket", "colon"))
    for size in ("xs", "s", "m", "l"):
        s.add_argument(f"--{size}", required=True, help=f"label name for {size.upper()}")
    s.add_argument("--word", action="append", default=[],
                   help="type=repo_word, e.g. fix=bug. Repeatable.")
    s.add_argument("--sampled", type=int, default=0)

    sub.add_parser("forget").add_argument("repo")

    sub.add_parser("priority-get").add_argument("repo")

    ps = sub.add_parser("priority-set")
    ps.add_argument("repo")
    priority_args(ps)

    sub.add_parser("seed-get").add_argument("repo")

    ss = sub.add_parser("seed-set")
    ss.add_argument("repo")
    ss.add_argument("--prefix", required=True, help='e.g. "[seed] " or "seed: "')
    ss.add_argument("--seed-label", required=True)
    ss.add_argument("--bug-label", default="bug", help='label for a [bug]; default "bug"')
    priority_args(ss)
    ss.add_argument("--sampled", type=int, default=0, help="issues inspected when learning")

    sub.add_parser("seed-forget").add_argument("repo")

    a = ap.parse_args()
    repo = a.repo.strip().lower()

    if a.cmd == "get":
        entry = load(STORE).get(repo)
        if not entry:
            miss()
        show(with_priority(repo, entry))
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
        show(with_priority(repo, data[repo]))
        return

    if a.cmd == "forget":
        data = load(STORE)
        if repo in data:
            del data[repo]
            save(STORE, data)
            print(f"forgot {repo}")
        else:
            print(f"nothing saved for {repo}")
        return

    if a.cmd == "priority-get":
        entry = load(PRIORITY_STORE).get(repo)
        if not entry:
            miss()
        show(entry)
        return

    if a.cmd == "priority-set":
        prios = load(PRIORITY_STORE)
        prios[repo] = {"p0": a.p0, "p1": a.p1, "p2": a.p2, "p3": a.p3}
        save(PRIORITY_STORE, prios)
        show(prios[repo])
        return

    if a.cmd == "seed-get":
        seed = load(SEED_STORE).get(repo)
        if not seed:
            miss()
        merged = with_priority(repo, seed)
        merged.setdefault("bug_label", "bug")
        show(merged)
        return

    if a.cmd == "seed-set":
        seeds = load(SEED_STORE)
        seeds[repo] = {
            "prefix": a.prefix,
            "seed_label": a.seed_label,
            "bug_label": a.bug_label,
            "sampled": a.sampled,
            "learned_at": time.strftime("%Y-%m-%d"),
        }
        save(SEED_STORE, seeds)

        prios = load(PRIORITY_STORE)
        prios[repo] = {"p0": a.p0, "p1": a.p1, "p2": a.p2, "p3": a.p3}
        save(PRIORITY_STORE, prios)

        merged = dict(seeds[repo])
        merged["priority"] = prios[repo]
        show(merged)
        return

    if a.cmd == "seed-forget":
        hit = False
        for store in (SEED_STORE, PRIORITY_STORE):
            data = load(store)
            if repo in data:
                del data[repo]
                save(store, data)
                hit = True
        print(f"forgot {repo}" if hit else f"nothing saved for {repo}")


if __name__ == "__main__":
    main()
