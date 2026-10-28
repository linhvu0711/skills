# capture

Files a raw idea or a bug you just noticed as a small GitHub issue, so it isn't lost. No diagnosis, no plan, no type.

## Use it when

Something crossed your mind and you want it parked in ten seconds. Type `/capture` followed by the thing (`$capture` in Codex), or say "capture this", "park this", "log this bug", "track this for later". Add `p0` to `p3` or a word like "urgent" if you want a priority label. When you want a real, typed ticket, use [to-issue](../to-issue/) instead.

## What you get

One issue, in the repo's own title style, and one line back with its URL (also on your clipboard):

```
Captured: https://github.com/acme/shop/issues/88 (on your clipboard)
```

It is a seed (an idea nobody has decided to do) or a bug (something seen broken today). The body holds your words, the facts already in the chat, and a status line that says it is not triaged. It is assigned to you, unless you name someone else or say no assignee. A bug also gets a Repro: the commands the chat ran, what failed, and how often when the chat measured it, or `Not known yet.` The body is written for a stranger with neither the chat nor your machine: code as permalinks, errors verbatim, screenshots uploaded, and no local paths, throwaway IDs, or session words. The first time it sees a repo it reads 30 recent titles and the labels to learn the prefix style and the priority labels, and it remembers them. Before it files, it searches open and closed issues. An open one on the same thing stops it; a closed one does not, and the new issue links it in Context as `Related: #<n> (closed)`, so a bug that came back keeps its history. It asks at most one question, "Which repo?", and only when it can't tell.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

## Needs

- `gh`, signed in. Screenshots need `--attach` on `gh issue create` (see `gh issue create --help`); without it the issue is still filed, with a sentence in place of each screenshot.
- `python3`, for `scripts/conventions.py`, which stores each repo's title style in `~/.config/capture/conventions.json` and its priority labels in `~/.config/gh-issues/priority-labels.json`.
- A clipboard tool, optional, for the URL, through [copy.sh](../../shared/copy.sh): macOS, Linux, or Windows. With none, it says the copy was skipped.
- From the shared core: [issue-rules.md](../../shared/issue-rules.md), which owns the label names and colors and the rules for writing for a stranger.

## Fits with

- A seed grows up through [grill](../grill/) (`/grill #88`) or [discover-path](../discover-path/). A bug becomes a `fix` ticket through [triage](../triage/) or [to-issue](../to-issue/), which rewrite the `[bug]` into the ticket in place.
- Called by [ready-pr](../ready-pr/) and [validate-pr-review](../validate-pr-review/) for each `fix later` finding, and by [handoff](../handoff/) to file a bug.
- Named by [kickoff](../kickoff/), [set-coding-standards](../set-coding-standards/), and [audit-coding-standards](../audit-coding-standards/). The shared core's issue rules read the priority labels through its `scripts/conventions.py`.

## Credits

This skill was written for this repo. The closed-issue search before filing comes from the triage dedupe of `automations/benny` in pstack, in [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack). Idea only; none of the text.
