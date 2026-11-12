---
name: build-and-prove
description: "Build a /plan-up plan on this machine and prove it: Coding runs on the local machine, then, for a plan with UI walks, one proofbox Sandbox runs the Gates and the app, and a walker subagent films the walks like a test user. A plan with no UI starts no Sandbox: its Gates run on this machine and in the PR's CI. Ends at a branch with one commit per slice and a proof folder for /make-pr. Also runs a follow-up on a branch it built, a change or review fixes, and redoes only what the change touches. /ship runs it by default."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

One plan, one branch, at most one proofbox Sandbox, one proof folder. Facts come
from reading, per `../../shared/facts.md`. Big forks go to
the user; everything else you decide, write down, and go on. You never
push and never open a PR: `/make-pr` does that with the proof folder.

In Claude Code every Bash call starts in the session's directory. Every
git command in the worktree is `git -C "$WT" …`.

## Sandbox

Coding runs on the local machine: each slice's red and green test,
typecheck, and lint, in the worktree, with the repo's packages installed
there.

**No UI, no Sandbox.** A plan with `UI: none` starts no Sandbox and
needs no proofbox (ADR 0019). Steps 2, 4, 6, and 11 are skipped, step
8 runs the Gates and the perf measure per `references/checks.md`, and
no other `box.sh` call runs. The rest of this section is for a plan
with UI walks.

One run of a plan with walks has one proofbox Sandbox. It starts after Coding and runs
the Gates, the app, the before shots, and the walks (ADR 0011 in this
repo). A slice test that needs a tool the local machine lacks,
or a slice's e2e spec files, start it early, and the run keeps it. `scripts/box.sh` holds the Sandbox; it
prints its usage with no arguments.

- `box.sh up <proof-dir> <worktree> <linux|macos> <owner/repo>` creates
  it with an idle time of 30m on Linux and 10m on macOS, proofbox's
  default max life of 3h, and no `--provider`, so proofbox's own config
  picks the Provider. It shows every line proofbox prints as it makes
  the Sandbox, so a failed setup script's last lines come before the
  `stop:` line. It reads the setup script, the Secrets file `app.env`,
  which it passes as `--secrets`, and the optional size file from
  `~/.agents/proofbox/<owner>-<repo>/`. With a
  Sandbox already in `<proof-dir>`, it keeps that one and prints its id.
- `box.sh run <proof-dir> [--from <folder>] -- <command>…` uploads the
  worktree's changed files, or `<folder>`'s, runs the command, and exits
  with its code. A Sandbox that is gone, idle too long or past its max
  life, is made again once from its Snapshot, and `run` says so on
  stderr. Nothing is lost: the code lives in the worktree. A run can
  last longer than one Sandbox. It notes in `box.env` which tree the
  Sandbox holds: `BOX_TREE=base` after `--from`, else `BOX_TREE=branch`.
- `box.sh start <proof-dir> [--from <folder>] [--url <url>] -- '<Run line>'`
  uploads as `run` does and starts the app in its own process group,
  prints `TREE=base` or `TREE=branch`, and with `--url` waits up to
  120 s for it to answer (step 9a).
- `box.sh stop <proof-dir> [--url <url>]` ends the app's process group,
  waiting up to 30 s before it kills it, and with `--url` waits up to
  30 s for the port to be free (step 9a).
- `box.sh open <proof-dir> -- '<command>'` and `box.sh close
  <proof-dir>` are the walker's: they start its browser or terminal in
  its own process group and end that group, waiting up to 10 s before
  the kill. Neither uploads or makes a gone Sandbox again.
- `box.sh gates <proof-dir> [--local <worktree>] [--on-local
  '<command>']… [--not-run '<command>' '<why>']… -- '<command>'…` runs
  each command as `run` does, keeps each one's own exit code and full
  output in a temp file, and writes every line of
  `<proof-dir>/checks.txt` (step 8).
- `box.sh down <proof-dir>` deletes it and prints `REMADE=<n>`, how many
  times it was made again.

`stop:` on stderr is the reason to stop. Every stop after `up` runs
`down` first, so no Sandbox is left running; the worktree and its
commits stay.

