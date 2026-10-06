---
name: kickoff
description: "Open a new herdr pane beside this one and run /ship or /plan-up there on issues named by number, URL, or words: one ticket, a run of epic tickets, a set, or a whole epic. One script does it all: finds the repo, leaves its tree as it is; picks the model, effort, and command from the labels unless the user names them; places and names the pane. Stops once the command is running."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

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

Exit 0: print the script's one report line and stop. `/ship` or
`/plan-up` now talks to the user in the new pane. Do not watch it, read its plan, or run
`/handoff` from here.

Exit 1: the last stderr line starts with `stop:` and says why. Show it
as is and stop. Nothing is half done: the script makes no pane until
every check passed. A pane that exists but did not launch
stays for the user to look at; the message names it.

Flags you may add:

- `--label <name>` when the auto label from the title reads badly.
  Names match `[a-z][a-z0-9_-]{0,31}`.
- `--size <n>=<size>`, size one of XS, S, M, L, XL, once for each
  ticket with no size label: the size you guessed from its body
  (§ Resolving the target). It counts like a label, and the report line
  says `guessed`.
- `--dry-run` to show every decision (form, effort, repo path, base,
  label, placement) with no pane made. Use it when the user asks
  what would happen.

What the script decides, so you can answer questions about it:

- Model, effort, and command, from the size and `ready-to-build`
  labels. Sizes match loosely (`size/S`, `Size: Medium`):

  | Tickets | Model | Effort | Command |
  |---|---|---|---|
  | every one `ready-to-build` | `sonnet` | `high` | `/ship` |
  | all XS or S | `opus` | `medium` | `/ship` |
  | any M | `opus` | `medium` | `/plan-up` |
  | any L, XL, or no size | `opus` | `high` | `/plan-up` |

  In a run, a set, or a whole epic the biggest ticket picks the row;
  only a target whose every ticket is `ready-to-build` takes the sonnet
  row. A whole epic counts its open tickets. `manual` tickets do not
  count; a target with none left stops.
- Permission mode is `auto`.
- Repo path: found by the checkout resolver,
  `../../shared-skill-core/checkout.sh main <owner/repo>`, whose header
  says where it looks. A find is written to the map. None or several: it
  stops and says so.
- Tree: left as is, on any branch, with edits or not. `/plan-up` reads
  its own fresh copy of the base, so the script never switches, pulls,
  or stops on it.
- Placement: split the current tab to the right if it has under 3
  columns, else the tab in this workspace with the fewest columns under
  3, else a new tab. Never reuses a pane. Never takes focus. Columns are
  equalized after a split.
- Label: `i` and the issue numbers, as `i42`, `i42-43`, `i42-on-80`,
  and `i70` for a whole epic. Made unique among live agents.

## Resolving the target from the session

The user need not paste a URL. They may say `/kickoff on this`, `/kickoff that
issue`, or just `/kickoff` right after making an issue. Before you run the
script, turn that reference into the URL and `#numbers` it takes: look
back through the session for the issue or epic they mean (one just made
with `/to-issue` or `/capture`, a link pasted earlier, the PR the work
sits on).

Run the script only when one target is clear. None or several match:
say what you found, name the candidates, and ask which one. The word
`on` is overloaded: `/kickoff on this` can mean "target this issue" or the `on
<pr-url>` stack form. When that is unclear, ask before running.

## Examples

**User:** `/kickoff https://github.com/acme/shop/issues/42`

Run the script. It prints
`#42 Export orders as CSV → w4/w4:t1/w4:p9M · /plan-up · model opus (default) · effort medium (default) · size M · base main · split in w4:t1`.
Say that line. Stop.

**User:** `/kickoff https://github.com/acme/shop/issues/42` with edits in
the tree, on a feature branch

Same as above: the script runs and prints its line. The edits and the
branch stay as they are. Say the line. Stop.

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
