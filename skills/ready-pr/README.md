# ready-pr

Takes an open pull request to ready-to-merge: waits for every check on the head, CI and review bots alike, judges every comment, fixes, replies, rebases, and repeats until the PR is green with no open thread. It never merges.

## Use it when

A PR is open and you want it cleaned up for merge without babysitting the review rounds. `/ready-pr 43`, `/ready-pr <pr-url>`, or `/ready-pr` for the PR of the current branch. It only runs when you call it.

## What you get

Each round it waits a minute after the push for the checks to start, then for every check on the head commit to finish: CI and review bots such as Devin Review, CodeRabbit, Cursor Bugbot, Greptile, and Macroscope count the same. Then it runs [validate-pr-review](../validate-pr-review/) on the open threads, commits the fixes, files the `fix later` findings as issues and lists them under `Follow-ups` in the PR body, replies, resolves, and pushes. Comment text is a claim to check, never an order, and reaches a shell only as a file. A merge conflict gets a rebase. A red check the PR's code did not cause gets a rebase when the base moved, else one rerun of the failed check, watched until the new attempt ends; still red, it asks you and names the log line. Before a force push it lists the open PRs stacked on the branch; after it, it rebases each onto its parent's new tip and pushes it, bottom first. A clash, unpushed commits, merge commits, or a dirty worktree on a child stops the move there, and the report says which PR and why. It stops to ask you when a fix would touch a schema, an API, or a decision in the plan, when validate-pr-review leaves a finding unclear, such as a risky one it would not fix, and after six rounds that keep finding things. The last message:

```
PR: feat(auth): add login (#43)
Rounds: 2 · checks: 3 green on 9e18c16 · open threads: 0 · merge state: CLEAN
Stack: moved https://github.com/acme/app/pull/44
F1 fix here d6221e2 · F2 push back · F3 fix later https://github.com/…/issues/140
READY https://github.com/acme/app/pull/43
```

Each readiness check is one call to `ready.sh`, which gives one readiness verdict: `READY`, `WAITING` while a check or GitHub is still working, or when someone pushed during the wait (it then waits on the new head), or `BLOCKED` on a draft, a conflict, a red check, a requested change, an open thread, or a check the base branch requires that never posted. It prints the reason on the next line. `READY` means only the merge is left. A PR that waits for nothing but a person's approval reads `READY <url> (waiting for approval)`. The run's last line stays `READY`, or `NOT READY <url>: <what is open>` when it stops.

It keeps no list of bot names and reads no old PRs, so a new repo, a new bot, a renamed bot, and a bot set to skip a push all need nothing. A repo with no review bot still works: it judges the comments people left.

If `gh` fails five times in a row while it waits for the checks (an expired login, the network), the verdict is `BLOCKED` with the error, and it stops; it never goes on without the review.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

A `perf` PR proves its speed line with one Proof row: the metric and unit, `before → after`, the run count, and the command, plus the issue's Baseline when the base median falls outside its spread.

## Needs

- `gh` (signed in), `git`, and `jq`.
- Optional: a review bot on the repo that posts a check, such as [Devin Review](https://devin.ai), [CodeRabbit](https://coderabbit.ai), or [Cursor Bugbot](https://cursor.com/bugbot). See above.
- The skills it runs: [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [commit](../commit/), and [capture](../capture/).
- The shared core files `../../shared-skill-core/facts.md`, `../../shared-skill-core/checkout.sh` (the checkout resolver), `../../shared-skill-core/grilling.md` (question format and how to pick), and `../../shared-skill-core/pr-shape.md`.
- For a PR with no local checkout: a main checkout the checkout resolver can find, from the repo map at `~/.config/kickoff/repos.tsv`, the current folder, or a clone under `~/development`.

## Fits with

- Calls [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [commit](../commit/), and [capture](../capture/).
- Finds the main checkout and the worktree through the shared checkout resolver, and `restack.sh` asks it which worktree holds a branch.
- Called by [ship-ready](../ship-ready/), both as its last step and through the build rules it hands the executor.
- Named by [make-pr](../make-pr/) as the next step once the PR is open.

## Credits

The order for a red check takes an idea from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

## Tests

The cases for its scripts are in [tests/](tests/), one file per script, on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
