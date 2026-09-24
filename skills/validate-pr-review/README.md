# validate-pr-review

Checks every finding in a pull request review before you act on it: is it true, did this PR cause it, and is it worth fixing.

## Use it when

A review came in, from a person, a bot, or a pasted Slack message, and you want to know which comments to fix, which to file for later, and which to push back on. `/validate-pr-review 42`, `/validate-pr-review <pr-url>`, or `/validate-pr-review` followed by the pasted text. With no argument it takes the PR of the current branch. It only runs when you call it.

## What you get

A table in chat and in `~/.claude/reviews/<repo>-<pr>-validation.md`. Each finding gets one verdict (`fix here`, `fix later`, `won't fix`, or `push back`), the fact that settles it, and a reply written as the PR author. "Did this PR cause it" is decided by `git blame` against the base, not by what the reviewer said. Then it stops and waits:

```
Say go to apply: 3 fix here, 2 fix later, 8 replies to post.
```

After you say go, it makes the fixes, files each `fix later` as an issue, posts the replies where each comment came from, and resolves the threads it fixed. "go, fixes only" does just that part.

## Needs

- `git` and `gh`, signed in (it reads review comments with `gh api` and resolves threads with `gh api graphql`).
- An agent that can start subagents, one judge per group of files. In Codex it runs them one after the other.
- The [make-commit](../make-commit/) skill for the fixes and the [capture](../capture/) skill for the `fix later` issues.
- The shared core file `../../shared-skill-core/facts.md`.

## Fits with

- Calls [make-commit](../make-commit/) and [capture](../capture/) after go.
- Called by [land-pr](../land-pr/), which runs it on every review round.
- [handoff-devin](../handoff-devin/) and [handoff-cursor](../handoff-cursor/) sort a cloud agent's review questions with the same verdict table.
