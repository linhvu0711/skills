# orchestrate

Runs a set of issues to closed from one pinned T3 Code thread. Every few minutes it starts a new thread for each issue that is free and has reached a new stage.

## Use it when

You have more issues than you want to start by hand, and you work in T3 Code. Name the set the way you would to a person:

- `/orchestrate 12 14 15`: these issues.
- `/orchestrate epic 70`: every open sub-issue of the epic, and any it gets later.
- `/orchestrate assigned to me`: your open issues, read once at the start.

The thread you type it in becomes the orchestrator. It pins itself, takes the title `orchestrate: <the set>`, and stays the place where you steer the run. It only runs when you call it.

## What you get

Each issue gets a thread with the skill that fits where it is:

| Stage | How the orchestrator sees it | Thread |
|---|---|---|
| seed | a `seed` label | `/grill` |
| bug | a `bug` label | `/triage` |
| ticket | a size label | `/ship`, which picks its own ship mode from its plan, or the ship mode you set |
| PR open | an open PR that closes it, opened before the run | `/ready-pr <pr-url>` |
| task | a `manual` label | none: it is yours |
| epic | sub-issues | none: its open sub-issues join the set |
| unlabeled | none of the above | the one you answer to the orchestrator's proposal, or none |
| done | closed | none |

The orchestrator proposes a skill for each unlabeled issue, in one list in its thread: the proposal, the model and effort its thread would get, the reason, and a quote from the issue. For an issue it would ship, it also reads the code the issue touches and gives a size by the [size rules](../../shared/size.md), with the facts behind it, such as `S: one path, about 4 files`. That size picks the model, so a small unlabeled issue no longer runs on the biggest row. Answer the whole list in one reply, such as `all yes, but #14 is grill`, or `skip #15`. An answered issue starts as soon as it is free. A `close` or `task` answer starts nothing and is yours. Answers live in the state file, so `/orchestrate resume` keeps them. An XL issue ships like any ticket.

An issue starts only when every issue that blocks it is closed. The model and effort come from the same table kickoff uses, `../../shared/kickoff/decide.sh`:

| Issue | Model | Effort |
|---|---|---|
| `ready-to-build`, XS, or S | opus | medium |
| M or L | opus | high |
| XL, or no size | opus | xhigh |
| `/triage` or `/grill` | opus | high |
| `/ready-pr` | opus | medium |

 Each issue gets one thread per stage. When triage turns a bug into a fix ticket, the next check starts `/ship` on it. New sub-issues and the follow-ups `/ready-pr` lists in a PR body join the set by themselves.

A board page shows the run while it goes: four columns (Shape, Build, Review, Done), each one scrolling on its own, an orange YOU strip on each card that waits for you with what to do, a blue dot on each running thread, and buttons to its thread and PR. Its tab shows a small board icon and the repo's name: a repo has one live run, so the name is enough. The orchestrator thread posts its link at the start and on `/orchestrate resume`. It reads only; you steer the run in the orchestrator thread.

The orchestrator never retries, messages, or answers a thread it started. You handle every thread. A thread that fails, or ends with no new stage, waits for you to say `restart #n` (ADR 0013).

The timer stays quiet unless something moved. A timer check posts a line only for an issue that changed since the last check: a new stage, a thread started or with a new status, a new blocker or PR, a proposal. When nothing changed, it posts nothing. A check that fails still posts why. `check now` posts every issue.

Say these in the orchestrator thread:

- `check now`, `check every 10 min` (1 minute at least; the start is 5).
- `pause`, `resume`, `stop`. Pause stops new starts and lets running threads go on. Stop ends the timer and keeps the run, so `/orchestrate resume` in any thread picks it up again.
- `add #16`, `remove #14`, `restart #12`.
- `ship merge #12` or `ship merge all`, and `ship review` and `ship ready` the same way, to set the ship mode: `review` waits for your ok on the plan, `ready` stops at a ready PR, `merge` merges it. With none set, each `/ship` thread picks its own. A change reaches only issues whose ticket thread has not started.
- `#12 with sonnet xhigh`, or `all with opus high`. This wins over the table, and over the model a proposal named.
- `all yes`, `#14 grill`, `#14 yes`, `skip #15`: answer the proposals.

A check that cannot read GitHub or T3 starts nothing and says why. After three in a row it tells you to act. When every issue is closed, with no open PR left on one, the orchestrator stops its timer, posts one summary line per issue (its stages, its PR, its threads), runs [prune-worktrees](../prune-worktrees/), and starts one more thread that runs [retro](../retro/) on everything the run did: its sessions and its PRs. If that thread cannot start, it posts the `/retro run` line for you to type. It never closes an epic.

The run lives in `~/.agents/orchestrate/<owner>-<repo>/<start time>/state.json`, outside every checkout (set `ORCHESTRATE_HOME` to move it). It holds only what GitHub and T3 do not: the set, the ship modes, the model choices, each thread's id, the timer, and its proposals: each route, size, and answer. Next to it sit `board.json`, the page data each check writes, and `board.html`, the page. One run per repo is live at a time; `/orchestrate` in a repo with a live run links that run's thread and stops.

## Needs

- A T3 Code chat. The script runs the `t3` command that T3 names in `T3CODE_CLI_PATH`, and the agent uses T3's tools for threads, the pin, and the scheduled task.
- `gh` (signed in), `git`, and `jq`.
- `python3`, for [serve.sh](../../shared/serve.sh), which serves the board on 127.0.0.1.
- A main checkout the shared checkout resolver can find, as for [kickoff-t3](../kickoff-t3/).
- The [grill](../grill/), [triage](../triage/), [ship](../ship/), [ready-pr](../ready-pr/), and [prune-worktrees](../prune-worktrees/) skills, installed for Claude Code.

## Fits with

- Starts each thread the way [kickoff-t3](../kickoff-t3/) does: the shared decide script, `../../shared/kickoff/decide.sh`, picks the model, effort, and command, and the shared launch steps, `../../shared/kickoff/launch-t3.md`, start the thread.
- Its threads run [grill](../grill/), [triage](../triage/), [ship](../ship/), and [ready-pr](../ready-pr/). A `/ship` thread merges only in ship mode `merge`: one you set, or one its agent picked from the plan, per [ADR 0014](../../docs/adr/0014-the-agent-picks-the-ship-mode.md).
- [capture](../capture/) makes the seeds and bugs it starts from; [to-epic](../to-epic/) makes the epics.
- When a run is done, it starts [retro](../retro/) on the run, which suggests changes to the repo's agent setup from what the run's sessions and PRs show.

## Tests

The cases for [orchestrate.sh](scripts/orchestrate.sh), the route for each stage, the quiet timer check, blockers, one thread per stage, `restart`, the proposals and answers, a failed check, the done rule, and the board data (each card's column, chip, mark, and action), are in [tests/orchestrate.sh](tests/orchestrate.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `t3` of its own. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
