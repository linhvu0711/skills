#!/usr/bin/env python3
"""Tag each PR and branch of a state brief with its live state.

    live_tags.py <brief file> [--cwd <dir>]

Prints the brief. Under its `**PRs and branches:**` line, up to the next
line that starts with `**` or `#`, each bullet
`- PR <#n or PR URL> · <what>` or `- branch <name> · <what>` gets a tag
right after `- `:

- `[merged #n]`, `[open PR #n]`, `[closed #n]`: the PR's state from `gh`;
  a branch tags as its newest PR;
- `[branch only]`: a branch with no PR, local or on GitHub;
- `[branch gone]`: a branch with no PR, neither local nor on GitHub;
- `[state unknown]`: `gh` could not say.

Every `gh` and `git` call runs in `--cwd`, the current folder by default.
A failed `gh` call is checked with `gh api user`. When that works too,
only the one lookup failed: a PR that `gh` cannot find is
`[state unknown]`, and the next bullets still ask. When it fails, `gh`
is down, missing, or logged out: `live tags: gh failed: <its last error
line>` goes to stderr, and that bullet and every later one is
`[state unknown]` with no more `gh` calls. A `--cwd` that is not a
folder counts as `gh` down. Every other line comes out as it went in; a
brief with no such section comes out unchanged. Exits 0.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SECTION = "**PRs and branches:**"
BULLET = re.compile(r"^- (PR|branch) (\S+)")
TAGS = {"MERGED": "[merged #{n}]", "OPEN": "[open PR #{n}]", "CLOSED": "[closed #{n}]"}


class GhDown(Exception):
    """gh cannot answer anything: down, missing, or logged out."""


class NotFound(Exception):
    """gh works, but this one lookup failed."""


class Tagger:
    def __init__(self, cwd):
        self.cwd = cwd
        self.gh_down = cwd is not None and not os.path.isdir(cwd)
        if self.gh_down:
            print(f"live tags: gh failed: no folder {cwd}", file=sys.stderr)

    def run(self, *args):
        try:
            return subprocess.run(args, cwd=self.cwd, capture_output=True, text=True)
        except FileNotFoundError:
            return subprocess.CompletedProcess(args, 127, "", f"{args[0]}: command not found")

    def gh(self, *args):
        if self.gh_down:
            raise GhDown
        r = self.run("gh", *args)
        if r.returncode == 0:
            return json.loads(r.stdout)
        if self.run("gh", "api", "user", "--jq", ".login").returncode == 0:
            raise NotFound
        self.gh_down = True
        lines = [l for l in r.stderr.splitlines() if l.strip()]
        print(f"live tags: gh failed: {lines[-1] if lines else f'gh exited {r.returncode}'}", file=sys.stderr)
        raise GhDown

    def branch_tag(self, branch):
        if self.run("git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0:
            return "[branch only]"
        try:
            self.gh("api", f"repos/{{owner}}/{{repo}}/branches/{branch}")
            return "[branch only]"
        except NotFound:
            return "[branch gone]"

    def tag(self, kind, ref):
        try:
            if kind == "PR":
                pr = self.gh("pr", "view", ref.lstrip("#"), "--json", "number,state")
            else:
                prs = self.gh("pr", "list", "--head", ref, "--state", "all", "--limit", "1", "--json", "number,state")
                if not prs:
                    return self.branch_tag(ref)
                pr = prs[0]
        except (GhDown, NotFound):
            return "[state unknown]"
        return TAGS.get(pr["state"], "[state unknown]").format(n=pr["number"])


def tagged(lines, tagger):
    inside = False
    for line in lines:
        if line.strip() == SECTION:
            inside = True
        elif line.startswith(("**", "#")):
            inside = False
        elif inside and (m := BULLET.match(line)):
            line = f"- {tagger.tag(m.group(1), m.group(2))} {line[2:]}"
        yield line


def main():
    ap = argparse.ArgumentParser(description="Tag each PR and branch of a state brief with its live state.")
    ap.add_argument("brief")
    ap.add_argument("--cwd", default=None, help="folder to run gh and git in (default: the current folder)")
    args = ap.parse_args()
    with open(args.brief, encoding="utf-8") as f:
        lines = f.read().splitlines()
    for line in tagged(lines, Tagger(args.cwd)):
        print(line)


if __name__ == "__main__":
    main()
