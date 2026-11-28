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
    github.py home <path>...
    github.py latest <owner/repo> <file>

`list` prints {"read_prs": [{"number", "url", "title", "date"}], "read_issues":
[...], "touched": [{"kind", "number", "by"}], "skipped": [{"url", "why"}],
"cut": [<what>]}, a skipped PR being one gh could not read or one in another
repo, a date the day the PR was opened, and a cut entry a list GitHub had
more of than the limit.
`pr` and `issues` print one markdown bundle for a reader. A PR bundle whose
lists GitHub cut has a `Cut:` line after its `Branch:` line, and `pr` prints
`warn: PR #<n> is cut: <lists>` on stderr.
`home` prints [{"path", "home", "file"}] per path, the GitHub repo that holds
the path's real file (by the shared checkout resolver) and the file's path in
it, or {"path", "unknown"} with "in no git repo" or "no GitHub remote".
`latest` prints {"file", "text"}, the file on the repo's default branch, or
{"file", "missing": true} when it is not there.
A gh call that fails stops with `stop: gh could not <what>: <gh's last line>`
on stderr and exit 1, except a PR view or a run log, whose failure is noted
in the output.
"""

import argparse
import datetime as dt
import importlib.util
import json
import os
import re
import subprocess
import sys

CHECKOUT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "shared", "checkout.sh")
LOG_TAIL = 80  # the failing assert sits at the end of a failed log
LIST_LIMIT = 200
# Loaded by path: `python3 -I` leaves the script's folder off sys.path.
_spec = importlib.util.spec_from_file_location("gh", os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "shared", "gh.py"))
GH = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(GH)

PR_QUERY = """
query($owner: String!, $name: String!, $n: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $n) {
      number title url body headRefName
      closingIssuesReferences(first: 10) { pageInfo { hasNextPage } nodes { number title body } }
      reviews(first: 100) { pageInfo { hasNextPage } nodes { author { login } state body } }
      comments(first: 100) { pageInfo { hasNextPage } nodes { author { login } body } }
      reviewThreads(first: 100) { pageInfo { hasNextPage } nodes { isResolved path line comments(first: 20) { pageInfo { hasNextPage } nodes { author { login } body } } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { pageInfo { hasNextPage } nodes {
        __typename
        ... on CheckRun { name conclusion detailsUrl }
        ... on StatusContext { context state targetUrl }
      } } } } } }
    }
  }
}
"""


def gh_json(what, *args):
    return json.loads(GH.stop(what, *args))


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


def url_pattern(repo, kind, n):
    # A run can span repos, so another repo's PR or issue with the same number
    # is not this one. GitHub reads the repo path in any case.
    return re.compile(rf"github\.com/{re.escape(repo)}/{kind}/{n}(?!\d)", re.IGNORECASE)


def pr_patterns(repo, pr):
    pats = [url_pattern(repo, "pull", pr["number"])]
    if pr.get("headRefName"):
        pats.append(re.compile(rf"(?<![\w/.-]){re.escape(pr['headRefName'])}(?![\w/.-])"))
    return pats


def cmd_list(args):
    repo = args.repo
    texts = transcripts(args.transcripts)
    skipped, cut = [], []
    if args.issues:
        issues, prs = [], {}
        for n in args.issues:
            i = gh_json(f"read issue #{n} of {repo}", "issue", "view", str(n), "--repo", repo,
                        "--json", "number,url,title,closedByPullRequestsReferences")
            # A closing reference carries no title or head branch, and the touched rule needs the branch.
            # A closer in another repo is that repo's work, not this one's.
            for ref in i.pop("closedByPullRequestsReferences", []) or []:
                if ref["url"] in prs or any(s["url"] == ref["url"] for s in skipped):
                    continue
                if not ref["url"].startswith(f"https://github.com/{repo}/pull/"):
                    skipped.append({"url": ref["url"], "why": "in another repo"})
                    continue
                try:
                    prs[ref["url"]] = json.loads(GH.run("pr", "view", ref["url"], "--json", "number,url,title,headRefName,createdAt"))
                except GH.GhError as e:
                    skipped.append({"url": ref["url"], "why": str(e)})
            issues.append(i)
        closed = set(args.issues)
        prs = list(prs.values())
    else:
        until = args.until or dt.date.today().isoformat()
        window = f"updated:{args.since}..{until}"
        prs = gh_json(f"list {repo}", "pr", "list", "--repo", repo, "--state", "all", "--search", window,
                      "--json", "number,url,title,headRefName,createdAt,closingIssuesReferences", "--limit", str(LIST_LIMIT + 1))
        issues = gh_json(f"list {repo}", "issue", "list", "--repo", repo, "--state", "all", "--search", window,
                         "--json", "number,url,title", "--limit", str(LIST_LIMIT + 1))
        # One more than the limit tells a cut list from one of exactly LIST_LIMIT.
        if len(prs) > LIST_LIMIT:
            prs = prs[:LIST_LIMIT]
            cut.append(f"pull requests: more than {LIST_LIMIT} in the window")
        if len(issues) > LIST_LIMIT:
            issues = issues[:LIST_LIMIT]
            cut.append(f"issues: more than {LIST_LIMIT} in the window")
        closed = {i["number"] for pr in prs for i in pr.get("closingIssuesReferences") or []}
    read_prs, read_issues, touched = [], [], []
    for pr in prs:
        by = named_by(texts, pr_patterns(repo, pr))
        if by:
            touched.append({"kind": "pr", "number": pr["number"], "by": by})
        else:
            read_prs.append({**{k: pr.get(k) for k in ("number", "url", "title")},
                             "date": (pr.get("createdAt") or "")[:10]})
    for i in issues:
        if i["number"] in closed:
            continue
        by = named_by(texts, [url_pattern(repo, "issues", i["number"])])
        if by:
            touched.append({"kind": "issue", "number": i["number"], "by": by})
        else:
            read_issues.append({k: i.get(k) for k in ("number", "url", "title")})
    print(json.dumps({"read_prs": read_prs, "read_issues": read_issues, "touched": touched, "skipped": skipped,
                      "cut": cut}))


def who(node):
    return ((node or {}).get("author") or {}).get("login") or "ghost"


def run_id(url):
    m = re.search(r"/actions/runs/(\d+)", url or "")
    return m.group(1) if m else None


def more(conn):
    return bool(((conn or {}).get("pageInfo") or {}).get("hasNextPage"))


def cut_lists(pr):
    contexts = [((n["commit"].get("statusCheckRollup") or {}).get("contexts")) for n in pr["commits"]["nodes"]]
    checks = {
        "closing issues": more(pr["closingIssuesReferences"]),
        "reviews": more(pr["reviews"]),
        "comments": more(pr["comments"]),
        "review threads": more(pr["reviewThreads"]),
        "thread comments": any(more(t["comments"]) for t in pr["reviewThreads"]["nodes"]),
        "checks": any(more(c) for c in contexts),
    }
    return [name for name, cut in checks.items() if cut]


def cmd_pr(args):
    owner, name = args.repo.split("/", 1)
    data = gh_json(f"read PR #{args.number} of {args.repo}", "api", "graphql", "-f", f"query={PR_QUERY}",
                   "-F", f"owner={owner}", "-F", f"name={name}", "-F", f"n={args.number}")
    pr = data["data"]["repository"]["pullRequest"]
    out = [f"# PR #{pr['number']} {pr['title']}", pr["url"], f"Branch: {pr['headRefName']}"]
    cut = cut_lists(pr)
    if cut:
        out.append(f"Cut: {', '.join(cut)}: GitHub has more than this bundle holds")
        print(f"warn: PR #{pr['number']} is cut: {', '.join(cut)}", file=sys.stderr)
    out += ["", "## Body", pr.get("body") or "(empty)", ""]
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
            try:
                log = GH.run("run", "view", rid, "--repo", args.repo, "--log-failed")
                out += ["```", *log.rstrip("\n").splitlines()[-LOG_TAIL:], "```"]
            except GH.GhError as e:
                out.append(f"log not readable: {e}")
        else:
            out.append(f"same run as above: {rid}")
    if not failed:
        out.append("none")
    print("\n".join(out))


def cmd_home(args):
    rows = []
    for path in args.paths:
        real = os.path.realpath(path)
        d = real if os.path.isdir(real) else os.path.dirname(real)
        # A file the fix will add is placed by the nearest folder that exists.
        while not os.path.isdir(d):
            d = os.path.dirname(d)
        top = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if top.returncode != 0:
            rows.append({"path": path, "unknown": "in no git repo"})
            continue
        top = os.path.realpath(top.stdout.strip())
        slug = subprocess.run(["bash", CHECKOUT, "slug", top], capture_output=True, text=True)
        if slug.returncode != 0:
            rows.append({"path": path, "unknown": "no GitHub remote"})
            continue
        rows.append({"path": path, "home": slug.stdout.strip(), "file": os.path.relpath(real, top)})
    print(json.dumps(rows))


def cmd_latest(args):
    try:
        text = GH.run("api", f"repos/{args.home}/contents/{args.file}", "-H", "Accept: application/vnd.github.raw")
    except GH.GhError as e:
        if e.status != 404:
            sys.exit(f"stop: gh could not read {args.file} on {args.home}: {e}")
        print(json.dumps({"file": args.file, "missing": True}))
        return
    print(json.dumps({"file": args.file, "text": text}))


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
    p = sub.add_parser("home")
    p.add_argument("paths", nargs="+")
    p = sub.add_parser("latest")
    p.add_argument("home")
    p.add_argument("file")
    args = ap.parse_args()
    {"list": cmd_list, "pr": cmd_pr, "issues": cmd_issues, "home": cmd_home, "latest": cmd_latest}[args.cmd](args)


if __name__ == "__main__":
    main()
