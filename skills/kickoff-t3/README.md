# kickoff-t3

Starts `/ship-ready`, `/ship-full`, or `/plan-up` in a new T3 Code thread on an issue, a run of tickets, or a whole epic.

## Use it when

You work in T3 Code and want planning or a whole ship-ready or ship-full run to start in its own thread while you keep going in this one. Name the issues the way you would to a person:

- `/kickoff-t3 42`: one ticket.
- `/kickoff-t3 12 and 14`: two tickets in one thread, as a stack.
- `/kickoff-t3 all of P1 in this epic`: the open tickets of that phase.
- `/kickoff-t3 the whole epic`: every open ticket in it.
- `/kickoff-t3 42 on PR 80`: one ticket as a new layer on an open stack.
- `/kickoff-t3 on this`, right after making an issue: it finds the issue in the chat.

More than one issue goes in one thread, unless you say "one thread each". Name a model, an effort, or the command ("ship it" for ship-ready, "ship and merge" for ship-full, or "plan only") in your words to change the defaults below. You can also name triage, grill, or ready-pr ("triage it", "grill it", "ready the PR"): triage and grill run on opus at high effort, ready-pr on opus at medium. It only runs when you call it. For a herdr pane, use [kickoff-herdr](../kickoff-herdr/).

## What you get

A shared script finds the repo on disk and picks the model, effort, and command from the tickets' labels:

| Tickets | Model | Effort | Command |
|---|---|---|---|
| every one `ready-to-build` | sonnet | high | `/ship-ready` |
| all XS or S | opus | medium | `/ship-ready` |
| any M | opus | medium | `/plan-up` |
| any L, XL, or no size | opus | high | `/plan-up` |

This skill's script then makes the repo a T3 project if it is not one yet. The agent starts the thread with T3's own tool, because `t3 thread start` cannot set the effort or the permission mode. The thread runs in `auto` mode, on the newest T3 model of that name.

The chat gets one line and stops:

```
#42 Export orders as CSV → i42 Export orders as CSV · /plan-up (default) · model claude-opus-5-5 (default) · effort medium (default) · size M · base main · project found
```

Your tree stays as it is: any branch, edits or not.

## Needs

- A T3 Code chat. The script runs the `t3` command that T3 names in `T3CODE_CLI_PATH`.
- `gh` (signed in), `git`, and `jq`.
- A main checkout the shared checkout resolver can find: the map `~/.config/kickoff/repos.tsv` (`owner/repo<TAB>path`, set `KICKOFF_REPO_MAP` to move it), the current folder, or a search under `~/development` (set `KICKOFF_DEV_ROOT` to change it).
- The [ship-ready](../ship-ready/), [ship-full](../ship-full/), and [plan-up](../plan-up/) skills, installed for Claude Code.

## Fits with

- Starts [ship-ready](../ship-ready/), [ship-full](../ship-full/), or [plan-up](../plan-up/) in the new thread. It starts ship-full only when you ask for the merge.
- [kickoff-herdr](../kickoff-herdr/) does the same in a herdr pane. Both run the shared decide script, `../../shared/kickoff/decide.sh`, and read `../../shared/kickoff/target.md`.
- Its thread launch steps (model, project, thread) live in the shared core, `../../shared/kickoff/launch-t3.md`, so another skill can start a T3 thread the same way: [orchestrate](../orchestrate/) does.
- Often follows [to-issue](../to-issue/) or [capture](../capture/), which make the issue.

## Tests

The cases for [kickoff.sh](scripts/kickoff.sh), the T3 check, the project add, and the line it prints, are in [tests/kickoff.sh](tests/kickoff.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh) and a fake `t3` of its own. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
