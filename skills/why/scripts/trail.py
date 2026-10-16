#!/usr/bin/env python3
"""Print the record behind some lines of code: the commits, their PRs, and the issues.

    trail.py <file>:<start>[-<end>]

Run it from inside the repo. It asks `git log -L` for every commit that
changed the lines, newest first, and GitHub for the PR of each commit.
One block per commit:

    commit <sha7> <date> <author>: <subject>
      <each line of the commit body>
      PR #<n> <title> <url>
        body: <the PR body>
        review @<login> <state>: <the review body>
        review comment @<login> on <file>: <the comment>
        comment @<login>: <the PR comment>
        issue #<n> <title> <url>
          body: <the issue body>

or `  no PR found` in place of the PR lines. Review comments on other files
are left out. Each PR, review, comment, and issue body is one line, cut at
400 characters with ` [cut]`. Exits 0. Line numbers are the file's on disk;
git reads the lines at HEAD.

A file on neither disk nor HEAD, or a line past the end of the file on
disk: prints `No such code: <target>` and exits 2. A file or a line on disk
that HEAD does not have yet: prints `No commits: <target> is not committed
yet.` and exits 0, with no gh call. The first gh call that fails ends the gh
calls: that commit and the later ones get no PR lines, and the last line is
`GitHub: not reached: <gh's error line>. Commits from <sha7> on are git only.`
"""
import json
import os
import subprocess
import sys

CUT = 400
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


def gh(*args):
    """gh's stdout, or raise RuntimeError with gh's last error line."""
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        lines = [l for l in r.stderr.splitlines() if l.strip()]
        raise RuntimeError(lines[-1] if lines else f"gh exited {r.returncode}")
    return r.stdout


def commits(path, start, end):
    """Each commit that changed the lines, newest first, as (sha, day, author, subject, body)."""
    out = git("log", f"-L{start},{end}:{path}", "-s", "--date=short",
              "--format=%H%x1f%ad%x1f%an%x1f%s%x1f%b%x1e")
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
    path, _, lines = target.rpartition(":")
    if not path or not lines:
        sys.exit(__doc__.split("\n\n")[1].strip())
    start, _, end = lines.partition("-")
    if not start.isdigit() or (end and not end.isdigit()) or int(start) < 1 or int(end or start) < int(start):
        sys.exit(__doc__.split("\n\n")[1].strip())
    return path, int(start), int(end or start)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.split("\n\n")[1].strip())
    target = sys.argv[1]
    path, start, end = parse(target)
    disk, head = lines_in(path)
    known = disk if disk is not None else head
    if known is None or end > known:
        print(f"No such code: {target}")
        sys.exit(2)
    if head is None or end > head:
        print(f"No commits: {target} is not committed yet.")
        return
    found = commits(path, start, end)
    repo, failed = None, None
    for sha, day, author, subject, body in found:
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
        for line in pr_lines(pr, path) if pr else ["  no PR found"]:
            print(line)
    if failed:
        print(f"GitHub: not reached: {failed[0]}. Commits from {failed[1]} on are git only.")


if __name__ == "__main__":
    main()
