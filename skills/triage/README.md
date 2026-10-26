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
Also at: src/orders/invoice.ts:31, writes the raw createdAt too
```

Once the cause is confirmed, it searches for the same mistake elsewhere: the `Also at:` line names each place, or says `none found` with the search it ran, and the ticket carries the same places as links to the lines, so they still point at the right code after later changes. For a slow thing the cause line is a hot spot with its share of the time, like `900 of 1200 ms`. The baseline passes the one-side checks of the shared [benchmark checklist](../../shared/benchmark.md): repeat runs with the median and spread, the limit named, the physical limit, and the share of the path. Old and new in turns, and both sides tuned, come in when it compares the number with the hot spot stubbed. The report then carries `Baseline:` and `Target:` lines. The fix takes the first rung of the fix order that reaches the target: don't do it, don't repeat it, do less, do it later, do it in parallel, do it cheaper. When the fix is a real choice (two fixes with a different blast radius, or a trade-off like batch or cache), it runs a grill on that choice first, and the doc text the grill agrees on goes into the ticket, so the fix PR writes it. When the fix is clear, it skips the grill.

Then it files the ticket itself, through [to-issue](../to-issue/). The ticket follows the bug's category: a `fix` for our code, a `perf` for a hot spot, a `chore` for a missing guard or a pinned dependency, a `docs` for a missing setup step, or nothing when no code work is left. It files a `spike` when it cannot find the cause. The part that is yours (an ops fix, a data fix, a local command) stays in the report. You do not run `/to-issue`. When you started from an issue, like `/triage #42`, that issue becomes the ticket: new title, new body, same number, and the old text kept under "Original report". Nothing new is opened and nothing is closed.

The repo is left as it found it, and your machine is yours to change: a local fix comes back as a command on the clipboard.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

## Needs

- `git`, for the log and for `git bisect`.
- `gh`, signed in, to read the issue you name and to file the ticket.
- Sub-agents: Explore agents to read and Runner agents to run repro loops and bisects, in Claude Code. In Codex it does both itself.
- A clipboard tool, optional, for the fix command on a local-env bug, through [copy.sh](../../shared/copy.sh): macOS, Linux, or Windows. With none, it says the copy was skipped.
- [benchmark.md](../../shared/benchmark.md) from the shared core: the checks a speed number must pass.
- [grill](../grill/), when a decision is open.
- [to-issue](../to-issue/), to file the ticket.

## Fits with

- Calls [grill](../grill/) when the fix needs a decision.
- Calls [to-issue](../to-issue/) to file the ticket, and to rewrite the bug issue into it.
- Suggested by [grill](../grill/) for bugs and slow things, and by [to-issue](../to-issue/), [to-epic](../to-epic/), and [plan-up](../plan-up/) when a `fix` ticket has no known cause.

## Credits

Adapted from the `diagnosing-bugs` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills.

The perf baseline checks, the fix order, and the search for the same mistake elsewhere take ideas from the `benchmark-checklist` skill and `poteto-mode/playbooks/perf-issue.md` in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
