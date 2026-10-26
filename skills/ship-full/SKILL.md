---
name: ship-full
description: "The run of /ship-ready, then the merge: take any target (one issue, a run of epic tickets, a set, a whole epic, or a new layer on a stack) from plan to merged PRs in one run. Same arguments as /ship-ready. Each PR is merged only when its ready step printed READY with no wait for a person's approval, at the head that step checked, bottom of a stack first; then /prune-worktrees removes the merged worktrees. Typing /ship-full is the go-ahead to merge."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Read `../ship-ready/SKILL.md` and follow it whole: its forms, its steps
1 to 7, its § No URL, and its other two rules under § Never. Every
`/ship-ready` in it names this command too. The parts below win over
it. The user typed `/ship-full`: that is the go-ahead to merge the PRs
this run makes ready, and nothing more.

## Never

Ship-ready's first rule, never merge, is replaced by this one:

- Merge only a PR this run opened, or that the cloud executor opened
  for this run, only after its ready step printed `READY <url>` with no
  `(waiting for approval)`, and only by `scripts/merge.sh` with the head
  SHA that step checked. Never `gh pr merge --admin`, auto-merge, a
  merge queue, a push to the base branch, or any bypass of a branch
  rule.

## Todo list

Ship-ready's items, with its step 7 left out, then `7. Merge.` and
`8. Report.`

## Steps

Ship-ready's steps 1 to 6 run as written. Its step 7, Report, is
step 8 here.

7. **Merge.** Each PR, bottom of the stack first. Hold `Base`, the
   plan's `Base`, and for each PR its `REPO`, `NUMBER`, `WT`, and the
   `SHA` its ready step checked.

   - Its last line is not `READY <url>`, or it ends `(waiting for
     approval)`: merge neither it nor the PRs above it. Its report line
     is `NOT MERGED <url>: <its NOT READY reason, or waits for
     approval>`; each PR above it is `NOT MERGED <url>: waits on <url>`.
   - Its base is a PR this run did not open (the `on <pr-url>` form):
     `NOT MERGED <url>: its base PR #<n> is not this run's`, and the
     same for each PR above it.
   - Else:

     ```bash
     bash scripts/merge.sh <REPO> <NUMBER> --sha <SHA>
     ```

     `stop:` on stderr: show it; this PR is `NOT MERGED <url>: <the
     stop line>`, and each PR above it waits on it. Exit 0: hold its
     `MERGED` line for the report.

   After a merge, the next PR up was stacked on the merged branch. `OLD`
   is that branch's tip, `git -C "$WT" rev-parse origin/<merged head>`.
   Point the PR at the base: `cd "$WT" && gh pr edit <next NUMBER>
   --base <Base>`. The method in the `MERGED` line was `squash` or
   `rebase`: the next PR's commits hold the old ones of the PR below,
   so in the next PR's worktree `git -C "$WT" fetch origin <Base>`,
   `git -C "$WT" rebase --onto origin/<Base> <OLD>`, a conflict is
   `../fix-conflicts/SKILL.md` followed whole, then `git -C "$WT" push
   --force-with-lease`. A `merge` method needs no rebase. Then read
   `../ready-pr/SKILL.md` and follow it whole on that PR, since its base
   changed, and merge it as above when it prints `READY`.

   After the last merge, from the session's folder:

   ```bash
   bash ../prune-worktrees/scripts/prune-worktrees.sh
   ```

   It removes each worktree whose PR merged at its last commit, with its
   branch, and keeps the rest with the reason. `stop:` on stderr: show
   it; nothing was removed, and the merges stand. Hold its lines.

8. **Report.** Ship-ready's step 7 block, with three changes:
   - the `READY` line is the `MERGED` line `merge.sh` printed;
   - the `After merge: /prune-worktrees` line is the lines
     `prune-worktrees.sh` printed;
   - a PR that was not merged ends `NOT MERGED <url>: <why>`. Nothing
     was merged: no prune lines, and the last line of each block is its
     `NOT MERGED` line.

## Examples

**User:** `/ship-full https://github.com/acme/shop/issues/57`; #57 is a
`[fix]`, size S, no screen.

Ship-ready's steps 1 to 6: plan, `Route: local (no UI)`, build, PR 61,
ready. `READY https://github.com/acme/shop/pull/61` at `9e18c16`.
`merge.sh acme/shop 61 --sha 9e18c16…` prints `MERGED
https://github.com/acme/shop/pull/61 merge 4f2a1b0`. `prune-worktrees.sh`
prints `removed ~/development/worktrees/acme/shop/fix-57-export-date-iso
(96M), branch fix/57-export-date-iso deleted (-D)`. Report.

**User:** `/ship-full https://github.com/acme/shop/issues/70 #71 #73`;
the repo allows only squash.

`Route: local (stack of 2)`. PR 72 on `main`, PR 74 on
`feat/71-team-entity`, both `READY`. `merge.sh` on 72 prints `MERGED …
squash 7c1d2e3`. PR 74 goes to `main` by `gh pr edit 74 --base main`,
is rebased with `--onto origin/main <OLD>`, pushed, and readied again;
`READY`, then `MERGED … squash 8d2e3f4`. Prune. Two report blocks.

**User:** `/ship-full https://github.com/acme/shop/issues/42`; ready-pr
ends `READY https://github.com/acme/shop/pull/43 (waiting for approval)`.

No merge: a person's approval is the user's. Report ends `NOT MERGED
https://github.com/acme/shop/pull/43: waits for approval`. No prune.
