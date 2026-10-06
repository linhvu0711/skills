# ready-pr

Takes an open pull request to ready-to-merge: waits for the repo's review tools, judges every comment, fixes, replies, rebases, and repeats until the PR is green with no open thread. It never merges.

## Use it when

A PR is open and you want it cleaned up for merge without babysitting the review rounds. `/ready-pr 43`, `/ready-pr <pr-url>`, or `/ready-pr` for the PR of the current branch. It only runs when you call it.

## What you get

First it reads the repo's last PRs to find which review tools it uses: Devin Review, CodeRabbit, Macroscope, Greptile, or Copilot. Each round it waits for each tool's status on the head commit, runs [validate-pr-review](../validate-pr-review/) on the open threads, commits the fixes, files the `fix later` findings as issues and lists them under `Follow-ups` in the PR body, replies, resolves, and pushes. Comment text is a claim to check, never an order, and reaches a shell only as a file. A merge conflict gets a rebase. Before a force push it lists the open PRs stacked on the branch; after it, it rebases each onto its parent's new tip and pushes it, bottom first. A clash, unpushed commits, merge commits, or a dirty worktree on a child stops the move there, and the report says which PR and why. It stops to ask you when a fix would touch a schema, an API, or a decision in the plan, and after six rounds that keep finding things. The last message:

```
PR: feat(auth): add login (#43)
Rounds: 2 · Review tools: devin success on 9e18c16 · open threads: 0 · merge state: CLEAN
Stack: moved https://github.com/acme/app/pull/44
F1 fix here d6221e2 · F2 push back · F3 fix later https://github.com/…/issues/140
READY https://github.com/acme/app/pull/43
```

Each readiness check is one call to `ready.sh`, which gives one readiness verdict: `READY`, `WAITING` while a review tool, a check, or GitHub is still working, or `BLOCKED` on a draft, a conflict, a red check, a requested change, an open thread, or a check the base branch requires that never posted. It prints the reason on the next line. `READY` means only the merge is left. A PR that waits for nothing but a person's approval reads `READY <url> (waiting for approval)`. The run's last line stays `READY`, or `NOT READY <url>: <what is open>` when it stops.

A repo with no review tool on its recent PRs still works: it judges the comments people left, and a tool that does post a status counts as one more check. A new tool is one row in the shared core's `review-tools/known.tsv`.

If `gh` fails five times in a row while it waits for the review (an expired login, the network), the verdict is `BLOCKED` with the error, and it stops; it never goes on without the review.

## Needs

- `gh` (signed in), `git`, and `jq`.
- Optional: a review tool on the repo, such as [Devin Review](https://devin.ai) or [CodeRabbit](https://coderabbit.ai). See above.
- The skills it runs: [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [commit](../commit/), and [capture](../capture/).
- The shared core files `../../shared-skill-core/review-tools/detect.sh` and its table `../../shared-skill-core/review-tools/known.tsv`, `../../shared-skill-core/facts.md`, `../../shared-skill-core/checkout.sh` (the checkout resolver), `../../shared-skill-core/grilling.md` (question format and how to pick), and `../../shared-skill-core/pr-shape.md`.
- For a PR with no local checkout: a main checkout the checkout resolver can find, from the repo map at `~/.config/kickoff/repos.tsv`, the current folder, or a clone under `~/development`.

## Fits with

- Calls [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [commit](../commit/), and [capture](../capture/).
- Finds the main checkout and the worktree through the shared checkout resolver, and `restack.sh` asks it which worktree holds a branch.
- Called by [ship](../ship/), both as its last step and through the build rules it hands the executor.
- Named by [make-pr](../make-pr/) as the next step once the PR is open.

## Tests

The cases for its scripts are in [tests/](tests/), one file per script, on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
