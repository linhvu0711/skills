# make-pr

Opens a pull request for the work in your checkout, or updates the one already open, in the same shape as every PR these skills make.

## Use it when

You made a change by hand in a chat and want it up for review: "make a PR", "open a PR", or `/make-pr` (`$make-pr` in Codex). The agent also picks it up on its own from those words. For work that starts from an issue and should go all the way to ready-to-merge, use [ship](../ship/).

## What you get

From a dirty tree to an open PR in one run. It makes a branch when you are on `main`, commits with the [commit](../commit/) rules, runs the repo's own checks, pushes, and opens the PR ready for review. The branch, the title, the body, and the size label follow the shared [PR shape](../../shared-skill-core/pr-shape.md): `Closes #N` when an issue exists, `Summary`, `Where to look`, `Breaking changes` when something else must happen, `Proof`, and `Follow-ups`. A repo with its own PR template keeps that template's headings. When the branch already has an open PR, it uses that PR's base, pushes, and writes the title and body again for the whole branch, keeping the `Follow-ups` lines. It stops when files that are not part of this work are in the tree, when a check is red, and when the push is rejected. The last message:

```
PR: feat(export): write ISO dates (#61) · size S · checks: 2 green
https://github.com/acme/shop/pull/61
Next: /ready-pr
```

It never merges.

## Needs

- `gh`, signed in, and `git`.
- [commit](../commit/), for the commit messages.
- From the shared core: [pr-shape.md](../../shared-skill-core/pr-shape.md), [size.md](../../shared-skill-core/size.md), and [issue-rules.md](../../shared-skill-core/issue-rules.md) for the repo's size labels.
- `python3`, for the saved size-label map in [to-issue](../to-issue/)'s `scripts/conventions.py`.

## Fits with

- Hands off to [ready-pr](../ready-pr/), which takes the open PR to ready-to-merge.
- Called by [grill](../grill/) for its docs PR at the close-out.
- Named by [set-coding-standards](../set-coding-standards/) and [audit-coding-standards](../audit-coding-standards/) as the next step.
- Shares the PR shape with [ship](../ship/), [handoff-devin](../handoff-devin/), and [handoff-cursor](../handoff-cursor/), whose builders open their own PRs.
