# run-in-t3

Starts the skill each issue needs in a new T3 Code thread: `/triage` for a bug, `/grill` for a seed, `/ready-pr` for an issue with an open PR, `/complete-task` for a task, and `/ship` for a sized ticket.

## Use it when

You work in T3 Code and want an issue's next step to run in its own thread while you keep going in this one. Name the issues the way you would to a person:

- `/run-in-t3 42`: one issue.
- `/run-in-t3 12 and 14`: two tickets in one `/ship` thread, as a stack.
- `/run-in-t3 12 14 15, the rest one thread each`: #12 and #14 share a `/ship` thread, #15 gets its own.
- `/run-in-t3 all of P1 in this epic`: the open tickets of that phase.
- `/run-in-t3 the whole epic`: every open ticket in it, in one `/ship` thread.
- `/run-in-t3 42 on PR 80`: one ticket as a new layer on an open stack.
- `/run-in-t3 on this`, right after making an issue: it finds the issue in the chat.

Name a model, an effort, or how far `/ship` goes ("review the plan first", "ship it" to stop at a ready PR, or "ship and merge") in your words to change the defaults. Name none, and each `/ship` run picks its own ship mode from its plan.

## What you get

The shared Router reads each issue's labels and open PRs and picks the skill and the effort. You can name `/triage`, `/grill`, or `/ready-pr` for an issue, as "triage 44", "grill it", or "ready the PR", and it beats the labels; a closed issue or an epic still gets no thread, and `/ready-pr` needs one open PR:

| Issue | Skill | Effort |
|---|---|---|
| `bug` | `/triage` | high |
| `seed` | `/grill` | high |
| one open PR closes it | `/ready-pr` on that PR | medium |
| `manual` | `/complete-task`, which waits for your `go` | medium |
| `ready-to-build`, or XS or S | `/ship` | medium |
| M or L | `/ship` | high |
| XL | `/ship` | xhigh |

Every thread runs on opus unless you name a model. Several `/ship` tickets share one thread, at the highest effort among them. Issues that need different skills each get their own thread, and when your words leave the grouping unclear, it asks before it starts anything.

An issue with no label that picks a skill gets a proposal: the skill it guesses, the effort, the reason, and a short quote from the issue. Nothing starts until you say yes. Your yes goes on the issue as a label (`bug`, `seed`, `manual`, or a size), so no skill has to guess that issue again.

A closed issue, an XXL one, a task that waits outside, and an issue with two open PRs get no thread, and the report says why.

The chat gets one line per thread, then one line per issue with no thread:

```
#42 Login fails → #42 Login fails · /triage · effort high (default) · bug
#12 #14 Add CSV → #12 #14 Add CSV · /ship · effort high (default) · size M of 2 tickets
#16 Old idea · no thread, skipped
```

The thread gets the command with issue numbers, not URLs: `/ship #12 #14`, `/triage #42`, or `/ready-pr #80`. If `gh` in that checkout sees another repo, as a fork clone can, it gets the full URLs.

The script makes the repo a T3 project if it is not one yet. The agent starts each thread with T3's own tool, because `t3 thread start` cannot set the effort. Each thread runs on the newest T3 model of that name, in the permission mode of the chat that starts it. Your tree stays as it is: any branch, edits or not.

## Needs

- A T3 Code chat. The script runs the `t3` command that T3 names in `T3CODE_CLI_PATH`, found by the shared T3 lookup, [t3-cli.sh](../../shared/t3-cli.sh).
- `gh` (signed in), `git`, and `jq`.
- A main checkout the shared checkout resolver can find: the map `~/.config/kickoff/repos.tsv` (`owner/repo<TAB>path`, set `KICKOFF_REPO_MAP` to move it), the current folder, or a search under `~/development` (set `KICKOFF_DEV_ROOT` to change it).
- The skills its threads start, installed for Claude Code: [ship](../ship/), [triage](../triage/), [grill](../grill/), [ready-pr](../ready-pr/), and [complete-task](../complete-task/).

## Fits with

- Asks the shared Router, `../../shared/route/router.sh`, about each issue, as [orchestrate](../orchestrate/) does, so both skills start the same step for the same issue.
- Builds each thread's folder and first message with the shared launcher, `../../shared/launch/line.sh`, and starts it by the shared launch steps, `../../shared/launch/launch-t3.md`.
- Guesses a step for an unlabeled issue by the shared rules in `../../shared/route/propose.md`, and writes your yes with the shared label writer, `../../shared/route/edit-labels.sh`.
- Often follows [file-issue](../file-issue/) or [capture](../capture/), which make the issue.

## Tests

The cases for [kickoff.sh](scripts/kickoff.sh), its routes, thread lines, labels, the T3 check, and the project add, are in [tests/kickoff.sh](tests/kickoff.sh). The project add lives in the shared core's [project.sh](../../shared/launch/project.sh), which orchestrate shares. The cases run on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `t3` of their own. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
