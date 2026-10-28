# kickoff-herdr

Opens a new herdr pane next to the one you are in and starts `/ship-ready`, `/ship-full`, or `/plan-up` there on an issue, a run of tickets, or a whole epic.

## Use it when

You work in herdr (a terminal workspace for AI coding agents) and want planning or a whole ship-ready or ship-full run to start in its own pane while you keep going in this one. Name the issues the way you would to a person:

- `/kickoff-herdr 42`: one ticket.
- `/kickoff-herdr 12 and 14`: two tickets in one pane, as a stack.
- `/kickoff-herdr all of P1 in this epic`: the open tickets of that phase.
- `/kickoff-herdr the whole epic`: every open ticket in it.
- `/kickoff-herdr 42 on PR 80`: one ticket as a new layer on an open stack.
- `/kickoff-herdr on this`, right after making an issue: it finds the issue in the chat.

More than one issue goes in one pane, unless you say "one pane each". Name a model, an effort, or the command ("ship it" for ship-ready, "ship and merge" for ship-full, or "plan only") in your words to change the defaults below. You can also name triage, grill, or ready-pr ("triage it", "grill it", "ready the PR"): triage and grill run on opus at high effort, ready-pr on opus at medium. URLs work too, and it takes the same forms as [plan-up](../plan-up/). It only runs when you call it.

## What you get

A shared script finds the repo on disk and picks the model, effort, and command from the tickets' labels. This skill opens the pane without taking focus, starts Claude Code there, and types the command into it:

| Tickets | Model | Effort | Command |
|---|---|---|---|
| every one `ready-to-build` | sonnet | high | `/ship-ready` |
| all XS or S | opus | medium | `/ship-ready` |
| any M | opus | medium | `/plan-up` |
| any L, XL, or no size | opus | high | `/plan-up` |

In a group of tickets, the biggest one picks the row. `manual` tickets do not count. A ticket with no size label gets a size from its text, guessed by the agent, and the line says `guessed`.

The chat gets one line and stops:

```
#42 Export orders as CSV → w4/w4:t1/w4:p9M · /plan-up (default) · model opus (default) · effort medium (default) · size M · base main · split in w4:t1
```

Your tree stays as it is: any branch, edits or not. plan-up reads its own fresh copy of the base branch.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

## Needs

- herdr, and this chat running inside a herdr pane (`HERDR_ENV=1`).
- Claude Code, which the script starts in the new pane.
- `gh` (signed in), `git`, `jq`, and `python3`.
- A main checkout the shared checkout resolver can find: the map `~/.config/kickoff-herdr/repos.tsv` (`owner/repo<TAB>path`, set `KICKOFF_REPO_MAP` to move it), the current folder, or a search under `~/development` (set `KICKOFF_DEV_ROOT` to change it).
- The [ship-ready](../ship-ready/), [ship-full](../ship-full/), and [plan-up](../plan-up/) skills in the new pane.

## Fits with

- Starts [ship-ready](../ship-ready/), [ship-full](../ship-full/), or [plan-up](../plan-up/) in the new pane. It starts ship-full only when you ask for the merge.
- Often follows [to-issue](../to-issue/) or [capture](../capture/), which make the issue.
- It runs the shared decide script, `../../shared/kickoff/decide.sh`, and reads its target rules in `../../shared/kickoff/target.md`, as [kickoff-t3](../kickoff-t3/) does in a T3 Code thread.
- It finds the repo through the shared checkout resolver, `../../shared/checkout.sh`, as [ready-pr](../ready-pr/) and [ship-ready](../ship-ready/) do; [build-and-prove](../build-and-prove/) uses its `equalize_columns.py` to even out pane widths.

## Tests

The cases for [kickoff.sh](scripts/kickoff.sh), the checkout lookup and the model, effort, command, and name it picks, are in [tests/kickoff.sh](tests/kickoff.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `herdr` of its own. The cases for the shared decide script are in `../../shared/tests/kickoff-decide.sh`. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
