---
name: kickoff-herdr
description: "Open a new herdr pane beside this one and run /ship or /plan-up there on issues named by number, URL, or words: one ticket, a run of epic tickets, a set, or a whole epic. One script does it all: finds the repo, leaves its tree as it is; picks the model, effort, and command from the labels unless the user names them; places and names the pane. Stops once the command is running."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

One script does the whole job. Read `../../shared/kickoff/target.md`:
the target forms, the flags, the table, and how to turn the user's
words into a target. Turn what the user said into the script's
arguments, run it, and relay what it says.

```bash
scripts/kickoff.sh [flags] <target>
```

Exit 0: print the script's one report line and stop. The command it
started now talks to the user in the new pane. Do not watch it, read
its plan, or run `/handoff` from here.

Exit 1: the last stderr line starts with `stop:` and says why. Show it
as is and stop. Nothing is half done: the script makes no pane until
every check passed. A pane that exists but did not launch
stays for the user to look at; the message names it.

What this script adds to the shared decisions, so you can answer
questions about it:

- It starts Claude Code in the new pane with the model, the effort, and
  `--permission-mode auto`, and types the command into it. A model name
  goes to claude as is.
- Placement: split the current tab to the right if it has under 3
  columns, else the tab in this workspace with the fewest columns under
  3, else a new tab. Never reuses a pane. Never takes focus. Columns are
  equalized after a split.
- Label: the shared label, made unique among live agents, as `i42-2`.

## Examples

**User:** `/kickoff-herdr https://github.com/acme/shop/issues/42`

Run the script. It prints
`#42 Export orders as CSV → w4/w4:t1/w4:p9M · /ship (default) · model opus (default) · effort medium (default) · size M · base main · split in w4:t1`.
Say that line. Stop.

**User:** `/kickoff-herdr 42` with edits in the tree, on a feature branch,
in a session about acme/shop

Run `kickoff.sh https://github.com/acme/shop/issues/42`. The edits and
the branch stay as they are. Say the line. Stop.

**User:** `/kickoff-herdr 42 with opus xhigh`

Run `kickoff.sh --model opus --effort xhigh
https://github.com/acme/shop/issues/42`. The command still comes from
the table.

**User:** `what would /kickoff-herdr do for issue 70?`

Do not run the script. Read #70's labels and answer from the table:
the model, effort, and command it would pick, and why.

**User:** makes an issue with `/to-issue`, then `/kickoff-herdr on this pls`

One fresh issue in the session, so the target is clear. Run the script on
that issue's URL. Say the line. Stop.

**User:** `/kickoff-herdr 34 35 36 33` right after filing those four with
`/to-issue`, no epic among them; #35 has no size label

A set, in one pane. Read #35 and size it, say S. Run
`kickoff.sh --size 35=S https://github.com/acme/shop/issues/34 '#35' '#36' '#33'`.
One pane, one command, four layers in that order.

**User:** `/kickoff-herdr P1 of this epic, one pane each`, in a session about
epic #70, whose `### Phase 1` lists #71 and #72, both open

Run the script twice: `kickoff.sh https://github.com/acme/shop/issues/71`,
then `kickoff.sh https://github.com/acme/shop/issues/72`. Say both lines.

**User:** `/kickoff-herdr on this` with no issue or PR anywhere in the session

Nothing to resolve. Do not run the script. Tell the user you found no
target in the session and ask for the link.
