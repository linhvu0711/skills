# review-pr

Reviews a pull request on three separate checks (logic, scope, standards), one subagent each, with your repo's own review rules folded in.

## Use it when

You want a review before you merge. `/review-pr 42` reviews PR 42; `/review-pr` with no number reviews the PR of the current branch, or the branch against the default branch when there is no PR. It only runs when you call it.

## What you get

A report in chat and in `~/.claude/reviews/<repo>-<pr>.md`. Each finding has a severity (🔴 blocker, 🟠 should, 🔵 nit), a `path:line`, the rule it breaks, and a one-line fix. Scope is judged against the linked issue and its epic. It never posts to GitHub; the last line gives you the command to do it yourself:

```
Verdict: request changes. To post: gh pr review 42 --request-changes -F ~/.claude/reviews/acme-42.md
```

## Needs

- `git` and `gh`, signed in.
- An agent that can start subagents. In Codex, which has none, it runs the three checks one after the other.
- The shared core files `../../shared-skill-core/facts.md`, `../../shared-skill-core/review/general-rules.md`, and `../../shared-skill-core/review/rule-sources.md`.

## Fits with

- Reads the `REVIEW.md` that [set-review-rules](../set-review-rules/) writes. With no rules in the repo, the report suggests running it.
- Nothing calls this skill; you run it.

## Credits

Thanks to [mattpocock/skills](https://github.com/mattpocock/skills) for the `code-review` skill, which gave us the idea (MIT license). No text was copied.
