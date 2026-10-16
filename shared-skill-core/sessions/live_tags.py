#!/usr/bin/env python3
"""Tag each PR and branch of a state brief with its live state.

    live_tags.py <brief file> [--cwd <dir>]

Prints the brief. Under its `**PRs and branches:**` line, up to the next
line that starts with `**` or `#`, each bullet
`- PR <#n or PR URL> · <what>` or `- branch <name> · <what>` gets a tag
right after `- `:

- `[merged #n]`, `[open PR #n]`, `[closed #n]`: the PR's state from `gh`;
  a branch tags as its newest PR;
- `[branch only]`: a branch with no PR, local or at origin;
- `[branch gone]`: a branch with no PR, neither local nor at origin;
- `[state unknown]`: `gh` failed or is missing.

Every `gh` and `git` call runs in `--cwd`, the current folder by default.
The first `gh` call that fails writes `live tags: gh failed: <its last
error line>` to stderr, and no later bullet calls `gh`. Every other line
comes out as it went in; a brief with no such section comes out
unchanged. Exits 0.
"""
import argparse
import json
import re
import subprocess
import sys

SECTION = "**PRs and branches:**"
BULLET = re.compile(r"^- (PR|branch) (\S+)")
TAGS = {"MERGED": "[merged #{n}]", "OPEN": "[open PR #{n}]", "CLOSED": "[closed #{n}]"}


class GhFailed(Exception):
    pass


class Tagger:
    def __init__(self, cwd):
        self.cwd = cwd
        self.gh_down = False

    def gh(self, *args):
        if self.gh_down:
            raise GhFailed
        try:
            r = subprocess.run(["gh", *args], cwd=self.cwd, capture_output=True, text=True)
        except FileNotFoundError:
            r = subprocess.CompletedProcess(args, 127, "", "gh: command not found")
        if r.returncode != 0:
            self.gh_down = True
            lines = [l for l in r.stderr.splitlines() if l.strip()]
            print(f"live tags: gh failed: {lines[-1] if lines else f'gh exited {r.returncode}'}", file=sys.stderr)
            raise GhFailed
        return json.loads(r.stdout)

    def has_ref(self, branch):
        return any(subprocess.run(["git", "show-ref", "--verify", "--quiet", ref], cwd=self.cwd).returncode == 0
                   for ref in (f"refs/heads/{branch}", f"refs/remotes/origin/{branch}"))

    def tag(self, kind, ref):
        try:
            if kind == "PR":
                pr = self.gh("pr", "view", ref.lstrip("#"), "--json", "number,state")
            else:
                prs = self.gh("pr", "list", "--head", ref, "--state", "all", "--limit", "1", "--json", "number,state")
                if not prs:
                    return "[branch only]" if self.has_ref(ref) else "[branch gone]"
                pr = prs[0]
        except GhFailed:
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
