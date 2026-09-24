---
name: kickoff
description: "Open a new herdr pane beside this one and run /plan-up there on an issue, a run of epic tickets, or a whole epic. One script does it all: checks the repo is clean, on base, and pulled; picks the effort from the size label; places and names the pane. Stops once /plan-up is running."
disable-model-invocation: true
---

One script does the whole job. You run it and relay what it says.

```bash
scripts/kickoff.sh <args as the user typed them>
```

The arguments are `/plan-up`'s, passed through unchanged:

- `/kickoff <issue-url>`: one ticket.
- `/kickoff <epic-url> #12 #14`: a run of the named tickets under that epic.
- `/kickoff <issue-url> #12 #14`: a set. Plain tickets with no shared
  parent, planned together in one pane, in the order given. The first
  URL is the first ticket. The script tells a set from a run by whether
  the first issue has sub-issues.
- `/kickoff <epic-url>`: the whole epic. The script sees the sub-issues
  and knows.
- `/kickoff <issue-url> on <pr-url>`: a new layer on an open stack.

Exit 0: print the script's one report line and stop. `/plan-up` now talks
to the user in the new pane. Do not watch it, read its plan, or run
`/handoff-devin` from here.

Exit 1: the last stderr line starts with `stop:` and says why. Show it
as is and stop. Nothing is half done: the script makes no pane until the
tree check passed. A dirty tree lists the files; the user commits or
stashes and runs `/kickoff` again. A pane that exists but did not launch
stays for the user to look at; the message names it.

Flags you may add:

- `--label <name>` when the auto label from the title reads badly.
  Names match `[a-z][a-z0-9_-]{0,31}`.
- `--dry-run` to show every decision (form, effort, base, repo path,
  tree, label, placement) with no pane made. Use it when the user asks
  what would happen.

What the script decides, so you can answer questions about it:

- Model is not set, so claude uses its default model. Effort is
  `medium` for one ticket labelled XS or S, matched loosely (`size/S`,
  `Size: Small`). Everything else is `high`: M and up, no size label, a
  run, a set, a whole epic.
- Permission mode is `auto`.
- Repo path: `~/.config/kickoff/repos.tsv` first (`owner/repo<TAB>path`),
  then the pane's cwd if its origin matches, then a search under
  `~/development`. Worktrees are skipped. A find is written to the map.
  None or several: it stops and says so.
- Tree: dirty stops. Clean but off base switches to base. Then
  `git pull --ff-only`.
- Placement: split the current tab to the right if it has under 3
  columns, else the tab in this workspace with the fewest columns under
  3, else a new tab. Never reuses a pane. Never takes focus. Columns are
  equalized after a split.
- Label: first four words of the title in kebab case, `-run` for a run,
  a set, or an epic, `-on-<pr>` for the `on` form. Made unique among live agents.

## Resolving the target from the session

The user need not paste a URL. They may say `/kickoff on this`, `/kickoff that
issue`, or just `/kickoff` right after making an issue. Before you run the
script, turn that reference into the URL and `#numbers` the script takes.

Look back through the session for the issue or epic they mean: one just
made with `/to-issue` or `/capture`, a link pasted earlier, the PR the work
sits on. Resolve it to the exact args and pass those to the script
unchanged.

Run the script only when one target is clear. If nothing in the session
matches, or more than one could, do not guess and do not run it. Say what
you found, name the candidates, and ask which one. The word `on` is
overloaded: `/kickoff on this` can mean "target this issue" or the `on
<pr-url>` stack form. When that is unclear, ask before running.

## Examples

**User:** `/kickoff https://github.com/acme/shop/issues/42`

Run the script. It prints
`#42 Export orders as CSV → w4/w4:t1/w4:p9M · effort high (size above S or no size label) · tree clean on main · split in w4:t1`.
Say that line. Stop.

**User:** `/kickoff https://github.com/acme/shop/issues/42` with edits in
the tree

Script exits 1 with `stop: dirty tree in ~/development/projects/shop:`
and the files. Show it. Stop.

**User:** `what would /kickoff do for issue 70?`

Run with `--dry-run`. Show the line.

**User:** makes an issue with `/to-issue`, then `/kickoff on this pls`

One fresh issue in the session, so the target is clear. Run the script on
that issue's URL. Say the line. Stop.

**User:** `/kickoff 34 35 36 33` right after filing those four with `/to-issue`,
no epic among them

A set. Run the script with the first as the URL and the rest as numbers:
`kickoff.sh https://github.com/acme/shop/issues/34 '#35' '#36' '#33'`. One
pane, one `/plan-up`, four layers in that order. Never one pane per
issue, and never attach the tickets to an epic just to satisfy the form.

**User:** `/kickoff on this` with no issue or PR anywhere in the session

Nothing to resolve. Do not run the script. Tell the user you found no
target in the session and ask for the link.
