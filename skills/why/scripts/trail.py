#!/usr/bin/env python3
"""Print the record behind some lines of code: the commits, their PRs, and the issues.

    trail.py <file>[:<start>[-<end>]]

Run it from the repo's top folder, so a path matches GitHub's. It asks `git log -L` for every commit that
changed the lines, newest first, or `git log --follow` for a whole file,
which follows its renames, and GitHub for the PR of each commit. More than
10 commits: it keeps the 9 newest and the oldest, which made the lines, with
a line `skipped <k> commits` between them. One block per commit:

    commit <sha7> <date> <author>: <subject>
      <each line of the commit body>
      PR #<n> <title> <url>
        body: <the PR body>
        review @<login> <state>: <the review body>
        review comment @<login> on <file>: <the comment>
        comment @<login>: <the PR comment>
        issue #<n> <title> <url>
          body: <the issue body>

or `  no PR found` in place of the PR lines, or `  PR #<n> (as above)` for a
PR an earlier block showed. Review comments on other files
are left out. Each PR, review, comment, and issue body is one line, cut at
400 characters with ` [cut]`. Exits 0. Line numbers are the file's on disk:
each one is mapped to its line at HEAD through `git diff -U0 HEAD`, and git
reads the lines at HEAD. Lines in the range that differ from HEAD come first,
as `Not committed yet: <file>:<lines>`, and the rest are traced.

A file on neither disk nor HEAD, or a line past the end of the file on
disk: prints `No such code: <target>` and exits 2. A file HEAD does not have,
or a range whose every line differs from HEAD: prints `No commits: <target> is not committed
yet.` and exits 0, with no gh call. The first gh call that fails ends the gh
calls: that commit and the later ones get no PR lines, and the last line is
`GitHub: not reached: <gh's error line>. Commits from <sha7> on are git only.`
"""
import json
import os
import re
import subprocess
import sys

CUT = 400
KEEP = 10
QUERY = """query($owner: String!, $name: String!, $oid: GitObjectID!) {
  repository(owner: $owner, name: $name) {
    object(oid: $oid) {
      ... on Commit {
        associatedPullRequests(first: 1) {
          nodes {
            number title url body
            closingIssuesReferences(first: 5) { nodes { number title url body } }
            reviews(first: 20) { nodes { author { login } state body comments(first: 20) { nodes { path body } } } }
            comments(first: 20) { nodes { author { login } body } }
          }
        }
      }
    }
  }
}"""


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr.strip() or f"git exited {r.returncode}")
    return r.stdout


def lines_in(path):
    """How many lines the file has on disk and at HEAD; None where it is not."""
    disk = None
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            disk = len(f.read().splitlines())
    r = subprocess.run(["git", "show", f"HEAD:./{path}"], capture_output=True, text=True)
    head = len(r.stdout.splitlines()) if r.returncode == 0 else None
    return disk, head


def to_head(path, start, end):
    """Map lines start..end of the file on disk to HEAD: (the HEAD lines, the
    lines on disk that differ from HEAD). Reads the hunks of `git diff -U0`."""
    hunks = []
    for m in re.finditer(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", git("diff", "-U0", "HEAD", "--", path), re.M):
        a, b, c, d = int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)
        # A hunk with no lines on one side names the line before it.
        hunks.append((a + (b == 0), b, c + (d == 0), d))
    head, changed = [], []
    for w in range(start, end + 1):
        shift, differs = 0, False
        for a, b, c, d in hunks:
            if w < c:
                break
            if w < c + d:
                differs = True
                break
            shift = (a + b) - (c + d)
        if differs:
            changed.append(w)
        else:
            head.append(w + shift)
    return head, changed


def spans(lines):
    """[2, 3, 4, 7] as `2-4, 7`."""
    out = []
    for n in lines:
        if out and out[-1][1] == n - 1:
            out[-1][1] = n
        else:
            out.append([n, n])
    return ", ".join(f"{a}" if a == b else f"{a}-{b}" for a, b in out)


def gh(*args):
    """gh's stdout, or raise RuntimeError with gh's last error line."""
    try:
        r = subprocess.run(["gh", *args], capture_output=True, text=True)
    except FileNotFoundError:
        raise RuntimeError("gh: command not found")
    if r.returncode != 0:
        lines = [l for l in r.stderr.splitlines() if l.strip()]
        raise RuntimeError(lines[-1] if lines else f"gh exited {r.returncode}")
    return r.stdout


