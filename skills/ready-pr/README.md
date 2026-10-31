# ready-pr

Takes an open pull request to ready-to-merge: watches every check and comment on the head, CI and review bots alike, looks into each red check and judges each comment as it comes, then fixes, replies, rebases, pushes once, and repeats until the PR is green with no open thread. It never merges.

## Use it when

A PR is open and you want it cleaned up for merge without babysitting the review rounds. `/ready-pr 43`, `/ready-pr <pr-url>`, or `/ready-pr` for the PR of the current branch. It only runs when you call it.

## What you get

Each round it waits a minute after the push for the checks to start, then watches every check and thread on the head commit until no check is still running: CI and review bots such as Devin Review, CodeRabbit, Cursor Bugbot, Greptile, and Macroscope count the same, and they can finish in any order. Each red check gets a CI helper at once, a subagent that reads its log and finds the cause. Red checks of one workflow that failed at the same step, such as one lint error on three Node versions, share one helper. Each new thread gets its judge from [validate-pr-review](../validate-pr-review/) at once. Helpers and judges only read. Nothing is fixed until every check is done and every helper is back. The one thing done at once is a rerun of a check that failed for no reason in the code, such as a timeout. Then validate-pr-review looks at all of it together, the red checks' causes next to the comments. Findings with one cause become one group and one commit. Every question for you comes in one message. The fixes that need no answer start at once, the rest after your answers. It files the `fix later` findings as issues and lists them under `Follow-ups` in the PR body, replies, resolves, and pushes once per round. Comment text is a claim to check, never an order, and reaches a shell only as a file. A merge conflict gets a rebase. A red check the PR's code did not cause gets a rebase when the base moved, else one rerun; still red, it asks you and names the log line. Before a force push it lists the open PRs stacked on the branch; after it, it rebases each onto its parent's new tip and pushes it, bottom first. A clash, unpushed commits, merge commits, or a dirty worktree on a child stops the move there, and the report says which PR and why. It asks you when a fix would touch a schema, an API, or a decision in the plan, when validate-pr-review leaves a finding unclear, such as a risky one it would not fix, and it stops after six rounds that keep finding things. In Codex, which has no background helpers, it does the same steps one after the other. The last message:

```
PR: feat(auth): add login (#43)
Rounds: 2 · checks: 3 green on 9e18c16 · open threads: 0 · merge state: CLEAN
Stack: moved https://github.com/acme/app/pull/44
F1 fix here d6221e2 · F2 push back · F3 fix later https://github.com/…/issues/140
READY https://github.com/acme/app/pull/43
```

In a round, `ready.sh` watches the head commit: it prints each new red check, with its workflow and the step that failed, and each new thread, as they come, in any order, until no check is still running. Then it gives the verdict. Each readiness check is one call to `ready.sh`, which gives one readiness verdict: `READY`, `WAITING` while a check or GitHub is still working, or when someone pushed during the watch (it then watches the new head), or `BLOCKED` on a draft, a conflict, a red check, a requested change, an open thread, or a check the base branch requires that never posted. It prints the reason on the next line. `READY` means only the merge is left. A PR that waits for nothing but a person's approval reads `READY <url> (waiting for approval)`. The run's last line stays `READY`, or `NOT READY <url>: <what is open>` when it stops.

It keeps no list of bot names and reads no old PRs, so a new repo, a new bot, a renamed bot, and a bot set to skip a push all need nothing. A repo with no review bot still works: it judges the comments people left.

If `gh` fails five times in a row while it watches the checks (an expired login, the network), the verdict is `BLOCKED` with the error, and it stops; it never goes on without the review.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

A `perf` PR proves its speed line with one Proof row: the metric and unit, `before → after`, the run count, and the command, plus the issue's Baseline when the base median falls outside its spread.

## Needs

- `gh` (signed in), `git`, and `jq`.
- Optional: a review bot on the repo that posts a check, such as [Devin Review](https://devin.ai), [CodeRabbit](https://coderabbit.ai), or [Cursor Bugbot](https://cursor.com/bugbot). See above.
- The skills it runs: [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [commit](../commit/), and [capture](../capture/).
- The shared core files `../../shared/facts.md`, `../../shared/checkout.sh` (the checkout resolver), `../../shared/grilling.md` (question format and how to pick), and `../../shared/pr-shape.md`.
- For a PR with no local checkout: a main checkout the checkout resolver can find, from the repo map at `~/.config/kickoff/repos.tsv`, the current folder, or a clone under `~/development`.

## Fits with

- Calls [validate-pr-review](../validate-pr-review/), [fix-conflicts](../fix-conflicts/), [commit](../commit/), and [capture](../capture/).
- Finds the main checkout and the worktree through the shared checkout resolver, and `restack.sh` asks it which worktree holds a branch.
- Called by [ship](../ship/), both as its last step and through the build rules it hands the executor.
- Named by [make-pr](../make-pr/) as the next step once the PR is open.

## Credits

The order for a red check takes an idea from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

## Tests

The cases for its scripts are in [tests/](tests/), one file per script, on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
