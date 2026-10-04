#!/usr/bin/env python3
"""List who is already on each issue, before plan-up plans it.

    claims.py <owner/repo> <n> [<n>...]

Asks GitHub once per issue, in the order given, and prints one line per
claim it finds:
- an open PR that closes the issue or mentions it:
  `#<n> pr #<pr> "<title>" @<author> <url>`, one per PR, by PR number;
- a person assigned to the issue who is not the gh user:
  `#<n> assignee @<login>`.
Closed and merged PRs are not claims. Comments are not read here.

Prints nothing and exits 0 when no issue has a claim. When a gh call
fails, prints `claims: #<n>: <gh's error line>` to stderr, nothing to
stdout, and exits 1.
"""
import json
import subprocess
import sys

PR = "number title url state author { login }"
QUERY = f"""query($owner: String!, $name: String!, $number: Int!) {{
  viewer {{ login }}
  repository(owner: $owner, name: $name) {{
    issue(number: $number) {{
      assignees(first: 20) {{ nodes {{ login }} }}
      closedByPullRequestsReferences(first: 20, includeClosedPrs: false) {{ nodes {{ {PR} }} }}
      timelineItems(first: 100, itemTypes: [CROSS_REFERENCED_EVENT]) {{
        nodes {{ ... on CrossReferencedEvent {{ source {{ ... on PullRequest {{ {PR} }} }} }} }}
      }}
    }}
  }}
}}"""


def ask(owner, name, number):
    """The `data` of the query for one issue, or raise RuntimeError with gh's error line."""
    r = subprocess.run(
        ["gh", "api", "graphql", "-F", f"owner={owner}", "-F", f"name={name}",
         "-F", f"number={number}", "-f", f"query={QUERY}"],
        capture_output=True, text=True)
    if r.returncode != 0:
        lines = [l for l in r.stderr.splitlines() if l.strip()]
        raise RuntimeError(lines[-1] if lines else f"gh exited {r.returncode}")
    return json.loads(r.stdout)["data"]


def claims(number, data):
    issue = data["repository"]["issue"]
    me = data["viewer"]["login"]
    prs = {}
    linked = issue["closedByPullRequestsReferences"]["nodes"]
    linked += [n.get("source") or {} for n in issue["timelineItems"]["nodes"]]
    for pr in linked:
        if pr.get("url") and pr.get("state") == "OPEN":
            prs[pr["url"]] = pr
    lines = [f'#{number} pr #{pr["number"]} "{pr["title"]}" @{(pr.get("author") or {}).get("login", "ghost")} {pr["url"]}'
             for pr in sorted(prs.values(), key=lambda p: p["number"])]
    lines += [f"#{number} assignee @{a['login']}"
              for a in issue["assignees"]["nodes"] if a["login"] != me]
    return lines


def main():
    if len(sys.argv) < 3 or "/" not in sys.argv[1]:
        sys.exit(__doc__.split("\n\n")[1].strip())
    owner, name = sys.argv[1].split("/", 1)
    out = []
    for number in sys.argv[2:]:
        try:
            out += claims(number, ask(owner, name, number))
        except RuntimeError as e:
            print(f"claims: #{number}: {e}", file=sys.stderr)
            sys.exit(1)
    for line in out:
        print(line)


if __name__ == "__main__":
    main()
