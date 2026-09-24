---
name: land-pr
description: "Take an open PR to ready-to-merge: wait for Devin Review on the head commit, judge every finding with /validate-pr-review, fix, reply, resolve, rebase on a conflict, push, and repeat until the status is green with no open thread. Never merges."
disable-model-invocation: true
---

You own one PR until it is ready. Devin Review is the reviewer: a
commit status named `Devin Review` that turns pending after each push,
`success` a few minutes later, and posts a review only when it found
something. A push that fixes a thread gets its `✅ Resolved` reply and
the thread is closed by Devin itself. People's comments count the same
way; they only lack the status. Short lookups are yours; the judging is
`/validate-pr-review`'s, read and followed. Facts per
`~/.agents/skills/grill/references/facts.md`. Never merge.

`~/.agents/skills/land-pr/scripts/` holds four helpers; each prints its
usage with no arguments.
In Claude Code every Bash call starts in the session's directory: git
runs as `git -C "$WT" …`, and `gh` or a test as `cd "$WT" && …`.

## Forms

- `/land-pr <pr-url|number>`: that PR.
- `/land-pr`: the PR of the current branch.

## Steps

1. **Resolve.** `bash ~/.agents/skills/land-pr/scripts/pr-facts.sh <arg>` (no arg: the current
   branch's PR; add `--repo owner/repo` when the argument is a number
   and you are not in the repo). Hold every line. `STATE` is not `OPEN`:
   say so, stop. `FORK=true`: say `fork PRs are not mine`, stop.
   `me` is `gh api user -q .login`. Done when you hold `REPO`, `NUMBER`,
   `URL`, `BASE`, `HEAD`, `SHA`, and `me`.

2. **Checkout.** In a checkout already on `HEAD` with a clean tree:
   `WT` is that directory. Otherwise find the main checkout the way
   `~/.agents/skills/kickoff/scripts/kickoff.sh` does (the map at
   `~/.config/kickoff/repos.tsv`, then the current directory's origin,
   then a search under `~/development`; a `.git` directory, not a
   file), and:

   ```bash
   bash ~/.agents/shared-skill-core/worktree.sh <main-checkout> <HEAD>
   ```

   `stop:` on stderr: show it, stop. `WT` is its `WORKTREE=`. Done when
   `git -C "$WT" status --porcelain` is empty and
   `git -C "$WT" rev-parse HEAD` is `SHA`; behind it, `git -C "$WT" pull
   --ff-only` first.

3. **Wait.** Round `r` starts here, `r` from 1.

   ```bash
   bash ~/.agents/skills/land-pr/scripts/wait-review.sh <REPO> <SHA>
   ```

   Run it in the background in Claude Code; in Codex or a Devin CLI
   pane, in the foreground. Exit 0: go on. Exit 3 (no status in ten
   minutes): say `No Devin Review on this repo` once, set `no-devin`,
   go on. Exit 1: say the state and the PR URL, stop; the user decides.
   Exit 2 (pending for thirty minutes): say so, stop.

4. **Open?** `bash ~/.agents/skills/land-pr/scripts/open-threads.sh <REPO> <NUMBER> --me <me>`.
   `OPEN=0`: step 6. Else hold the lines.

