# kickoff

Opens a new herdr pane next to the one you are in and starts `/ship` or `/plan-up` there on an issue, a run of tickets, or a whole epic.

## Use it when

You work in herdr (a terminal workspace for AI coding agents) and want planning or a full ship to start in its own pane while you keep going in this one. Name the issues the way you would to a person:

- `/kickoff 42`: one ticket.
- `/kickoff 12 and 14`: two tickets in one pane, as a stack.
- `/kickoff all of P1 in this epic`: the open tickets of that phase.
- `/kickoff the whole epic`: every open ticket in it.
- `/kickoff 42 on PR 80`: one ticket as a new layer on an open stack.
- `/kickoff on this`, right after making an issue: it finds the issue in the chat.

More than one issue goes in one pane, unless you say "one pane each". Name a model, an effort, or the command (`ship` or "plan only") in your words to change the defaults below. URLs work too, and it takes the same forms as [plan-up](../plan-up/). It only runs when you call it.

## What you get

A script finds the repo on disk, picks the model, effort, and command from the tickets' labels, opens the pane without taking focus, starts Claude Code there, and types the command into it:

| Tickets | Model | Effort | Command |
|---|---|---|---|
| every one `ready-to-build` | sonnet | high | `/ship` |
| all XS or S | opus | medium | `/ship` |
| any M | opus | medium | `/plan-up` |
| any L, XL, or no size | opus | high | `/plan-up` |

In a group of tickets, the biggest one picks the row. `manual` tickets do not count. A ticket with no size label gets a size from its text, guessed by the agent, and the line says `guessed`.

The chat gets one line and stops:

```
#42 Export orders as CSV → w4/w4:t1/w4:p9M · /plan-up · model opus (default) · effort medium (default) · size M · base main · split in w4:t1
```

Your tree stays as it is: any branch, edits or not. plan-up reads its own fresh copy of the base branch.

## Needs

- herdr, and this chat running inside a herdr pane (`HERDR_ENV=1`).
- Claude Code, which the script starts in the new pane.
- `gh` (signed in), `git`, `jq`, and `python3`.
- A main checkout the shared checkout resolver can find: the map `~/.config/kickoff/repos.tsv` (`owner/repo<TAB>path`, set `KICKOFF_REPO_MAP` to move it), the current folder, or a search under `~/development` (set `KICKOFF_DEV_ROOT` to change it).
- The [ship](../ship/) and [plan-up](../plan-up/) skills in the new pane.

## Fits with

- Starts [ship](../ship/) or [plan-up](../plan-up/) in the new pane.
- Often follows [to-issue](../to-issue/) or [capture](../capture/), which make the issue.
- It finds the repo through the shared checkout resolver, `../../shared-skill-core/checkout.sh`, as [ready-pr](../ready-pr/) and [ship](../ship/) do; [build-and-prove](../build-and-prove/) uses its `equalize_columns.py` to even out pane widths.

## Tests

The cases for [kickoff.sh](scripts/kickoff.sh), the checkout lookup and the model, effort, command, and name it picks, are in [tests/kickoff.sh](tests/kickoff.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `herdr` of its own. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
