#!/usr/bin/env python3
"""List who is already on each issue, before plan-up plans it.

    claims.py <owner/repo> <n> [<n>...]

Asks GitHub for each issue, in the order given, page by page until every
linked PR is read, and prints one line per claim it finds:
- an open PR that closes the issue or mentions it:
  `#<n> pr #<pr> "<title>" @<author> <url>`, one per PR, by PR number;
- a person assigned to the issue who is not the gh user:
  `#<n> assignee @<login>`.
Closed and merged PRs are not claims. Comments are not read here.

Prints nothing and exits 0 when no issue has a claim. When a gh call
fails, prints `stop: gh could not read #<n>: <gh's error line>` to stderr,
nothing to stdout, and exits 1.
"""
import argparse
import importlib.util
import json
import os

# gh.py sits in the shared core, off sys.path, so it is loaded by path.
_spec = importlib.util.spec_from_file_location("gh", os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "shared", "gh.py"))
GH = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(GH)

PR = "number title url state author { login }"
PAGE = "pageInfo { hasNextPage endCursor }"
QUERY = f"""query($owner: String!, $name: String!, $number: Int!, $prAfter: String, $eventAfter: String) {{
  viewer {{ login }}
  repository(owner: $owner, name: $name) {{
    issue(number: $number) {{
      assignees(first: 20) {{ nodes {{ login }} }}
      closedByPullRequestsReferences(first: 100, after: $prAfter, includeClosedPrs: false) {{
        nodes {{ {PR} }} {PAGE}
      }}
      timelineItems(first: 100, after: $eventAfter, itemTypes: [CROSS_REFERENCED_EVENT]) {{
        nodes {{ ... on CrossReferencedEvent {{ source {{ ... on PullRequest {{ {PR} }} }} }} }} {PAGE}
      }}
    }}
  }}
}}"""


def ask(owner, name, number, cursors):
    """The `data` of one page of the query; a gh failure stops the script."""
    args = ["api", "graphql", "-F", f"owner={owner}", "-F", f"name={name}",
            "-F", f"number={number}", "-f", f"query={QUERY}"]
    for key, cursor in cursors.items():
        if cursor:
            args += ["-f", f"{key}={cursor}"]
    return json.loads(GH.stop(f"read #{number}", *args))["data"]


def read(owner, name, number):
    """Every page for one issue: the gh user, the assignees, and every linked PR.

    Each round asks for the page after each list's last cursor, so a list
    already read to its end comes back empty while the other goes on.
    """
    cursors = {"prAfter": None, "eventAfter": None}
    linked = []
    while True:
        data = ask(owner, name, number, cursors)
        issue = data["repository"]["issue"]
        closing, events = issue["closedByPullRequestsReferences"], issue["timelineItems"]
        linked += closing["nodes"] + [n.get("source") or {} for n in events["nodes"]]
        more = False
        for key, conn in (("prAfter", closing), ("eventAfter", events)):
            cursors[key] = conn["pageInfo"]["endCursor"] or cursors[key]
            more = more or conn["pageInfo"]["hasNextPage"]
        if not more:
            return data["viewer"]["login"], issue["assignees"]["nodes"], linked


def claims(number, me, assignees, linked):
    prs = {}
    for pr in linked:
        if pr.get("url") and pr.get("state") == "OPEN":
            prs[pr["url"]] = pr
    lines = [f'#{number} pr #{pr["number"]} "{pr["title"]}" @{(pr.get("author") or {}).get("login", "ghost")} {pr["url"]}'
             for pr in sorted(prs.values(), key=lambda p: p["number"])]
    lines += [f"#{number} assignee @{a['login']}"
              for a in assignees if a["login"] != me]
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", help="owner/repo")
    ap.add_argument("numbers", nargs="+", metavar="n", help="an issue number")
    args = ap.parse_args()
    if "/" not in args.repo:
        ap.error("repo must be owner/repo")
    owner, name = args.repo.split("/", 1)
    out = []
    for number in args.numbers:
        out += claims(number, *read(owner, name, number))
    for line in out:
        print(line)


if __name__ == "__main__":
    main()
