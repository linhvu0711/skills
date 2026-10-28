# ship-full

Does the same run as [ship-ready](../ship-ready/), then merges each pull request once it is ready, and removes the merged worktrees. Plan it, build it, make it ready, merge it, in one run.

## Use it when

You have a ready issue and want it all the way to merged, with no stop for you at the end. It takes the same arguments as [ship-ready](../ship-ready/):

- `/ship-full <issue-url>`: one ticket, one PR, merged.
- `/ship-full <epic-url> #12 #14`, `/ship-full <issue-url> #14 #15`, `/ship-full <epic-url>`: a stack of PRs, merged bottom first.
- `/ship-full <issue-url> on <pr-url>`: a new layer on an open stack. It is made ready but not merged, since the PR under it is not this run's.
- Any of the above with `devin` or `cursor` at the end: built in the cloud, then merged.
- `/ship-full` with no URL: the plan or the work this chat holds, as for ship-ready.

Typing `/ship-full` is your go-ahead to merge. Use [ship-ready](../ship-ready/) when you want to merge yourself. It only runs when you call it.

## What you get

Everything [ship-ready](../ship-ready/) gives, then the merge:

- A PR is merged only when its ready step says `READY` with no wait for a person's approval. A PR that is not ready, or waits for an approval, stays open, and so do the PRs above it.
- It merges only at the head commit that the ready step checked. If someone pushed after that check, GitHub refuses the merge and the run stops.
- The method is a merge commit when the repo allows it, else squash, else rebase. A merge commit keeps one commit per slice, and the next PR in a stack needs no rebase.
- In a stack, after a PR merges, the next one points at the base branch, is rebased when the method was squash or rebase, and is made ready again before its merge.
- It never uses `--admin`, auto-merge, or a merge queue, and never pushes to the base branch. The repo's branch rules stay in force.
- After the last merge, [prune-worktrees](../prune-worktrees/) removes the worktrees whose PR merged, with their branches.

The last message is ship-ready's, with the merge in place of the ready line:

```
Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
Route: local · built by: claude pane w4:p9M · walks: 3 in round 2 · review rounds: 2 · Filed: none
Worktree: ~/development/worktrees/acme/app/feat-42-login
removed ~/development/worktrees/acme/app/feat-42-login (1.2G), branch feat/42-login deleted (-D)
MERGED https://github.com/acme/app/pull/43 merge 4f2a1b0
```

A PR it did not merge ends `NOT MERGED <url>: <why>`.

## Needs

- Everything [ship-ready](../ship-ready/) needs.
- `gh` signed in as someone who may merge in the repo, and `jq`.
- [prune-worktrees](../prune-worktrees/) and [fix-conflicts](../fix-conflicts/), and [ready-pr](../ready-pr/) for a stack.

## Fits with

- Follows [ship-ready](../ship-ready/) whole and adds only the merge.
- Runs [ready-pr](../ready-pr/) again on each PR of a stack after the one below it merges, and [prune-worktrees](../prune-worktrees/) at the end.
- [kickoff-herdr](../kickoff-herdr/) starts it in a new pane when you say "ship and merge".

## Credits

The split into one skill that stops at a ready PR and one that merges takes the idea of `full-stop` and `full-send` from [tstack](https://github.com/t3dotgg/tstack) by Theo Browne (MIT). No text was copied.

## Tests

The cases for its script are in [tests/](tests/), one file per script, on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
