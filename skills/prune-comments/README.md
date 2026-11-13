# prune-comments

Finds code comments that teach agents bad habits, removes the useless ones after your go, and logs an issue for each hack it keeps.

## Use it when

Agents in your repo keep copying hacks and trusting stale comments. A `// temp fix, clean up later` tells the next agent that hacks are fine there. Type `/prune-comments` (`$prune-comments` in Codex), or add a path: `/prune-comments src/billing`. With no path it reads the whole repo, minus vendored, generated, and gitignored files.

## What you get

A list in chat, before anything changes. It shows how many comments stay, the ones that are clear to remove grouped by kind (repeats the code, commented-out code, no longer true, banner lines) with a few examples each, and a numbered table of the ones that need you. Each row in that table has a suggested choice and a short reason: `remove`, `keep`, or `keep + issue`.

You answer `go`, or `go, but 2 keep`. Then each hack you keep gets an issue: a full ticket when the fix is clear, a seed when it is not. The comment gets the issue link, as in `// Safari drops the first event, see #42`. The useless comments are deleted. All of it goes in one PR that changes comments only, and the skill takes that PR to ready to merge. The last message has the PR link, the issue links, and the ready result.

It never changes code and never merges. When there is nothing to remove, it says so and opens no PR.

## Needs

- `gh`, signed in, and a GitHub repo, for the issues and the PR.
- Sub-agents: readers for the code, per the reader job in [facts.md](../../shared/facts.md).
- [to-issue](../to-issue/) and [capture](../capture/), to log the issues.
- [make-pr](../make-pr/) and [ready-pr](../ready-pr/), for the PR.

## Fits with

- Calls [to-issue](../to-issue/) for a clear hack and [capture](../capture/) for an unclear one, then [make-pr](../make-pr/), then follows [ready-pr](../ready-pr/).
- No other skill calls it; you start it yourself.
- [ship](../ship/) can fix a logged hack later: `/ship #42`.