5. **Judge and apply.** Read `~/.agents/skills/validate-pr-review/SKILL.md`.
   Follow its steps 1 to 6 with `NUMBER` as the argument, in `$WT`; then
   its § After go whole, `go` given, push included: the fixes, one
   commit each per `/make-commit`, `/capture` for every `fix later`,
   the replies by source, the resolves. No subagent tool here (Codex,
   a Devin CLI pane): each judge brief is yours, one after the other,
   same return shape, as validate-pr-review says for Codex. Three
   rules on top:
   - **Stop points.** A row under `## Unclear`: one question to the
     user per row, in the format of
     `~/.agents/skills/grill/references/grilling.md`, wait. A `fix here`
     whose change touches a seam, a Done-when line, a schema, an API,
     or a `Decided` line of the plan: ask before the fix, not after.
     In a Devin CLI pane, asking is `QUESTION` first, per the rules the
     pane holds.
   - **Seen before.** A finding with the same path and the same claim
     as one answered `push back` or `won't fix` earlier in this
     session: the same reply, with a link to the earlier thread, no new
     judge.
   - **Before the push.** `git -C "$WT" fetch origin <BASE>`. The push
     is rejected, or `MERGE_STATE` was `DIRTY`: `git -C "$WT" rebase
     origin/<BASE>`; a conflict is
     `~/.agents/skills/fix-conflicts/SKILL.md`, followed whole; then
     `git -C "$WT" push --force-with-lease`. Devin re-reviews the new
     head; old threads go `outdated` and stay resolved.

   After the push, `r` is `r + 1`. `r` past 6: say what keeps coming
   back and stop. Else `SHA` is the new head: step 3.

6. **Ready.**

   ```bash
   bash ~/.agents/skills/land-pr/scripts/ready.sh <REPO> <NUMBER> --me <me> [--no-devin]
   ```

   `READY`: step 7. `NOT READY`, by reason:
   - `merge state is DIRTY`: the rebase path of step 5, then step 3.
   - `check(s) red`: `cd "$WT" && gh pr checks <NUMBER>`, read the
     failing log. A cause inside the PR's own change is work: fix,
     commit, push, step 3. A cause outside it is a question to the
     user.
   - `check(s) pending`: wait for them, `cd "$WT" && gh pr checks
     <NUMBER> --watch`, then ready again.
   - `thread(s) wait for the author`: step 5.
   - `Devin Review is PENDING`: step 3.
   - anything else: say it, stop.

7. **Report.** Chat gets this and nothing more:

   ```
   Landed: feat(cli): add uninstall that reverses setup (#134)
   Rounds: 2 · Devin Review: success on 9e18c16 · open threads: 0 · merge state: CLEAN
   F1 fix here d6221e2 · F2 push back · F3 fix later https://github.com/…/issues/140
   Filed: https://github.com/…/issues/140
   Worktree: ~/development/worktrees/clocktrace/feat-133-uninstall
   READY https://github.com/linhvu0711/clocktrace/pull/134
   ```

   One line per finding over every round, id, verdict, SHA or URL.
   `Filed: none` when nothing was filed. A `no-devin` run says
   `Devin Review: none on this repo`. A stop point that ended the run
   prints the same block with `NOT READY <url>: <what is open>` last.

## Examples

**User:** `/land-pr 134` in the clocktrace checkout, on `feat/133-uninstall`.

Facts: open, not a fork, head `d6221e2`, `DEVIN=PENDING`. Tree clean on
the branch, so `WT` is here. `wait-review.sh` in the background returns
`DEVIN=success` after four minutes. `open-threads.sh`: `OPEN=1`, a 🟡
finding at `apps/cli/src/uninstall.ts:212`. Validate: one `fix here`,
`ours`, `should`. Fix, commit, fetch, push. Round 2: wait, success,
`OPEN=0`. Ready: `READY`. Report with the one finding and its SHA.

**User:** `/land-pr https://github.com/acme/shop/pull/61` in a chat with
no checkout.

Main checkout found under `~/development`; `worktree.sh` tracks
`origin/fix/57-export-date-iso` into
`~/development/worktrees/shop/fix-57-export-date-iso`. Then as above.

**Round 3** finds a thread whose fix means a new column on `users`.

A schema change: stop before the fix. One question to the user, `A`
add the migration in this PR, `B` `fix later` as its own ticket. Wait.

**`ready.sh`** says `merge state is DIRTY` after main moved.

Rebase on `origin/main`; two hunks conflict; fix-conflicts resolves them
and the suite is green; `push --force-with-lease`. Step 3 again on the
new head.

**`wait-review.sh`** exits 3 on a repo with no Devin app.

`No Devin Review on this repo`, `no-devin` set. Threads from people are
still judged; ready is checked with `--no-devin`. The report says
`Devin Review: none on this repo`.
