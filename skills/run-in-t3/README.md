# run-in-t3

Starts `/ship` in a new T3 Code thread on an issue, a run of tickets, or a whole epic.

## Use it when

You work in T3 Code and want planning or a whole `/ship` run to start in its own thread while you keep going in this one. Name the issues the way you would to a person:

- `/run-in-t3 42`: one ticket.
- `/run-in-t3 12 and 14`: two tickets in one thread, as a stack.
- `/run-in-t3 all of P1 in this epic`: the open tickets of that phase.
- `/run-in-t3 the whole epic`: every open ticket in it.
- `/run-in-t3 42 on PR 80`: one ticket as a new layer on an open stack.
- `/run-in-t3 on this`, right after making an issue: it finds the issue in the chat.

More than one issue goes in one thread, unless you say "one thread each". Name a model, an effort, or how far `/ship` goes ("review the plan first", "ship it" to stop at a ready PR, or "ship and merge") in your words to change the defaults below. Name none of these, and the `/ship` run picks its own ship mode from its plan. You can also name triage, grill, or ready-pr ("triage it", "grill it", "ready the PR"): triage and grill run on opus at high effort, ready-pr on opus at medium. For a task issue, one with the `manual` label, name complete-task ("do the task"): it runs on opus at medium, and the agent says it is ready and waits for your `go`. It only runs when you call it.

## What you get

A shared script finds the repo on disk and picks the model, effort, and command from the tickets' labels:

| Tickets | Model | Effort | Command |
|---|---|---|---|
| every one `ready-to-build` | opus | medium | `/ship` |
| all XS or S | opus | medium | `/ship` |
| any M or L | opus | high | `/ship` |
| any XL, or no size | opus | xhigh | `/ship` |

The thread gets the command with issue numbers, not URLs: `/ship #42`, `/ship #42 #43`, or `/ready-pr #43`. If `gh` in that checkout sees another repo, as a fork clone can, it gets the full URLs. A `/ready-pr` PR in another repo also keeps its full URL.

This skill's script then makes the repo a T3 project if it is not one yet. The agent starts the thread with T3's own tool, because `t3 thread start` cannot set the effort. The thread runs on the newest T3 model of that name, in the permission mode of the chat that starts it: start from a chat in full access, and the thread's helpers in Antigravity run without asking you at each command.

The chat gets one line and stops:

```
#42 Export orders as CSV → #42 Export orders as CSV · /ship (default) · model claude-opus-5-5 (default) · effort medium (default) · size M · base main · project found
```

Your tree stays as it is: any branch, edits or not.

## Needs

- A T3 Code chat. The script runs the `t3` command that T3 names in `T3CODE_CLI_PATH`, found by the shared T3 lookup, [t3-cli.sh](../../shared/t3-cli.sh).
- `gh` (signed in), `git`, and `jq`.
- A main checkout the shared checkout resolver can find: the map `~/.config/kickoff/repos.tsv` (`owner/repo<TAB>path`, set `KICKOFF_REPO_MAP` to move it), the current folder, or a search under `~/development` (set `KICKOFF_DEV_ROOT` to change it).
- The [ship](../ship/) skill, installed for Claude Code.

## Fits with

- Starts [ship](../ship/) in the new thread. It sets a ship mode only when you name one; else the `/ship` run picks it.
- Runs the shared decide script, `../../shared/kickoff/decide.sh`, which gives the command as the thread runs it, as `/ship --merge`, in its own field, and reads `../../shared/kickoff/target.md`.
- Its thread launch steps (model, project, thread) live in the shared core, `../../shared/kickoff/launch-t3.md`, so another skill can start a T3 thread the same way: [orchestrate](../orchestrate/) does.
- Often follows [file-issue](../file-issue/) or [capture](../capture/), which make the issue.

## Tests

The cases for [kickoff.sh](scripts/kickoff.sh), the T3 check, the project add, and the line it prints, are in [tests/kickoff.sh](tests/kickoff.sh). The project add lives in the shared core's [project.sh](../../shared/kickoff/project.sh), which orchestrate shares. The cases run on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `t3` of its own. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
