#!/usr/bin/env python3
"""The GitHub side of a retro: which PRs and issues to read, and their bundles.

A session that worked on a PR already holds its reviews and fixes, so a PR
is read only when no rendered transcript in scope names it (ADR: retro reads
only untouched PRs). A PR is touched when a transcript holds its
`/pull/<n>` URL or its head branch name; an issue, when one holds its
`/issues/<n>` URL or a PR in scope closes it.

    github.py list <owner/repo> --transcripts DIR (--since D [--until D] | --issues N...)
    github.py pr <owner/repo> <n>
    github.py issues <owner/repo> <n>...

`list` prints {"read_prs": [...], "read_issues": [...], "touched": [{"kind",
"number", "by"}]}. `pr` and `issues` print one markdown bundle for a reader.
A gh call that fails stops with `stop: gh could not <what>: <gh's last line>`
on stderr and exit 1.
"""

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

LOG_TAIL = 80  # the failing assert sits at the end of a failed log

PR_QUERY = """
query($owner: String!, $name: String!, $n: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $n) {
      number title url body headRefName
      closingIssuesReferences(first: 10) { nodes { number title body } }
      reviews(first: 100) { nodes { author { login } state body } }
      comments(first: 100) { nodes { author { login } body } }
      reviewThreads(first: 100) { nodes { isResolved path line comments(first: 20) { nodes { author { login } body } } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
        __typename
        ... on CheckRun { name conclusion detailsUrl }
        ... on StatusContext { context state targetUrl }
      } } } } } }
    }
  }
}
"""


def gh(what, *args):
    done = subprocess.run(["gh", *args], capture_output=True, text=True)
    if done.returncode != 0:
        last = (done.stderr.strip().splitlines() or [f"exit {done.returncode}"])[-1]
        print(f"stop: gh could not {what}: {last}", file=sys.stderr)
        raise SystemExit(1)
    return done.stdout


def gh_json(what, *args):
    return json.loads(gh(what, *args))


def transcripts(folder):
    texts = {}
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as h:
                texts[name] = h.read()
    return texts


def named_by(texts, patterns):
    for name, text in texts.items():
        if any(p.search(text) for p in patterns):
            return name
    return None


def pr_patterns(pr):
    pats = [re.compile(rf"/pull/{pr['number']}(?!\d)")]
    if pr.get("headRefName"):
        pats.append(re.compile(rf"(?<![\w/.-]){re.escape(pr['headRefName'])}(?![\w/.-])"))
    return pats


def cmd_list(args):
    repo = args.repo
    texts = transcripts(args.transcripts)
    if args.issues:
        issues, prs = [], {}
        for n in args.issues:
            i = gh_json(f"read issue #{n} of {repo}", "issue", "view", str(n), "--repo", repo,
                        "--json", "number,url,title,closedByPullRequestsReferences")
            for pr in i.pop("closedByPullRequestsReferences", []) or []:
                prs[pr["number"]] = pr
            issues.append(i)
        closed = set(args.issues)
        prs = list(prs.values())
    else:
        until = args.until or dt.date.today().isoformat()
        window = f"updated:{args.since}..{until}"
        prs = gh_json(f"list {repo}", "pr", "list", "--repo", repo, "--state", "all", "--search", window,
                      "--json", "number,url,title,headRefName,closingIssuesReferences", "--limit", "200")
        issues = gh_json(f"list {repo}", "issue", "list", "--repo", repo, "--state", "all", "--search", window,
                         "--json", "number,url,title", "--limit", "200")
        closed = {i["number"] for pr in prs for i in pr.get("closingIssuesReferences") or []}
    read_prs, read_issues, touched = [], [], []
    for pr in prs:
        by = named_by(texts, pr_patterns(pr))
        if by:
            touched.append({"kind": "pr", "number": pr["number"], "by": by})
        else:
            read_prs.append({k: pr.get(k) for k in ("number", "url", "title")})
    for i in issues:
        if i["number"] in closed:
            continue
        by = named_by(texts, [re.compile(rf"/issues/{i['number']}(?!\d)")])
        if by:
            touched.append({"kind": "issue", "number": i["number"], "by": by})
        else:
            read_issues.append({k: i.get(k) for k in ("number", "url", "title")})
    print(json.dumps({"read_prs": read_prs, "read_issues": read_issues, "touched": touched}))


