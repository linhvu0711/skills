# factory

Runs a set of issues to closed from one pinned T3 Code thread. Every few minutes it starts a new thread for each issue that is free and has reached a new stage.

## Use it when

You have more issues than you want to start by hand, and you work in T3 Code. Name the set the way you would to a person:

- `/factory 12 14 15`: these issues.
- `/factory epic 70`: every open sub-issue of the epic, and any it gets later.
- `/factory assigned to me`: your open issues, read once at the start.

The thread you type it in becomes the factory. It pins itself, takes the title `factory: <the set>`, and stays the place where you steer the run. It only runs when you call it.

## What you get

Each issue gets a thread with the skill that fits where it is:

| Stage | How the factory sees it | Thread |
|---|---|---|
| seed | a `seed` label | `/grill` |
| bug | a `bug` label | `/triage` |
| ticket | a size label | `/ship-ready`, or `/ship-full` when you say so |
| PR open | an open PR that closes it, opened before the run | `/ready-pr <pr-url>` |
| task | a `manual` label | none: it is yours |
| epic | sub-issues | none: its open sub-issues join the set |
| unlabeled | none of the above | the one you answer to the factory's proposal, or none |
| done | closed | none |

The factory proposes a skill for each unlabeled issue, in one list in its thread: the proposal, the reason, and a quote from the issue. Answer the whole list in one reply, such as `all yes, but #14 is grill`, or `skip #15`. An answered issue starts as soon as it is free. A `close` or `task` answer starts nothing and is yours. Answers live in the state file, so `/factory resume` keeps them. An XL issue ships like any ticket.

An issue starts only when every issue that blocks it is closed. The model and effort come from the same table kickoff uses, `../../shared/kickoff/decide.sh`. Each issue gets one thread per stage. When triage turns a bug into a fix ticket, the next check starts `/ship-ready` on it. New sub-issues and the follow-ups `/ready-pr` lists in a PR body join the set by themselves.

The factory never retries, messages, or answers a thread it started. You handle every thread. A thread that fails, or ends with no new stage, waits for you to say `restart #n` (ADR 0013).

Say these in the factory thread:

- `check now`, `check every 10 min` (1 minute at least; the start is 5).
- `pause`, `resume`, `stop`. Pause stops new starts and lets running threads go on. Stop ends the timer and keeps the run, so `/factory resume` in any thread picks it up again.
- `add #16`, `remove #14`, `restart #12`.
- `ship-full #12` or `ship-full all`, and `ship-ready` the same way. A change reaches only issues whose ticket thread has not started.
- `#12 with sonnet xhigh`, or `all with opus high`.
- `all yes`, `#14 grill`, `#14 yes`, `skip #15`: answer the proposals.

A check that cannot read GitHub or T3 starts nothing and says why. After three in a row it tells you to act. When every issue is closed, with no open PR left on one, the factory stops its timer, posts one summary line per issue (its stages, its PR, its threads), and runs [prune-worktrees](../prune-worktrees/). It never closes an epic.

The run lives in `~/.agents/factory/<owner>-<repo>/<start time>/state.json`, outside every checkout (set `FACTORY_HOME` to move it). It holds only what GitHub and T3 do not: the set, the ship modes, the model choices, each thread's id, the timer, and the answers to its proposals. One run per repo is live at a time; `/factory` in a repo with a live run links that run's thread and stops.

## Needs

- A T3 Code chat. The script runs the `t3` command that T3 names in `T3CODE_CLI_PATH`, and the agent uses T3's tools for threads, the pin, and the scheduled task.
- `gh` (signed in), `git`, and `jq`.
- A main checkout the shared checkout resolver can find, as for [kickoff-t3](../kickoff-t3/).
- The [grill](../grill/), [triage](../triage/), [ship-ready](../ship-ready/), [ship-full](../ship-full/), [ready-pr](../ready-pr/), and [prune-worktrees](../prune-worktrees/) skills, installed for Claude Code.

## Fits with

- Starts each thread the way [kickoff-t3](../kickoff-t3/) does: the shared decide script, `../../shared/kickoff/decide.sh`, picks the model, effort, and command, and the shared launch steps, `../../shared/kickoff/launch-t3.md`, start the thread.
- Its threads run [grill](../grill/), [triage](../triage/), [ship-ready](../ship-ready/), [ship-full](../ship-full/), and [ready-pr](../ready-pr/). Only a ship-full thread merges, and only when you asked for ship-full.
- [capture](../capture/) makes the seeds and bugs it starts from; [to-epic](../to-epic/) makes the epics.

## Tests

The cases for [factory.sh](scripts/factory.sh), the route for each stage, blockers, one thread per stage, `restart`, a failed check, and the done rule, are in [tests/factory.sh](tests/factory.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `t3` of its own. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