def commits(path, start, end):
    """Each commit that changed the lines, or the whole file when start is None,
    newest first, as (sha, day, author, subject, body)."""
    fmt = ["-s", "--date=short", "--format=%H%x1f%ad%x1f%an%x1f%s%x1f%b%x1e"]
    if start is None:
        out = git("log", "--follow", *fmt, "--", path)
    else:
        out = git("log", f"-L{start},{end}:{path}", *fmt)
    return [tuple(rec.strip("\n").split("\x1f")) for rec in out.split("\x1e") if rec.strip()]


def one_line(text):
    text = " ".join((text or "").split())
    return text if len(text) <= CUT else text[:CUT] + " [cut]"


def login(node):
    return (node.get("author") or {}).get("login", "ghost")


def pr_lines(pr, path):
    lines = [f"  PR #{pr['number']} {pr['title']} {pr['url']}"]
    if one_line(pr.get("body")):
        lines.append(f"    body: {one_line(pr['body'])}")
    for review in pr["reviews"]["nodes"]:
        if one_line(review.get("body")):
            lines.append(f"    review @{login(review)} {review['state']}: {one_line(review['body'])}")
        for c in review["comments"]["nodes"]:
            if c["path"] == path:
                lines.append(f"    review comment @{login(review)} on {path}: {one_line(c['body'])}")
    for c in pr["comments"]["nodes"]:
        lines.append(f"    comment @{login(c)}: {one_line(c['body'])}")
    for issue in pr["closingIssuesReferences"]["nodes"]:
        lines.append(f"    issue #{issue['number']} {issue['title']} {issue['url']}")
        if one_line(issue.get("body")):
            lines.append(f"      body: {one_line(issue['body'])}")
    return lines


def pr_of(owner, name, sha):
    """The PR GitHub ties to the commit, or None."""
    data = json.loads(gh("api", "graphql", "-F", f"owner={owner}", "-F", f"name={name}",
                         "-F", f"oid={sha}", "-f", f"query={QUERY}"))["data"]
    obj = (data.get("repository") or {}).get("object") or {}
    nodes = (obj.get("associatedPullRequests") or {}).get("nodes") or []
    return nodes[0] if nodes else None


def parse(target):
    """(path, start, end); start and end are None for a whole file."""
    path, sep, lines = target.rpartition(":")
    if not sep or not re.fullmatch(r"\d+(-\d+)?", lines):
        return target, None, None
    start, _, end = lines.partition("-")
    start, end = int(start), int(end or start)
    if not path or start < 1 or end < start:
        sys.exit(__doc__.split("\n\n")[1].strip())
    return path, start, end


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.split("\n\n")[1].strip())
    target = sys.argv[1]
    path, start, end = parse(target)
    disk, head = lines_in(path)
    known = disk if disk is not None else head
    if known is None or (end or 0) > known:
        print(f"No such code: {target}")
        sys.exit(2)
    if head is None:
        print(f"No commits: {target} is not committed yet.")
        return
    if start is not None:
        mapped, changed = to_head(path, start, end)
        if not mapped:
            print(f"No commits: {target} is not committed yet.")
            return
        if changed:
            print(f"Not committed yet: {path}:{spans(changed)}")
        start, end = min(mapped), max(mapped)
    found = commits(path, start, end)
    skipped = max(0, len(found) - KEEP)
    if skipped:
        found = found[:KEEP - 1] + found[-1:]
    repo, failed, shown = None, None, set()
    for i, (sha, day, author, subject, body) in enumerate(found):
        if skipped and i == KEEP - 1:
            print(f"skipped {skipped} commits")
        print(f"commit {sha[:7]} {day} {author}: {subject}")
        for line in body.splitlines():
            if line.strip():
                print(f"  {line}")
        if failed:
            continue
        try:
            repo = repo or gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip().split("/", 1)
            pr = pr_of(*repo, sha)
        except RuntimeError as e:
            failed = (str(e), sha[:7])
            continue
        if not pr:
            print("  no PR found")
        elif pr["number"] in shown:
            print(f"  PR #{pr['number']} (as above)")
        else:
            shown.add(pr["number"])
            print("\n".join(pr_lines(pr, path)))
    if failed:
        print(f"GitHub: not reached: {failed[0]}. Commits from {failed[1]} on are git only.")


if __name__ == "__main__":
    main()
