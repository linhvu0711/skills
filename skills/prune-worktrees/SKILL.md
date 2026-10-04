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
  hand. A worktree the script printed as `kept` goes only through
  `--remove` (step 3), and only when the user names it in this turn.
- **The main checkout is never touched.**
- **Relay, do not rewrite.** The script's lines are the reply.

## Steps

1. Run it from the session's folder, the repo to prune:

   ```bash
   bash scripts/prune-worktrees.sh
   ```

   `/prune-worktrees all`: add `all`. It also goes through every repo
   with a worktree under `${WORKTREES_ROOT:-~/development/worktrees}`,
   in `<owner>/<repo>/<branch>` folders or the older `<repo>/<branch>`.

2. Exit 0: reply with its stdout, verbatim, and nothing more.

   A `stop: gh failed: <why>` line: say that `gh` failed and why, name
   `gh auth status` to check the login, and stop. Nothing was removed.
   Do not run the script again without `gh`.

3. The user names a `kept` worktree to remove ("remove X", "remove the
   search one"): run the script with `--remove <path>`, one per worktree
   named, with the path from the `kept` line, and relay its lines. Its
   uncommitted files go with it; its branch goes only when git allows.
   Pass `--remove` only for a path the user named in this turn.

## Examples

**User:** `/prune-worktrees` after two PRs merged; a third PR is open.

```
kept ~/development/worktrees/acme/app/feat-7-search: PR #159 open
removed ~/development/worktrees/acme/app/feat-42-login, branch feat/42-login deleted (-D)
removed ~/development/worktrees/acme/app/fix-43-date, branch fix/43-date deleted (-D)
```

The reply is those three lines.

**User:** `remove the search one` after that reply.

`bash scripts/prune-worktrees.sh --remove ~/development/worktrees/acme/app/feat-7-search`
prints `removed ~/development/worktrees/acme/app/feat-7-search, branch
feat/7-search kept: git branch -d refused`. The reply is that line.
