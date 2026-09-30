# triage

Finds the root cause of a bug, or the hot spot behind something slow, then files the fix ticket. It does not change any code.

## Use it when

Something is broken or slow, and you don't know why yet. Type `/triage` with what you see (`$triage` in Codex), as in `/triage the CSV export shows dates as big numbers`. You can also name an issue, as in `/triage #42` or its URL; it reads the issue and its comments. It needs the symptom and nothing else; "something is off" gets one question back.

## What you get

A short report in chat that a worker can pick up cold:

```
Expected: createdAt as an ISO date
Actual: createdAt as epoch milliseconds
Repro: pnpm test export
Cause: src/orders/export.ts:57, writes the raw createdAt and skips formatDate, unlike line 49
Category: Our code
Evidence: the export test with an ISO assertion fails on that field
```

For a slow thing the cause line is a hot spot with its share of the time, like `900 of 1200 ms`. When the fix is a real choice (two fixes with a different blast radius, or a trade-off like batch or cache), it runs a grill on that choice first. When the fix is clear, it skips the grill.

Then it files the ticket itself, through [to-issue](../to-issue/): a `fix` or `perf` ticket, or a `spike` when the cause was not found. You do not run `/to-issue`. When you started from an issue, like `/triage #42`, that issue becomes the ticket: new title, new body, same number, and the old text kept under "Original report". Nothing new is opened and nothing is closed.

The repo is left as it found it, and your machine is yours to change: a local fix comes back as a command on the clipboard.

## Needs

- `git`, for the log and for `git bisect`.
- `gh`, signed in, to read the issue you name and to file the ticket.
- Sub-agents: Explore agents to read and Runner agents to run repro loops and bisects, in Claude Code. In Codex it does both itself.
- `pbcopy`, optional, for the fix command on a local-env bug.
- [grill](../grill/), when a decision is open.
- [to-issue](../to-issue/), to file the ticket.

## Fits with

- Calls [grill](../grill/) when the fix needs a decision.
- Calls [to-issue](../to-issue/) to file the ticket, and to rewrite the bug issue into it.
- Suggested by [grill](../grill/) for bugs and slow things, and by [to-issue](../to-issue/), [to-epic](../to-epic/), and [plan-up](../plan-up/) when a `fix` ticket has no known cause.

## Credits

Adapted from the `diagnosing-bugs` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills.
