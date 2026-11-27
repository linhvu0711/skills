#!/usr/bin/env python3
"""Print the size of the diff from a base to HEAD: XS, S, M, L, XL, or XXL.

Usage:
  size.py <base>
      Run it in the checkout. <base> is a commit or a branch, as
      origin/main; the diff is <base>...HEAD, from their merge base.

The count is the changed lines, added and removed. Test files count only
when nothing else changed. Lines whose only change is whitespace, blank
lines, lockfiles, and files .gitattributes marks linguist-generated count 0.
The scale is the one in size.md: XS 0-9, S 10-29, M 30-99, L 100-499,
XL 500-999, XXL 1000 or more.

This file runs alone: the cloud handoff rules paste it whole, so it imports
nothing from this repo.
"""

import argparse
import fnmatch
import os
import shutil
import subprocess
import sys

LOCKFILES = {
    "package-lock.json", "pnpm-lock.yaml", "npm-shrinkwrap.json", "bun.lockb",
    "go.sum", "packages.lock.json", "Package.resolved", "conda-lock.yml",
    "pylock.toml",
}
LOCK_PATTERNS = ("*.lock", "*.lockfile", "pylock.*.toml")
TEST_FOLDERS = {"test", "tests", "__tests__"}
TEST_PATTERNS = ("*.test.*", "*.spec.*")
SCALE = ((10, "XS"), (30, "S"), (100, "M"), (500, "L"), (1000, "XL"))


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def is_lockfile(path):
    name = os.path.basename(path)
    return name in LOCKFILES or any(fnmatch.fnmatch(name, p) for p in LOCK_PATTERNS)


def is_test(path):
    parts = path.split("/")
    return bool(TEST_FOLDERS.intersection(parts[:-1])) or any(fnmatch.fnmatch(parts[-1], p) for p in TEST_PATTERNS)


def changed_lines(base):
    """Changed lines per file path, from the -U0 patch.

    --ignore-blank-lines keeps a blank line that sits in a hunk with a real
    change, so blank lines are skipped here too.
    """
    r = git("-c", "core.quotePath=false", "diff", "-U0", "-w", "--ignore-blank-lines", "-M",
            "--no-color", "--no-ext-diff", "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/",
            f"{base}...HEAD")
    if r.returncode != 0:
        sys.exit(f"stop: git diff failed: {r.stderr.strip()}")
    counts = {}
    path, old, in_hunk = None, None, False
    for line in r.stdout.splitlines():
        if line.startswith("diff --git "):
            path, old, in_hunk = None, None, False
        elif not in_hunk and line.startswith("--- "):
            old = line[6:] if line.startswith("--- a/") else None
        elif not in_hunk and line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else old
        elif line.startswith("@@"):
            in_hunk = True
        elif in_hunk and line[:1] in ("+", "-") and line[1:].strip() and path:
            counts[path] = counts.get(path, 0) + 1
    return counts


def generated(paths):
    if not paths:
        return set()
    r = subprocess.run(["git", "check-attr", "-z", "--stdin", "linguist-generated"],
                       input="\0".join(paths) + "\0", capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"stop: git check-attr failed: {r.stderr.strip()}")
    f = r.stdout.split("\0")
    return {f[i] for i in range(0, len(f) - 2, 3) if f[i + 2] in ("set", "true")}


def size_of(n):
    for limit, name in SCALE:
        if n < limit:
            return name
    return "XXL"


def main():
    ap = argparse.ArgumentParser(description="Print the size of the diff from a base to HEAD.")
    ap.add_argument("base", help="a commit or branch, as origin/main")
    a = ap.parse_args()
    if not shutil.which("git"):
        sys.exit("stop: git not found; install git")
    if git("rev-parse", "--is-inside-work-tree").returncode != 0:
        sys.exit("stop: not inside a git checkout; run it from the PR's checkout")
    if git("rev-parse", "--verify", "--quiet", f"{a.base}^{{commit}}").returncode != 0:
        sys.exit(f"stop: base {a.base} not found; fetch it first, as git fetch origin <branch>")
    counts = changed_lines(a.base)
    skip = generated(list(counts))
    code = tests = 0
    for path, n in counts.items():
        if path in skip or is_lockfile(path):
            continue
        if is_test(path):
            tests += n
        else:
            code += n
    print(size_of(code or tests))


if __name__ == "__main__":
    main()
