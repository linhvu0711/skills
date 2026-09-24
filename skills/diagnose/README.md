# diagnose

Finds the root cause of a bug, or the hot spot behind something slow, and stops there. It does not fix anything.

## Use it when

Something is broken or slow, and you don't know why yet. Type `/diagnose` with what you see (`$diagnose` in Codex), as in `/diagnose the CSV export shows dates as big numbers`. It needs the symptom and nothing else; "something is off" gets one question back.

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

For a slow thing the cause line is a hot spot with its share of the time, like `900 of 1200 ms`. When the fix is a real choice (two fixes with a different blast radius, or a trade-off like batch or cache), it runs a grill on that choice first. It ends with `Ready for /to-issue.` The repo is left as it found it, and your machine is yours to change: a local fix comes back as a command on the clipboard.

## Needs

- `git`, for the log and for `git bisect`.
- Sub-agents: Explore agents to read and Runner agents to run repro loops and bisects, in Claude Code. In Codex it does both itself.
- `pbcopy`, optional, for the fix command on a local-env bug.
- [grill](../grill/), when a decision is open.

## Fits with

- Calls [grill](../grill/) when the fix needs a decision.
- Hands its report to [to-issue](../to-issue/).
- Suggested by [grill](../grill/) for bugs and slow things, and by [to-issue](../to-issue/), [to-epic](../to-epic/), and [plan-up](../plan-up/) when a `fix` ticket has no known cause.

## Credits

Adapted from the `diagnosing-bugs` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills.
