# land-pr

Takes an open pull request to ready-to-merge: waits for Devin Review, judges every comment, fixes, replies, rebases, and repeats until the PR is green with no open thread. It never merges.

## Use it when

A PR is open and you want it cleaned up for merge without babysitting the review rounds. `/land-pr 43`, `/land-pr <pr-url>`, or `/land-pr` for the PR of the current branch. It only runs when you call it.

## What you get

Each round it waits for the `Devin Review` status on the head commit, runs [validate-pr-review](../validate-pr-review/) on the open threads, commits the fixes, files the `fix later` findings as issues, replies, resolves, and pushes. A merge conflict gets a rebase. It stops to ask you when a fix would touch a schema, an API, or a decision in the plan, and after six rounds that keep finding things. The last message:

```
Landed: feat(auth): add login (#43)
Rounds: 2 · Devin Review: success on 9e18c16 · open threads: 0 · merge state: CLEAN
F1 fix here d6221e2 · F2 push back · F3 fix later https://github.com/…/issues/140
READY https://github.com/acme/app/pull/43
```

A repo without Devin Review still works: it says so once and judges the comments people left.

## Needs

- `gh` (signed in), `git`, and `jq`.
- [Devin Review](https://devin.ai) installed on the repo, for the review status. Optional, see above.
- The skills it runs: [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [make-commit](../make-commit/), and [capture](../capture/).
- The shared core files `../../shared-skill-core/facts.md`, `../../shared-skill-core/worktree.sh`, and `../../shared-skill-core/grilling.md`.
- For a PR with no local checkout: the repo map at `~/.config/kickoff/repos.tsv` or a clone under `~/development`, found the way [kickoff](../kickoff/) finds one.

## Fits with

- Calls [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [make-commit](../make-commit/), and [capture](../capture/).
- Finds a checkout the way [kickoff](../kickoff/)'s script does.
- Called by [ship](../ship/), both as its last step and through the build rules it hands the executor.
