# prune-worktrees

Removes the git worktrees whose PRs are merged, with their branches, and lists every other worktree with the reason it stays.

## Use it when

A PR merged and its worktree is still on disk. Type `/prune-worktrees` in the repo (`$prune-worktrees` in Codex). `/prune-worktrees all` also goes through every repo with a worktree under `${WORKTREES_ROOT:-~/development/worktrees}`, in `<owner>/<repo>/<branch>` folders or the older `<repo>/<branch>`. [ship](../ship/) names it in its last line, `After merge: /prune-worktrees`. It only runs when you call it.

## What you get

It looks at every worktree of the repo, wherever it is on disk. A worktree is safe to prune when it is clean, its PR is merged on GitHub, and its branch tip is the PR's last commit. Those go without a question: the worktree with `git worktree remove`, the branch with `git branch -D`. A clean branch with no PR whose tip is in the default branch is safe too; its branch goes with `git branch -d`, and when git refuses, the branch stays and the report says so. A repo with no GitHub remote gets only that git test, and only `-d`. `-D` needs both proofs: the PR is merged, and the tip is its last commit. Every other worktree stays, listed with one reason: uncommitted files, an open PR, a PR closed without a merge, a merged PR whose tip moved after it, commits not on GitHub, no PR, a detached HEAD, or a lock. The worktree you run it from stays too, and the main checkout is never touched.

```
kept ~/development/worktrees/acme/app/feat-7-search: PR #159 open
removed ~/development/worktrees/acme/app/feat-42-login, branch feat/42-login deleted (-D)
```

To remove a kept worktree, name it: "remove X". Its uncommitted files go with it, and its branch goes only when git allows. Entries whose folder is gone are cleared with `git worktree prune`, and the report says how many. No worktree to prune: one line, `nothing to prune`.

## Needs

- `git`.
- `gh`, signed in, for the PR of each branch: one call per branch. When `gh` fails (not signed in, no network), it removes nothing and says so.

## Fits with

- [ship](../ship/) ends with `After merge: /prune-worktrees` for the worktree it built in.
- It removes what `../../shared-skill-core/worktree.sh` makes for [ship](../ship/) and [ready-pr](../ready-pr/).
- Nothing calls this skill; you run it.

## Tests

The cases for [prune-worktrees.sh](scripts/prune-worktrees.sh) are in [tests/prune-worktrees.sh](tests/prune-worktrees.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.

## Credits

The idea came from the worktree-cleanup playbook and `worktree-audit.sh` in pstack, in [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack). Idea only; none of the text.
