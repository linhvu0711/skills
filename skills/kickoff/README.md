# kickoff

Opens a new herdr pane next to the one you are in and starts `/plan-up` there on an issue, a run of tickets, or a whole epic.

## Use it when

You work in herdr (a terminal workspace for AI coding agents) and want planning to start in its own pane while you keep going in this one. It takes the same arguments as [plan-up](../plan-up/):

- `/kickoff <issue-url>`: one ticket.
- `/kickoff <epic-url> #12 #14`: those tickets from the epic, as a stack.
- `/kickoff <issue-url> #12 #14`: a set of plain tickets, planned together.
- `/kickoff <epic-url>`: every open ticket in the epic.
- `/kickoff <issue-url> on <pr-url>`: one ticket as a new layer on an open stack.

`/kickoff on this` right after making an issue works too; it finds the issue in the chat. Add `--dry-run` to see what it would do. It only runs when you call it.

## What you get

A script checks that the repo is clean, on its base branch, and pulled, picks the effort from the size label (`medium` for XS or S, else `high`), opens the pane without taking focus, and types `/plan-up` into it. The chat gets one line and stops:

```
#42 Export orders as CSV → w4/w4:t1/w4:p9M · effort high (size above S or no size label) · tree clean on main · split in w4:t1
```

A dirty tree stops it before any pane is made, with the files listed.

## Needs

- herdr, and this chat running inside a herdr pane (`HERDR_ENV=1`).
- Claude Code, which the script starts in the new pane.
- `gh` (signed in), `git`, `jq`, and `python3`.
- A way to find the repo on disk: the map `~/.config/kickoff/repos.tsv` (`owner/repo<TAB>path`, set `KICKOFF_REPO_MAP` to move it), the current folder, or a search under `~/development` (set `KICKOFF_DEV_ROOT` to change it).
- The [plan-up](../plan-up/) skill in the new pane.

## Fits with

- Starts [plan-up](../plan-up/) in the new pane.
- Often follows [to-issue](../to-issue/) or [capture](../capture/), which make the issue.
- [land-pr](../land-pr/) finds a checkout the way this script does, and [ship](../ship/) uses its `equalize_columns.py` to even out pane widths.
