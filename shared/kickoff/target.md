# Kickoff target

Shared by kickoff-herdr and kickoff-t3. Both turn what the user said into
the arguments of their `scripts/kickoff.sh`, and both scripts run
`decide.sh`, the script next to this file, which reads them. This file
holds the target forms, the flags, the table the script picks from, and
how to turn the user's words into a target.

## Target forms

The target takes `/plan-up`'s forms, with full URLs. The script passes
it on unchanged:

- `<issue-url>`: one ticket.
- `<epic-url> #12 #14`: a run of the named tickets under that epic.
- `<issue-url> #12 #14`: a set. Plain tickets with no shared parent,
  in one pane or thread, in the order given. The first URL is the first
  ticket. The script tells a set from a run by whether the first issue
  has sub-issues.
- `<epic-url>`: the whole epic. The script sees the sub-issues and
  knows.
- `<issue-url> on <pr-url>`: a new layer on an open stack.

## Flags

Flags you may add:

- `--label <name>` when the user names the pane or thread.
  Names match `[a-z][a-z0-9_-]{0,31}`.
- `--size <n>=<size>`, size one of XS, S, M, L, XL, once for each
  ticket with no size label: the size you guessed from its body
  (§ Resolving the target). It counts like a label, and the report line
  says `guessed`.
- `--model <name>` when the user names a model: an alias (`opus`,
  `sonnet`, `haiku`) or a full model name.
- `--effort <level>` when the user names an effort: `low`, `medium`,
  `high`, `xhigh`, or `max`.
- `--command ship-ready`, `--command ship-full`, or `--command plan-up`
  when the user names the command: "plan only" is `plan-up`, "ship it"
  is `ship-ready`, "ship and merge" or "full ship" is `ship-full`. The
  table never picks `ship-full`: a merge needs the user's words.
- `--command triage`, `--command grill`, or `--command ready-pr` when
  the user names that skill: "triage it" is `triage`, "grill it" is
  `grill`, "ready the PR" is `ready-pr`. The table never picks these.

A value the user does not name comes from the table below. The report
line marks each value `(default)` or `(set)`.

## What the script decides

So you can answer questions about it:

- Model, effort, and command, from the size and `ready-to-build`
  labels. Sizes match loosely (`size/S`, `Size: Medium`):

  | Tickets | Model | Effort | Command |
  |---|---|---|---|
  | every one `ready-to-build` | `sonnet` | `high` | `/ship-ready` |
  | all XS or S | `opus` | `medium` | `/ship-ready` |
  | any M | `opus` | `medium` | `/plan-up` |
  | any L, XL, or no size | `opus` | `high` | `/plan-up` |

  In a run, a set, or a whole epic the biggest ticket picks the row;
  only a target whose every ticket is `ready-to-build` takes the sonnet
  row. A whole epic counts its open tickets. `manual` tickets do not
  count; a target with none left stops.

  A named `triage`, `grill`, or `ready-pr` picks its own row instead:

  | Command | Model | Effort |
  |---|---|---|
  | `/triage` | `opus` | `high` |
  | `/grill` | `opus` | `high` |
  | `/ready-pr` | `opus` | `medium` |

  `--model` and `--effort` still win over every row. With `ready-pr`,
  the thread gets the URL of the open PR that closes the issue in place
  of the issue URL. An issue with no open PR, or with two or more,
  stops.
- Permission mode is `auto`.
- Repo path: found by the checkout resolver,
  `../checkout.sh main <owner/repo>`, whose header says where it looks.
  A find is written to the map. None or several: it stops and says so.
- Tree: left as is, on any branch, with edits or not. `/plan-up` reads
  its own fresh copy of the base, so the script never switches, pulls,
  or stops on it.
- Label: `i` and the issue numbers, as `i42`, `i42-43`, `i42-on-80`,
  and `i70` for a whole epic.

## Resolving the target from the session

The user seldom pastes a URL. They name issues by number or in words,
most often ones this session made or talked about: `12`, `12 and 14`,
`all of P1 in this epic`, `on this`, or nothing right after `/to-issue`.
Before you run the script, do these steps.

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
3. **One or each.** One pane or thread for all the issues, unless the
   user asks for "one pane each", "one thread each", or the like. One:
   tickets that are all sub-issues of one epic go as a run,
   `<epic-url> #a #b`; else as a set, `<first-url> #b #c`, in the order
   the user gave. Never attach tickets to an epic to make a run. One
   each: run the script once per issue, one after the other.
4. **Sizes.** For each ticket with no size label (`gh issue view <n>
   --json labels,title,body`), read its title and body and size it by
   `../size.md`. Pass `--size <n>=<size>`. Skip a ticket that has a
   size label.
5. **Flags.** A model, an effort, or a command in the user's words
   becomes `--model`, `--effort`, or `--command` (§ Flags). A word the
   flags do not take: ask.

The word `on` is overloaded: `on this` can mean "target this issue" or
the `on <pr-url>` stack form. When that is unclear, ask before running.
