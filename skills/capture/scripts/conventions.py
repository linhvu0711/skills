#!/usr/bin/env python3
"""Store for per-repo issue conventions.

Two backing files, split by how general the data is:

  Priority store (general, reusable by any issue tool):
    $GH_PRIORITY_STORE or ~/.config/gh-issues/priority-labels.json
    Shape: { "owner/repo": {"p0": "...", "p1": "...", "p2": "...", "p3": "..."} }
    This is a plain, tool-agnostic contract. Any skill that files issues may
    read it directly as JSON, or call `priority-get` below. It is NOT tied to
    the capture skill.

  Seed store (capture-only: how this repo names a seed):
    $CAPTURE_STORE or ~/.config/capture/conventions.json
    Shape: { "owner/repo": {"prefix": "...", "seed_label": "...",
                            "bug_label": "...",
                            "sampled": N, "learned_at": "YYYY-MM-DD"} }
    An entry saved before bug_label existed reads back with "bug".

Usage:
  conventions.py get <owner/repo>
      Print the merged entry as JSON (exit 0), or "MISS" (exit 3).
      A hit needs the seed store entry; priority may be absent.
  conventions.py priority-get <owner/repo>
      Print only the priority mapping as JSON (exit 0), or "MISS" (exit 3).
      The general entry point other issue tools can call.
  conventions.py priority-set <owner/repo> --p0 L0 --p1 L1 --p2 L2 --p3 L3
      Save only the priority labels. For issue tools that learned the
      priority names but have no seed data (to-issue, to-epic).
  conventions.py set <owner/repo> --prefix P --seed-label L [--bug-label B] \
      --p0 L0 --p1 L1 --p2 L2 --p3 L3 [--sampled N]
      Save the seed bits to the seed store and the priority labels to the
      priority store. Prints the merged entry.
  conventions.py forget <owner/repo>
      Remove the entry from both stores. Always exits 0.

A corrupt store is moved aside to <name>.bak-<timestamp> and treated as
empty, so a bad file never blocks a capture.
"""
import argparse
import json
import os
import sys
import time

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
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, store)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("get")
    g.add_argument("repo")

    pg = sub.add_parser("priority-get")
    pg.add_argument("repo")

    ps = sub.add_parser("priority-set")
    ps.add_argument("repo")
    for lvl in ("p0", "p1", "p2", "p3"):
        ps.add_argument(f"--{lvl}", required=True, help=f"label name for {lvl}")

    s = sub.add_parser("set")
    s.add_argument("repo")
    s.add_argument("--prefix", required=True, help='e.g. "[seed] " or "seed: "')
    s.add_argument("--seed-label", required=True)
    s.add_argument("--bug-label", default="bug", help='label for a [bug]; default "bug"')
    for lvl in ("p0", "p1", "p2", "p3"):
        s.add_argument(f"--{lvl}", required=True, help=f"label name for {lvl}")
    s.add_argument("--sampled", type=int, default=0, help="issues inspected when learning")

    f = sub.add_parser("forget")
    f.add_argument("repo")

    a = ap.parse_args()
    repo = a.repo.strip().lower()

    if a.cmd == "priority-get":
        entry = load(PRIORITY_STORE).get(repo)
        if not entry:
            print("MISS")
            sys.exit(3)
        print(json.dumps(entry, indent=2, sort_keys=True))
        return

    if a.cmd == "priority-set":
        prios = load(PRIORITY_STORE)
        prios[repo] = {"p0": a.p0, "p1": a.p1, "p2": a.p2, "p3": a.p3}
        save(PRIORITY_STORE, prios)
        print(json.dumps(prios[repo], indent=2, sort_keys=True))
        return

    if a.cmd == "get":
        seed = load(SEED_STORE).get(repo)
        if not seed:
            print("MISS")
            sys.exit(3)
        merged = dict(seed)
        merged.setdefault("bug_label", "bug")
        prio = load(PRIORITY_STORE).get(repo)
        if prio:
            merged["priority"] = prio
        print(json.dumps(merged, indent=2, sort_keys=True))
        return

    if a.cmd == "set":
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
        print(json.dumps(merged, indent=2, sort_keys=True))
        return

    if a.cmd == "forget":
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
