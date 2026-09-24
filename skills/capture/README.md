# capture

Files a raw idea or a bug you just noticed as a small GitHub issue, so it isn't lost. No diagnosis, no plan, no type.

## Use it when

Something crossed your mind and you want it parked in ten seconds. Type `/capture` followed by the thing (`$capture` in Codex), or say "capture this", "park this", "log this bug", "track this for later". Add `p0` to `p3` or a word like "urgent" if you want a priority label. When you want a real, typed ticket, use [to-issue](../to-issue/) instead.

## What you get

One issue, in the repo's own title style, and one line back with its URL (also on your clipboard):

```
Captured: https://github.com/acme/shop/issues/88 (on your clipboard)
```

It is a seed (an idea nobody has decided to do) or a bug (something seen broken today). The body holds your words, any file paths or error lines already in the chat, and a status line that says it is not triaged. The first time it sees a repo it reads 30 recent titles and the labels to learn the prefix style and the priority labels, and it remembers them. It asks at most one question, "Which repo?", and only when it can't tell.

## Needs

- `gh`, signed in.
- `python3`, for `scripts/conventions.py`, which stores each repo's title style in `~/.config/capture/conventions.json` and its priority labels in `~/.config/gh-issues/priority-labels.json`.
- `pbcopy`, optional, for the clipboard.
- From the shared core: [issue-rules.md](../../shared-skill-core/issue-rules.md), which owns the label names and colors.

## Fits with

- A seed grows up through [grill](../grill/) (`/grill #88`) or [discover-path](../discover-path/). A bug becomes a `fix` ticket through [to-issue](../to-issue/), which then closes the `[bug]`.
- Called by [grill](../grill/) to file a seed for an idea it grilled, by [land-pr](../land-pr/) and [validate-pr-review](../validate-pr-review/) for each `fix later` finding, and by [handoff-devin](../handoff-devin/) and [handoff-cursor](../handoff-cursor/) to file a bug.
- Named by [kickoff](../kickoff/) and [set-coding-standards](../set-coding-standards/). The shared core's issue rules read the priority labels through its `scripts/conventions.py`.

## Credits

None. This skill was written for this repo.