**Sandbox fault.** A command in the Sandbox that prints `not found`
for a tool a setup script can install is the setup script's, not the
code's, whatever its exit code: a script can catch the 127 and exit 1,
as a check script that prints `stop: not inside a git repo` after
`git: command not found` does. Check the tool with `box.sh run
"$PROOF" -- sh -c 'command -v <tool>'`; exit 1 confirms it. A setup
script from an earlier run, one that writes no `$PROOFBOX_ENV`, fails
this way. Rewrite the script per step 4, `box.sh down`, `box.sh up`
(step 6), and run the command again. This holds wherever the command
ran: a slice test in a Sandbox Coding started early, a Gate, the app,
a walk. After three in one run: `box.sh down`, then stop with the last
one.

## Forms

- `/build-and-prove <plan.md>`: the plan of one ticket.
- `/build-and-prove <plan.md> --layer <n> --base <branch>`: layer `n` of
  a run's plan, its branch made from `<branch>`. `/ship` uses this form.
- `/build-and-prove <plan.md> [--layer <n> --base <branch>] follow-up
  <change>`: more work on the branch a build of this plan made
  (§ Follow-up). `/ship` uses it for a change and for review fixes.
- No plan named and none in this chat: say `Run /plan-up first.` and
  stop.

## Todo list

Before step 1, open a todo list with the todo tool your host gives:
TaskCreate and TaskUpdate, or TodoWrite, in Claude Code; `update_plan`
in Codex. No such tool: print the list in chat once, then one line as
each item starts, as `5. Coding.` It holds one item per step of
§ Steps, its number and bold title word for word, as in `5. Coding.`
Run by `/ship`, open no list of your own: ship's list already holds
these steps under its step 5, so mark those items.

Mark each item in progress as it starts and done as it ends. A step the
run does not do stays in the list as `<title> skip: <reason>`, as in
`7. Before shots. skip: no Before steps`. After the chat is compacted,
the list says where the run is: go on from the first item that is not
done.

## Steps

1. **Plan.** Read the plan `.md` whole: step 5 pastes its blocks into
   the builder's prompt. A run: read the blocks above the first
   `## Layer` heading, then this layer's, from `## Layer <n>` to the
   next `## Layer`; no other layer is held. Stop with one line on each
   of these:
   - no file at the path: `No plan at <path>.`
   - no `# Plan:` heading, or no `Repo:` line under `## Facts`: `<path>
     is not a /plan-up plan.`
   - a `## Stack` block and no `--layer`: `A run: /ship builds it
     layer by layer, or name --layer <n>.`
   - `Platform: windows`: `proofbox has no Windows. Use Devin: /ship
     <issue-url> devin?` and wait for the answer. A chat plan (no
     `#<n>` in its `# Plan:` line) has no issue for Devin: `proofbox has
     no Windows, and the cloud needs an issue. Run /to-issue first.`
     and stop.

   Hold `REPO` (the `Repo:` line), `BASE` (`--base`, else the `Base:`
   line), the issue number `N`, `UI` (the `UI:` line), the OS (`linux`,
   or `macos` for `macos-outpost`), `PERF` (the plan's `Perf` block, or
   none), and the layer's blocks: for a run, only the blocks under
   `## Layer <n>`, and `PERF` is the layer's. The slug is `<owner>-<repo>-<N>`.
   A chat plan (`../plan-up/references/plan.md` § Chat plan) has no
   `N`: its slug is the plan file's, `plan-<slug>.md`.
   `PROOF` is `$HOME/.agents/artifacts/proof/<slug>`. Make it.

2. **proofbox.** `UI: none`: mark it `2. proofbox. skip: no UI` and
   go to step 3. Else `command -v proofbox`. Missing: say `proofbox is not
   installed: https://github.com/linhvu0711/proofbox` and stop. Then
   the login, before any work:

   ```bash
   bash scripts/box.sh auth <os>
   ```

   - `stop: log in first: <command>`: show the command, copy it with
     `../../shared/copy.sh` (any other exit than 0: say
     `Clipboard copy skipped.`), and stop. Coding has not started.
   - Any other `stop:`: show it, stop.

3. **Worktree.** The branch follows the PR shape § Branch
   (`../../shared/pr-shape.md`): the issue's type, its
   number, two to four words, as in `fix/133-uninstall-reverses-setup`.
   A chat plan: the type from its title, then the words of its slug
   after `chat-`, as in `feat/export-orders-csv` for
   `acme-shop-chat-export-orders-csv`. The slug was picked so that no
   branch had this name, so an existing branch here is this plan's
   follow-up (§ Follow-up).

   ```bash
   bash ../../shared/checkout.sh <REPO> <branch> --base <BASE>
   ```

   `stop:` on stderr: show it, stop. Hold `WT` from the `WORKTREE=`
   line. The branch has commits ahead of `BASE` already: this is a
   follow-up (§ Follow-up), with no change when none was named.

