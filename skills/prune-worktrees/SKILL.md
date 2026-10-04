---
name: prune-worktrees
description: "Remove the git worktrees that are safe to prune (clean, PR merged at its last commit) with their branches, and list every other worktree with the reason it stays. Use when the user types /prune-worktrees in Claude Code or $prune-worktrees in Codex, or says 'prune worktrees', 'clean up worktrees', 'remove merged worktrees'. /ship's last line names it after a merge."
disable-model-invocation: true
---

# prune-worktrees

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

A worktree is **safe to prune** when it is clean, its PR is merged on
GitHub, and its branch tip is the PR's last commit. The script removes
those and their branches without asking, and lists every other worktree
with the reason it stays. The user decides about the rest.

## Hard rules

- **The script decides.** Never remove a worktree or delete a branch by
  hand, and never remove one the script printed as `kept`.
- **The main checkout is never touched.**
- **Relay, do not rewrite.** The script's lines are the reply.

## Steps

1. Run it from the session's folder, the repo to prune:

   ```bash
   bash scripts/prune-worktrees.sh
   ```

2. Exit 0: reply with its stdout, verbatim, and nothing more.

## Examples

**User:** `/prune-worktrees` after two PRs merged; a third PR is open.

```
kept ~/development/worktrees/app/feat-7-search: PR #159 open
removed ~/development/worktrees/app/feat-42-login, branch feat/42-login deleted (-D)
removed ~/development/worktrees/app/fix-43-date, branch fix/43-date deleted (-D)
```

The reply is those three lines.
