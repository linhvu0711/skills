---
name: kickoff
description: "Open a new herdr pane beside this one and run /ship or /plan-up there on issues named by number, URL, or words: one ticket, a run of epic tickets, a set, or a whole epic. One script does it all: finds the repo, leaves its tree as it is; picks the model, effort, and command from the labels unless the user names them; places and names the pane. Stops once the command is running."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

One script does the whole job. You turn what the user said into its
arguments (§ Resolving the target), run it, and relay what it says.

```bash
scripts/kickoff.sh [flags] <target>
```

The target takes `/plan-up`'s forms, with full URLs. The script passes
it on unchanged:

- `<issue-url>`: one ticket.
- `<epic-url> #12 #14`: a run of the named tickets under that epic.
- `<issue-url> #12 #14`: a set. Plain tickets with no shared parent,
  in one pane, in the order given. The first URL is the first ticket.
  The script tells a set from a run by whether the first issue has
  sub-issues.
- `<epic-url>`: the whole epic. The script sees the sub-issues and
  knows.
- `<issue-url> on <pr-url>`: a new layer on an open stack.

Exit 0: print the script's one report line and stop. `/ship` or
`/plan-up` now talks to the user in the new pane. Do not watch it, read
its plan, or run `/handoff` from here.

Exit 1: the last stderr line starts with `stop:` and says why. Show it
as is and stop. Nothing is half done: the script makes no pane until
every check passed. A pane that exists but did not launch
stays for the user to look at; the message names it.

Flags you may add:

- `--label <name>` when the user names the pane.
  Names match `[a-z][a-z0-9_-]{0,31}`.
- `--size <n>=<size>`, size one of XS, S, M, L, XL, once for each
  ticket with no size label: the size you guessed from its body
  (§ Resolving the target). It counts like a label, and the report line
  says `guessed`.
- `--model <name>` when the user names a model: an alias (`opus`,
  `sonnet`, `haiku`) or a full model name. It goes to claude as is.
- `--effort <level>` when the user names an effort: `low`, `medium`,
  `high`, `xhigh`, or `max`.
- `--command ship` or `--command plan-up` when the user names the
  command: "plan only" is `plan-up`, "ship it" is `ship`.

A value the user does not name comes from the table below. The report
line marks each value `(default)` or `(set)`.

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

The user seldom pastes a URL. They name issues by number or in words,
most often ones this session made or talked about: `/kickoff 12`,
`/kickoff 12 and 14`, `/kickoff all of P1 in this epic`, `/kickoff on
this`, or just `/kickoff` right after `/to-issue`. Before you run the
script, do these steps.

1. **Repo.** Take it from the session: the issues made or linked here,
   or the repo of the current folder (`gh repo view --json
   nameWithOwner`). Two repos fit, or none: ask.
2. **Issues.** Find each issue the user means. A number is an issue in
   that repo. Words point back into the session: "this", "that issue",
   "the one we just made", a link pasted earlier, the PR the work sits
   on. A phase, as in "P1 of this epic", is the `### Phase 1` section
   under `## Phases` in the epic's body; take its open tickets, top to
   bottom (`gh issue view <epic> --json body,subIssues`). None or
   several match: say what you found, name the candidates, and ask.
3. **Panes.** One pane for all the issues, unless the user asks for
   "one pane each" or the like. One pane: tickets that are all
   sub-issues of one epic go as a run, `<epic-url> #a #b`; else as a
   set, `<first-url> #b #c`, in the order the user gave. Never attach
   tickets to an epic to make a run. One pane each: run the script
   once per issue, one after the other.
4. **Sizes.** For each ticket with no size label (`gh issue view <n>
   --json labels,title,body`), read its title and body and size it by
   `../../shared-skill-core/size.md`. Pass `--size <n>=<size>`. Skip a
   ticket that has a size label.
5. **Flags.** A model, an effort, or a command in the user's words
   becomes `--model`, `--effort`, or `--command` (see Flags). A word
   the flags do not take: ask.

The word `on` is overloaded: `/kickoff on this` can mean "target this
issue" or the `on <pr-url>` stack form. When that is unclear, ask before
running.

## Examples

**User:** `/kickoff https://github.com/acme/shop/issues/42`

Run the script. It prints
`#42 Export orders as CSV → w4/w4:t1/w4:p9M · /plan-up · model opus (default) · effort medium (default) · size M · base main · split in w4:t1`.
Say that line. Stop.

**User:** `/kickoff 42` with edits in the tree, on a feature branch,
in a session about acme/shop

Run `kickoff.sh https://github.com/acme/shop/issues/42`. The edits and
the branch stay as they are. Say the line. Stop.

**User:** `/kickoff 42 with opus xhigh`

Run `kickoff.sh --model opus --effort xhigh
https://github.com/acme/shop/issues/42`. The command still comes from
the table.

**User:** `what would /kickoff do for issue 70?`

Do not run the script. Read #70's labels and answer from the table:
the model, effort, and command it would pick, and why.

**User:** makes an issue with `/to-issue`, then `/kickoff on this pls`

One fresh issue in the session, so the target is clear. Run the script on
that issue's URL. Say the line. Stop.

**User:** `/kickoff 34 35 36 33` right after filing those four with
`/to-issue`, no epic among them; #35 has no size label

A set, in one pane. Read #35 and size it, say S. Run
`kickoff.sh --size 35=S https://github.com/acme/shop/issues/34 '#35' '#36' '#33'`.
One pane, one command, four layers in that order.

**User:** `/kickoff P1 of this epic, one pane each`, in a session about
epic #70, whose `### Phase 1` lists #71 and #72, both open

Run the script twice: `kickoff.sh https://github.com/acme/shop/issues/71`,
then `kickoff.sh https://github.com/acme/shop/issues/72`. Say both lines.

**User:** `/kickoff on this` with no issue or PR anywhere in the session

Nothing to resolve. Do not run the script. Tell the user you found no
target in the session and ask for the link.