4. **Setup files.** `UI: none`: mark it `4. Setup files. skip: no UI`
   and go to step 5. Else the folder is `~/.agents/proofbox/<owner>-<repo>/`,
   outside every repo, as proofbox wants (its ADR 0007).
   - No `setup-<os>.sh`: write it from what the repo shows: the runtime
     versions (`.nvmrc`, `.tool-versions`, `engines`, `packageManager`),
     the install command its lockfile calls for, the tools the plan's
     `Test`, `Lint`, `Build`, and `Run` lines need, and the tools the
     commands of its UI walks and videos use, and the browsers its e2e
     tests need. It runs once
     on proofbox's Base image, as a user with no sudo, before the work
     is built. `$HOME` is the Work folder, so the script keeps every
     tool, cache, and store outside it, in `/tmp/pb`. It puts them in
     reach of every later command by writing `NAME=value` lines to the
     file at `$PROOFBOX_ENV`, the Setup env: `PATH`, with its tool
     folders first (`echo "PATH=/tmp/pb/bin:$PATH" >> "$PROOFBOX_ENV"`),
     `LANG=C.UTF-8`, so a terminal's xterm draws `✔`, and any other
     setting its tools need. It writes no `env.sh`, and no command loads
     a file first. A name in `app.env` never goes in the Setup env:
     proofbox stops on it. Say `Setup: wrote <path>`.
   - The app needs settings (`.env.example`, the plan's `Run` line): no
     `app.env` yet, or one that lacks a name: write the names whose
     values the repo shows (a test port, a local URL), and an empty
     `NAME=` line for each secret. Then one message: the file's path
     and the names to fill in, never a value. Wait until the user says
     it is done. Never print the file.
   - `size`, optional, one line such as `8x16`: the Sandbox size for
     every run of this repo, which `box.sh` passes as `--size`, on `up`
     and on each remake. The skill never writes it; the user does, when
     proofbox's default (4x8 on Linux) is too slow.

5. **Coding.** Install the repo's packages in `$WT` on the local
   machine, with the install command its lockfile calls for (the one
   step 4 reads for the setup script); a repo with no lockfile installs
   nothing. The install fails because the local machine lacks its tool
   (`command not found`, exit 127): say `<tool> is not installed on this
   machine; install it and run again.` and stop. Coding has not started,
   and no Sandbox runs. With `UI: none` no Sandbox runs at all. Else
   no Sandbox runs yet: `proofbox list` shows none of this run
   until the last slice is committed, unless a slice test needed a tool
   the local machine lacks, or a slice ran its e2e spec files
   (§ Sandbox).

   Assemble the prompt per
   `bash ../../shared/handoff/render.sh local prompt`: the
   head lines with `Branch`, `Worktree`, and `Proof folder` (`PROOF`),
   the issue's `Task` and `Done when` verbatim (a chat plan: its
   `## Brief` block's), the plan's blocks, and
   the rules block from `render.sh local rules` pasted whole,
   unchanged, once. No `UI walks`, no `Videos`. On a follow-up, one line
   under `# Slices` first: `Slices 1 to <k> are committed; start at
   slice <k+1>.` (§ Follow-up). Check: every Proof row, every `file:line`, zero
   placeholders. Write it to
   `$HOME/.agents/artifacts/plan/prompt-<slug>.md`. Say
   `Prompt: <path> (<n> lines)`.

   You build. Read the prompt file and follow it whole as its
   builder, in `$WT`: slices in order, tests first, each
   slice's test, typecheck, and lint on the local machine, in `$WT`, and
   its e2e spec files in the Sandbox, one commit per slice. A slice test in the Sandbox that stops on a tool
   `not found` is a Sandbox fault (§ Sandbox): fix it and run the test
   again. With `UI: none`, there is no Sandbox, as the prompt's rules
   say: the e2e spec files are left to the PR's CI, and a slice test
   whose tool the local machine lacks stops and asks the user to
   install it. Say `Build:
   slice <k> of <n>` as each slice is committed. Its § Surprises are
   yours: stop and ask the user where it says stop and ask. It ends at
   `BUILT <branch>`.

6. **Sandbox up.** `UI: none`: mark it `6. Sandbox up. skip: no UI`
   and go to step 7. Else after Coding:

   ```bash
   bash scripts/box.sh up "$PROOF" "$WT" <os> <REPO>
   ```

   - `stop: log in first: <command>`: the login expired since step 2.
     Show the command, copy it with `../../shared/copy.sh` (any
     other exit than 0: say `Clipboard copy skipped.`), and stop.
   - A line that says the setup script failed: proofbox printed its
     last 50 lines above it. Fix the script and run `up` again; after
     three tries, stop with the last line.
   - Any other `stop:`: show it, stop.

   When Coding started one for a missing tool, `up` keeps it and prints
   the same id. Say `Sandbox: <id>`.

7. **Before shots.** Only when `UI` is not `none` and a walk's `Before`
   line names steps, and only for a walk with no `before-<walk>.png` in
   `PROOF` yet. Read `references/walks.md` whole first: this step uses
   its three sections, 9a to 9c, which are the whole file. The Sandbox must hold the base, since Coding has
   committed: add a detached worktree of `BASE` in a temp
   folder. Every start of the app in this step, the first and each one
   again below, is `box.sh start "$PROOF" --from <that folder> …`
   (step 9a), so the base is what runs; each prints `TREE=base`, and a
   `TREE=branch` is a start without `--from`: stop the app and start it
   again with it. Start the app, send the walker in `before` mode and
   round 1 (step 9b),
   and stop the app (step 9a, Stop the app) unless the walker ended with `GONE <id>`. On `GONE`,
   start the app again from the same temp worktree and send the walker
   once more, round 2, as step 9c says. Each `FAIL` line in the
   `BEFORE` report is sorted by step 9c, and its `before-<walk>.png`
   is deleted, so no failed shot stays in `PROOF`:
   - A Sandbox fault: fix the setup script, `box.sh down`, and start
     again from step 6.
   - Any other `FAIL`: the `Before` line's steps do not reach the screen
     it names on the base, a Wrong walk. Fix the line in the plan `.md`,
     add a `Decided` line, start the app again from the same temp
     worktree (step 9a), send the walker again for that walk, and stop
     the app (step 9a). A second `FAIL` for it: `box.sh down`, then stop with that line.

   Remove the temp worktree only when this step ends, with the shots
   or with a stop. The next `start`, `run`, or `gates` without
   `--from` puts the branch back, and `box.env` notes it. Say
   `Before shots: <n>`.

8. **Gates.** `UI: none`: read `references/checks.md` whole, since
   its four sections are one pass: run the Gates and the perf measure
   per that file, then go to step 9. The rest of this step is for a
   plan with walks.

   Yourself, once, on the head commit: the full suite,
   typecheck, lint, and build under `Facts`, and every command the
   repo's `AGENTS.md` or `CLAUDE.md` names as a check, all in one call,
   each command in single quotes, a `none` line left out:

   ```bash
   bash scripts/box.sh gates "$PROOF" -- '<Test>' '<Typecheck>' '<Lint>' '<Build>' '<check>'
   ```

   It runs each one in the Sandbox and writes `$PROOF/checks.txt` fresh,
   one line per command: the command, the short SHA, the last line of
   its output, and where it ran, as in `pnpm test · 1a2b3c4 · 116 pass,
   0 fail (sandbox)`. Write no Sandbox line by hand. `/make-pr` counts
   these lines and runs none of them again. Exit 3 means a red Gate:
   stderr has `red: <command> · exit <code> · output <file>` for each.
   A red Gate is the builder's: a follow-up per `render.sh local
   prompt` § Follow-up, `# Check` naming the Gate and its output file,
   so the builder reads the output and does not run the Gate again.
   Then the `gates` call again, which writes the file fresh. Exit 1 is
   a stop, with `stop:` on stderr: show it, `box.sh down`, stop.

   A Gate that prints `not found` gets a `missing tool:` line on
   stderr. It sorts in this order. First, a tool no
   setup script can make work in the Sandbox, such as `docker`, which
   needs a daemon and root: the Gate runs on the local machine, below.
   Any other tool, such as one the `Test`, `Lint`, or `Build` line
   names, is a Sandbox fault (§ Sandbox), whatever its exit code: fix
   it, then the Gates again.

   A Gate the Sandbox cannot run in any case, such as `pnpm test:docker`
   with no Docker in the Sandbox (`docker: command not found`, or its
   output names a service the Sandbox lacks): run `gates` again with it
   as `--on-local '<command>'` in place of its place after `--`.
   `box.sh` runs it on the local machine in the worktree, and its line
   ends `(local machine)`. A Gate that can run in neither place goes in
   as `--not-run '<command>' '<why>'`, and its line is `<command> ·
   <short SHA> · not run: <why>`. Pass both options on every later
   `gates` call: each call writes every line of `checks.txt`.

   With a `PERF` block, after the Gates, measure per
   `../../shared/benchmark.md`. Add a detached worktree of
   `BASE` in a temp folder, as step 7 does. Run the block's `Command` in
   turns, `box.sh run "$PROOF" --from <that folder> -- <Command>` then
   `box.sh run "$PROOF" -- <Command>`, as many times each as the `Pass
   rule` says. Write one line to `checks.txt`: `<Command> · <short SHA>
   · <metric>: <base median> → <head median> <unit>, median of <n> in
   turns, spread <low> to <high> (sandbox)`. A base median outside the
   `Before` spread adds ` (issue Baseline: <Before>)` before
   `(sandbox)`, per `../../shared/pr-shape.md` § Proof. A
   head that misses the `Pass rule` is a red Gate: a follow-up, as
   above. Remove the temp worktree.

9. **Walks.** `UI: none`: no walker; say `Walks: none (no UI)` and go
   to step 10. Else read `references/walks.md` whole and follow it,
   since each round runs all three of its sections: rounds, at most
   three, each 9a start the app, 9b walker and video check, 9c sort.

10. **Proof folder.** Write `$PROOF/proof.md`: the `## Proof` part per
   `../../shared/pr-shape.md` § Proof, one row per Done-when
   line from the plan's Proof table, the test case by name, and for a
   plan with walks the `Screenshot` and `Video` columns and the
   Screenshots and Videos parts, each image and video as `./<file>` in
   `PROOF`, each video's line with its commit from `videos.txt`. A row proved by a command carries the command, the short
   SHA, and the result from `checks.txt`. The Target line's row of a
   plan with a `PERF` block carries the perf line from `checks.txt`, per
   `../../shared/pr-shape.md` § Proof. A `not run` line from
   `checks.txt`, `not run: CI runs it` too, goes in as its command,
   `not run: <why>`, and the words `CI must prove it`.

11. **Down.** `UI: none`: mark it `11. Down. skip: no UI`. Else
    `bash scripts/box.sh down "$PROOF"`. Hold its `REMADE`
    count for the report.

12. **Report.** Chat gets this and nothing more:

    ```
    Built: #42 Export orders as CSV · feat/42-export-orders-csv · 4 commits
    Checks: pnpm test, pnpm lint, pnpm build green on 1a2b3c4 in the Sandbox
    Walks: 3 passed in round 2 · videos: 2 · built by: session
    Walk notes:
    - after round 1 · walk 2: FAIL · step 3: no `Save` button; the screen shows `Save changes` · fail-2.png · video 1 @ step 3
    - walk 1: not checked: no console errors
    - W2 See changed after round 1: "Saved" → "Changes saved". The toast text is the app's
    Sandbox: made again 1 time
    Proof: ~/.agents/artifacts/proof/acme-shop-42
    BUILT feat/42-export-orders-csv
    ```

    The `Walk notes:` block copies, word for word: each `FAIL` line of
    every `walk-report-before-<r>.md` and `walk-report-after-<r>.md` in
    `PROOF`, with its mode and round in front; each `not checked:` part
    of a walk's line, once per walk; and each `Decided` line this run
    added in the `W<w> ... changed after round <r>` shape
    (`references/walks.md` § 9c. Sort). None of them: no notes block, and the
    `Walks:` line says the walks passed, as above.

    The `Checks:` line names each Gate once: the green ones with where
    they ran, then the ones left to CI, as in `Checks: pnpm lint green
    on 1a2b3c4 on the local machine · pnpm test: CI`. `UI: none`:
    `Walks: none (no UI)` and no `Sandbox:` line. `REMADE=0`: no
    `Sandbox:` line.
    A chat plan: the first line has no `#<n>`, as in
    `Built: [feat] Export orders as CSV · feat/export-orders-csv`. The
    worktree is `WT`, and the branch is not pushed: `/make-pr` with the proof folder is next.

## Follow-up

More work on the branch a build of this plan made. The change is named
any way: the user's words, as `the button says Export CSV`, or `review
fixes are committed` when the fixes are already in commits. A rerun
after a stop is a follow-up with no change, and so is the plain form
on a branch with commits ahead of `BASE` (step 3).

It runs steps 1 to 12 with the rules below. What is done is read from
disk: the commits ahead of `BASE`, the before shots in `PROOF`,
`videos.txt` with each video's commit, `checks.txt`, and `box.env`. It
writes the branch's commits and `PROOF`, nothing else: `/make-pr`
updates the PR from `PROOF`.

- **The change.** Sort it first by the two tests of
  `../plan-up/SKILL.md` step 5; a big fork goes to the user, and the
  follow-up waits. A change that adds or changes a Proof row, a slice,
  a walk, or a video goes into the plan `.md` first, with a `Decided`
  line that says so, as a Wrong walk fix does (`references/walks.md`
  § 9c. Sort).
- **Step 3.** `checkout.sh` hands back the same worktree, only when it
  is clean: a slice or a fix cut off before its commit leaves changes,
  and step 3 stops on them with the files named. The user commits or
  drops them, then runs again.
- **Step 5.** The commits ahead of `BASE` are the first slices, one
  commit each, in order: `git -C "$WT" rev-list --count <BASE>..HEAD`
  is the number done, and the prompt starts at the next one. A count at
  or past the number of slices means every slice is in. The change
  comes after the last slice, as one more part shaped by `render.sh
  local prompt` § Follow-up, with its own commits, so the count holds
  on the next follow-up. No slice left and nothing to build, as with
  `review fixes are committed`: no builder.
- **Sandbox.** A plan with walks only. `box.sh up` (step 6) runs at the
  first step that needs the Sandbox, and only then: a slice test that
  runs there, as step 5 says (a tool the local machine lacks, the
  slice's e2e spec files), a before shot to take, a Gate or the perf
  measure that runs there, a video to film. None of them: no `up`, and
  step 11 is skipped.
- **Step 7.** Only the walks with no `before-<walk>.png` in `PROOF`.
- **Step 8.** Every Gate line of `checks.txt` names HEAD's short SHA
  and none is red: the Gates stand, and no `gates` call runs. The perf
  line is not a Gate line: it keeps the SHA it was measured on. Else, with no open
  PR, step 8 as written. The PR is open when `gh pr list -R <REPO>
  --head <branch> --state open --json url -q '.[0].url'` prints a URL;
  then only the Gates CI does not run run here. `UI: none`: step 8 as
  written, since `gates --local` already asks. A plan with walks asks
  `bash ../../shared/ci-covers.sh "$WT" -- '<Gate>'…`. No `here` Gate
  left for the Sandbox, each one `ci` or one the build ran as
  `--on-local`: `box.sh gates "$PROOF" --local "$WT"` with every Gate
  after `--`, which writes each one's `not run: CI runs it` line, runs
  the rest on the local machine, and needs no Sandbox. Else the Sandbox
  `gates` call with the other `here` Gates after `--`, each `ci <file>`
  Gate as `--not-run '<Gate>' 'CI runs it (<file>)'`, and the build's
  `--on-local` and `--not-run` Gates passed as before.
  With a `PERF` block, the measure runs again only when `git -C "$WT"
  diff --name-only <its line's SHA> HEAD` names a file its `Command`
  runs. Else copy its line out of `checks.txt` before the `gates` call
  and add it back after, since `gates` writes the file fresh.
- **Step 9.** Films only the videos `references/walks.md` § 9c. Sort
  names; every other video keeps its files and its passes. None: no
  walker.
- **Steps 10 to 12.** As written: `proof.md` again from `checks.txt`
  and `videos.txt`, `box.sh down` only after an `up` of this follow-up,
  and the report.
- **Todo list.** Run by `/ship` after its step 5 is done, open no list:
  say one line as each step starts, as `Follow-up: 8. Gates.`

## Examples

Sample runs, a login stop, and a wrong walk: `references/examples.md`.
Read it when a step here is unclear.
