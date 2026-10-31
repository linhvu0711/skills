#!/usr/bin/env python3
"""Delete plan files whose work is done.

    prune.py [-n]      -n: print what would go, delete nothing

A slug goes when its `plan-<slug>.md` has a `Repo: owner/repo` line and
every issue the slug names is closed: the number(s) in the slug, plus,
for a `-run`, every `#N` in the `## Stack` table. Its `plan-<slug>.*`
and `prompt-<slug>.*` files are deleted. A chat plan, slug
`<owner>-<repo>-chat-<words>`, has no issue: it goes when its `.md` is
older than 30 days. Any other slug with no issue, an unknown repo, or a
gh error stays. Files that belong to no plan are printed as `stray`,
never deleted. Each plan is read through plan_reader.py.
"""
import glob
import json
import os
import re
import subprocess
import sys
import time

import plan_reader

DAYS_30 = 30 * 24 * 60 * 60


def closed_issues(repo, cache):
    """The repo's closed issue numbers, or None when gh cannot list them."""
    if repo not in cache:
        try:
            done = subprocess.run(["gh", "issue", "list", "-R", repo, "--state", "closed", "-L", "100000",
                                   "--json", "number"], capture_output=True, text=True)
            cache[repo] = {i["number"] for i in json.loads(done.stdout)} if done.returncode == 0 else None
        except (OSError, ValueError, TypeError, KeyError):
            cache[repo] = None
    return cache[repo]


def delete(folder, slug):
    for prefix in ("plan-", "prompt-"):
        for f in glob.glob(os.path.join(glob.escape(folder), glob.escape(prefix + slug) + ".*")):
            os.remove(f)


def files(folder):
    """The folder's names, sorted, without the hidden ones a shell's `*` leaves out."""
    return sorted(n for n in os.listdir(folder) if not n.startswith("."))


def main():
    folder = os.environ.get("PLAN_DIR") or os.path.expanduser("~/.agents/artifacts/plan")
    dry = sys.argv[1:2] == ["-n"]
    if not os.path.isdir(folder):
        return
    cache, pruned, kept = {}, 0, 0
    for name in files(folder):
        if not (name.startswith("plan-") and name.endswith(".md")):
            continue
        md = os.path.join(folder, name)
        slug = name[len("plan-"):-len(".md")]
        plan = plan_reader.read(md)
        repo = plan["facts"].get("repo", "")
        prefix = repo.replace("/", "-", 1) + "-"
        tail = slug[len(prefix):] if repo and slug.startswith(prefix) else slug
        if repo and re.fullmatch(r"chat-[a-z0-9-]+", tail):
            gone = time.time() - os.path.getmtime(md) > DAYS_30
        elif repo and tail != slug and re.fullmatch(r"[0-9]+(-[0-9]+)*(-run)?", tail):
            numbers = {int(n) for n in tail.removesuffix("-run").split("-")}
            if tail.endswith("-run"):
                numbers |= set(plan["stack_issues"])
            closed = closed_issues(repo, cache)
            gone = closed is not None and numbers <= closed
        else:
            gone = False
        if not gone:
            kept += 1
            continue
        print(f"pruned {slug}")
        if not dry:
            delete(folder, slug)
        pruned += 1
    # Listed again: the deletes above leave fewer files.
    for name in files(folder):
        m = re.fullmatch(r"(plan|prompt)-(.*)\.[a-z]+", name)
        if m and os.path.exists(os.path.join(folder, f"plan-{m.group(2)}.md")):
            continue
        print(f"stray {name}")
    print(f"pruned {pruned}, kept {kept}{' (dry run)' if dry else ''}")


if __name__ == "__main__":
    main()