def who(node):
    return ((node or {}).get("author") or {}).get("login") or "ghost"


def run_id(url):
    m = re.search(r"/actions/runs/(\d+)", url or "")
    return m.group(1) if m else None


def cmd_pr(args):
    owner, name = args.repo.split("/", 1)
    data = gh_json(f"read PR #{args.number} of {args.repo}", "api", "graphql", "-f", f"query={PR_QUERY}",
                   "-F", f"owner={owner}", "-F", f"name={name}", "-F", f"n={args.number}")
    pr = data["data"]["repository"]["pullRequest"]
    out = [f"# PR #{pr['number']} {pr['title']}", pr["url"], f"Branch: {pr['headRefName']}", "",
           "## Body", pr.get("body") or "(empty)", ""]
    for i in pr["closingIssuesReferences"]["nodes"]:
        out += [f"## Closes #{i['number']} {i['title']}", i.get("body") or "(empty)", ""]
    out.append("## Reviews")
    out += [f"- {who(r)} {r['state']}: {r['body']}" for r in pr["reviews"]["nodes"] if r.get("body")] or ["none"]
    out += ["", "## Comments"]
    out += [f"- {who(c)}: {c['body']}" for c in pr["comments"]["nodes"]] or ["none"]
    out += ["", "## Review threads"]
    for t in pr["reviewThreads"]["nodes"]:
        state = "resolved" if t["isResolved"] else "unresolved"
        out.append(f"- {t['path']}:{t.get('line') or '?'} ({state})")
        out += [f"  - {who(c)}: {c['body']}" for c in t["comments"]["nodes"]]
    if not pr["reviewThreads"]["nodes"]:
        out.append("none")
    out += ["", "## Failed checks"]
    failed = []
    for node in pr["commits"]["nodes"]:
        for c in ((node["commit"].get("statusCheckRollup") or {}).get("contexts") or {}).get("nodes", []):
            if c.get("__typename") == "CheckRun" and c.get("conclusion") in ("FAILURE", "TIMED_OUT"):
                failed.append((c["name"], c.get("detailsUrl")))
            elif c.get("__typename") == "StatusContext" and c.get("state") in ("FAILURE", "ERROR"):
                failed.append((c["context"], c.get("targetUrl")))
    seen = set()
    for check, url in failed:
        out.append(f"### {check}")
        rid = run_id(url)
        if not rid:
            out.append(f"no log here: {url or 'no link'}")
        elif rid not in seen:
            seen.add(rid)
            log = gh(f"read the failed log of run {rid}", "run", "view", rid, "--repo", args.repo, "--log-failed")
            out += ["```", *log.rstrip("\n").splitlines()[-LOG_TAIL:], "```"]
        else:
            out.append(f"same run as above: {rid}")
    if not failed:
        out.append("none")
    print("\n".join(out))


def cmd_issues(args):
    out = []
    for n in args.numbers:
        i = gh_json(f"read issue #{n} of {args.repo}", "issue", "view", str(n), "--repo", args.repo,
                    "--json", "number,title,url,body,comments")
        out += [f"# Issue #{i['number']} {i['title']}", i["url"], "", i.get("body") or "(empty)", "", "## Comments"]
        out += [f"- {who(c)}: {c['body']}" for c in i.get("comments") or []] or ["none"]
        out.append("")
    print("\n".join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("list")
    p.add_argument("repo")
    p.add_argument("--transcripts", required=True)
    scope = p.add_mutually_exclusive_group(required=True)
    scope.add_argument("--since")
    scope.add_argument("--issues", nargs="+", type=int)
    p.add_argument("--until")
    p = sub.add_parser("pr")
    p.add_argument("repo")
    p.add_argument("number", type=int)
    p = sub.add_parser("issues")
    p.add_argument("repo")
    p.add_argument("numbers", nargs="+", type=int)
    args = ap.parse_args()
    {"list": cmd_list, "pr": cmd_pr, "issues": cmd_issues}[args.cmd](args)


if __name__ == "__main__":
    main()
