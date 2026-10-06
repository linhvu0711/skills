---
name: build-and-prove
description: "Build a /plan-up plan on this machine and prove it with proofbox: the Mac edits and commits, one proofbox Sandbox runs every test, the build, and the app, and a walker subagent films the UI walks like a test user. Ends at a branch with one commit per slice and a proof folder for /make-pr. /ship runs it by default."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

One plan, one branch, one proofbox Sandbox, one proof folder. Facts come
from reading, per `../../shared-skill-core/facts.md`. Big forks go to
the user; everything else you decide, write down, and go on. You never
push and never open a PR: `/make-pr` does that with the proof folder.

In Claude Code every Bash call starts in the session's directory. Every
git command in the worktree is `git -C "$WT" …`.

## Sandbox

One run has one proofbox Sandbox, and every command that runs the
project's code runs there: each slice's red and green test, typecheck,
lint, the full suite, the build, an install, and the app. The Mac only
edits files, runs git, and calls proofbox (ADR 0009 in this repo).
`scripts/box.sh` holds the Sandbox; it prints its usage with no
arguments.

- `box.sh up <proof-dir> <worktree> <linux|macos> <owner/repo>` creates
  it with an idle time of 30m on Linux and 10m on macOS, proofbox's
  default max life of 3h, and no `--provider`, so proofbox's own config
  picks the Provider. It reads the setup script and env file
  from `~/.agents/proofbox/<owner>-<repo>/`.
- `box.sh run <proof-dir> [--from <folder>] -- <command>…` uploads the
  worktree's changed files, or `<folder>`'s, runs the command, and exits
  with its code. A Sandbox that is gone, idle too long or past its max
  life, is made again once from its Snapshot, and `run` says so on
  stderr. Nothing is lost: the code lives in the worktree. A run can
  last longer than one Sandbox.
- `box.sh down <proof-dir>` deletes it and prints `REMADE=<n>`, how many
  times it was made again.

`stop:` on stderr is the reason to stop. Every stop after `up` runs
`down` first, so no Sandbox is left running; the worktree and its
commits stay.

## Forms

- `/build-and-prove <plan.md>`: the plan of one ticket.
- `/build-and-prove <plan.md> --layer <n> --base <branch>`: layer `n` of
  a run's plan, its branch made from `<branch>`. `/ship` uses this form.
- `/build-and-prove <note>`: an answer or follow-up for the pane this
  chat started (§ Follow-up).
- No plan named and none in this chat: say `Run /plan-up first.` and
  stop.

## Steps

1. **Plan.** Read the plan `.md` whole. Stop with one line on each of
   these:
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
   or `macos` for `macos-outpost`), and the layer's blocks: for a run,
   only the blocks under `## Layer <n>`. The slug is `<owner>-<repo>-<N>`.
   A chat plan (`../plan-up/references/plan.md` § Chat plan) has no
   `N`: its slug is the plan file's, `plan-<slug>.md`.
   `PROOF` is `$HOME/.agents/artifacts/proof/<slug>`. Make it.

2. **proofbox.** `command -v proofbox`. Missing: say `proofbox is not
   installed: https://github.com/linhvu0711/proofbox` and stop.

3. **Worktree.** The branch follows the PR shape § Branch
   (`../../shared-skill-core/pr-shape.md`): the issue's type, its
   number, two to four words, as in `fix/133-uninstall-reverses-setup`.
   A chat plan: the type from its title, then the words of its slug
   after `chat-`, as in `feat/export-orders-csv` for
   `acme-shop-chat-export-orders-csv`. The slug was picked so that no
   branch had this name, so an existing branch here is this plan's
   rerun.

   ```bash
   bash ../../shared-skill-core/checkout.sh <REPO> <branch> --base <BASE>
   ```

   `stop:` on stderr: show it, stop. Hold `WT` from the `WORKTREE=`
   line. The branch has commits ahead of `BASE` already: this is a
   rerun (§ Rerun).

4. **Setup files.** The folder is `~/.agents/proofbox/<owner>-<repo>/`,
   outside every repo, as proofbox wants (its ADR 0007).
   - No `setup-<os>.sh`: write it from what the repo shows: the runtime
     versions (`.nvmrc`, `.tool-versions`, `engines`, `packageManager`),
     the install command its lockfile calls for, and the tools the
     plan's `Test`, `Lint`, `Build`, and `Run` lines need. It runs once
     on proofbox's Base image, as a user with no sudo, before the work
     is built. Say `Setup: wrote <path>`.
   - The app needs settings (`.env.example`, the plan's `Run` line): no
     `app.env` yet, or one that lacks a name: write the names whose
     values the repo shows (a test port, a local URL), and an empty
     `NAME=` line for each secret. Then one message: the file's path
     and the names to fill in, never a value. Wait until the user says
     it is done. Never print the file.

5. **Sandbox up.**

   ```bash
   bash scripts/box.sh up "$PROOF" "$WT" <os> <REPO>
   ```

   - `stop: log in first: <command>`: show the command, copy it with
     `pbcopy` when there is one, and stop.
   - A line that says the setup script failed: proofbox printed its
     last 50 lines above it. Fix the script and run `up` again; after
     three tries, stop with the last line.
   - Any other `stop:`: show it, stop.

   Say `Sandbox: <id>`.

6. **Before shots.** Only when `UI` is not `none` and a walk's `Before`
   line names steps, and only for a walk with no `before-<walk>.png` in
   `PROOF` yet. The Sandbox must hold the base, even on a rerun whose
   worktree has commits: add a detached worktree of `BASE` in a temp
   folder, and run every command of this step as `box.sh run "$PROOF"
   --from <that folder> -- …`, so the base is what runs. Start the app
   (step 8a), send the walker in `before` mode (step 8b), and stop the
   app unless the walker ended with `GONE <id>`. On `GONE`, start the
   app again from the same temp worktree and send the walker once more,
   as step 8c says. Remove the temp worktree only when this step ends,
   with the shots or with a stop. The next `box.sh run` without
   `--from` puts the branch back. Say `Before shots: <n>`.

7. **Build.** Assemble the prompt per
   `bash ../../shared-skill-core/handoff/render.sh local prompt`: the
   head lines with `Branch`, `Worktree`, and `Proof folder` (`PROOF`),
   the issue's `Task` and `Done when` verbatim (a chat plan: its
   `## Brief` block's), the plan's blocks, and
   the rules block from `render.sh local rules` pasted whole,
   unchanged, once. No `UI walks`, no `Videos`. On a rerun, one line
   under `# Slices` first: `Slices 1 to <k> are committed; start at
   slice <k+1>.` Check: every Proof row, every `file:line`, zero
   placeholders. Write it to
   `$HOME/.agents/artifacts/plan/prompt-<slug>.md`. Say
   `Prompt: <path> (<n> lines)`.

   Your system prompt names the model you run on.

   **Fable** (`Fable`, `claude-fable-*`): a Claude Code pane builds, on
   Sonnet at high effort.
   - `HERDR_ENV` is not `1`: say `Not inside herdr. Open a herdr pane
     and run this there, or say "here" to build in this session.` and
     stop. `here` means the "Any other model" branch below.
   - Otherwise:

     ```bash
     bash scripts/pane.sh "$WT" <label> <prompt-path>
     ```

     The label is the first four words of the issue title (a chat
     plan: the plan title, its type tag left out) in kebab case. `stop:` on stderr: show it, stop. Exit 0: print its report
     line and hold `PANE` and `AGENT`. Then wait:

     ```bash
     ~/.claude/bin/herdr-wait <PANE> --timeout-sec 21600
     ```

     In Claude Code run it in the background; the tool wakes you when
     it ends. In Codex run it in the foreground with a long timeout.
     Read the tail, `herdr agent read <AGENT> --source visible --lines
     80`, and sort:
     - The last message starts with `QUESTION`: sort it by the two
       tests in `../plan-up/SKILL.md` step 5. **Small fork**: the plan,
       the issue (a chat plan: its brief), or the repo holds the
       answer; fetch the `file:line` with Explore, shape it per `render.sh local prompt` § Answer,
       write it to a file, `~/.claude/bin/herdr-send <PANE> --file
       <file> --no-wait`, tell the user in one line what was asked and
       answered, and wait again. **Big fork** (the list in plan-up step
       5, plus a force push, a delete, another branch): quote the
       question in a fenced block, then one question to the user, two
       options at most, your pick first. The user answers
       `/build-and-prove <note>`. Stop.
     - The last line is `BUILT <branch>`: step 8.
     - The last line is `NOT BUILT <branch>: …`: show it, stop.
     - Neither, and no question: the pane stopped short. Show the last
       20 lines and stop.
     - `STATUS=timeout`: say how long it ran, the pane's last lines,
       and stop.

   **Any other model**: you build. Read the prompt file and follow it
   whole as its builder, in `$WT`: slices in order, tests first, every
   command through `box.sh run`, one commit per slice. Say `Build:
   slice <k> of <n>` as each slice is committed. Its § Surprises are
   yours: stop and ask the user where it says stop and ask. It ends at
   `BUILT <branch>`.

   Then the gates once more, yourself, on the head commit: the full
   suite, typecheck, lint, and build under `Facts`, and every command
   the repo's `AGENTS.md` or `CLAUDE.md` names as a check, each through
   `box.sh run`. Write each to `$PROOF/checks.txt`, one line per
   command: the command, the short SHA, and the result, as in
   `pnpm test · 1a2b3c4 · 116 pass, 0 fail`. `/make-pr` counts these
   and runs none of them on this machine. A fix round rewrites the file.

8. **Walks.** `UI: none`: no walker; say `Walks: none (no UI)` and go
   to step 9. Else rounds, at most three:

   a. **Start the app.** You start it; the walker never does.

      ```bash
      bash scripts/box.sh run "$PROOF" -- sh -c '<Run line> >/tmp/app.log 2>&1 & echo $! >/tmp/app.pid'
      ```

      Then wait until it answers, the way the `Open` line reaches it:
      for a URL, `box.sh run "$PROOF" -- sh -c 'for i in $(seq 60); do
      curl -fsS -o /dev/null <url> && exit 0; sleep 2; done; exit 1'`.
      It does not answer: read `box.sh run "$PROOF" -- tail -n 50
      /tmp/app.log`. A missing tool or package is the setup script's:
      fix it, `box.sh down`, then step 5 again. A crash in the code is
      the builder's: a follow-up (step 8c). Still down after that:
      `box.sh down`, then stop with the log's last line.

   b. **Walker.** In Claude Code, the `walker` agent
      (`agents/walker.md`, linked into `~/.claude/agents/`); in Codex,
      no sub-agent, so you read `agents/walker.md` and follow it
      yourself, reading no code while you walk. Its brief, whole:
      - the mode, `before` or `after`, and the round;
      - the Sandbox id (`BOX_ID` in `$PROOF/box.env`), the OS, and the
        screen size (1440x900 on linux, 1280x800 on macos);
      - how to open the app: the `Open` line, as a command it runs with
        `proofbox exec`;
      - the plan's `UI walks` and `Videos` blocks, verbatim;
      - the folder to write in, `PROOF`.

      It does not get the code, the slices, or the diff. It returns
      one line per walk and writes `walk-report-<round>.md` in `PROOF`.
      It ended with `GONE <id>`: the app died with its Sandbox, so stop
      nothing and go to 8c. Else stop the app: `box.sh run "$PROOF" --
      sh -c 'kill $(cat /tmp/app.pid)'`. Read `/tmp/app.log` for each walk's `Must not`
      that the screen cannot show (console errors, failed requests):
      one found is a failed walk.

   c. **Sort.** The walker ended with `GONE <id>`: the Sandbox died
      under it, idle or at its max life. No walk failed; run the round
      again from 8a, where `box.sh run` makes a new Sandbox, and it does
      not count as a round. A second `GONE` in the same round: `box.sh
      down`, then stop with that line. Every walk passed: step 9. Each
      failed walk, by its screenshot and the plan, never by the walker's
      guess:
      - **App bug**: the steps reached the screen the walk names, and
        `See` is not there or a `Must not` is. A follow-up to the
        builder per `render.sh local prompt` § Follow-up: `# Changed`
        names the walk, what it saw, and the screenshot's path; `#
        Check` names the tests to run again. The pane gets it with
        `herdr-send`; as the builder, you do it yourself. Then the
        gates again (end of step 7).
      - **Wrong walk**: a label, route, or step the plan named is not on
        the screen, and the Done-when line still holds there. Sort it
        by the two tests in `../plan-up/SKILL.md` step 5. Small fork:
        fix the walk in the plan `.md`, add a `Decided` line, and say so
        in one line. Big fork, such as a walk whose fix changes what a
        Done-when line means: one question to the user, your pick first.
        Wait.

      Say `Walks round <r>: <p> passed, <f> failed`. Then the next round
      from 8a; every walk again, from the start. After round three with
      a failed walk: `box.sh down`, then stop with the failing videos'
      paths, one per line.

9. **Proof folder.** Write `$PROOF/proof.md`: the `## Proof` part per
   `../../shared-skill-core/pr-shape.md` § Proof, one row per Done-when
   line from the plan's Proof table, the test case by name, and for a
   plan with walks the `Screenshot` and `Video` columns and the
   Screenshots and Videos parts, each image and video as `./<file>` in
   `PROOF`. A row proved by a command carries the command, the short
   SHA, and the result from `checks.txt`.

10. **Down.** `bash scripts/box.sh down "$PROOF"`. Hold its `REMADE`
    count for the report.

11. **Report.** Chat gets this and nothing more:

    ```
    Built: #42 Export orders as CSV · feat/42-export-orders-csv · 4 commits
    Checks: pnpm test, pnpm lint, pnpm build green on 1a2b3c4 in the Sandbox
    Walks: 3 passed in round 2 · videos: 2 · built by: claude pane w4:p9M
    Sandbox: made again 1 time
    Proof: ~/.agents/artifacts/proof/acme-shop-42
    BUILT feat/42-export-orders-csv
    ```

    `UI: none`: `Walks: none (no UI)`. `REMADE=0`: no `Sandbox:` line.
    A chat plan: the first line has no `#<n>`, as in
    `Built: [feat] Export orders as CSV · feat/export-orders-csv`. The
    worktree is `WT`, and the branch is not pushed: `/make-pr` with the proof folder is next.

## Rerun

The same plan again after a stop. `checkout.sh` hands back the same
worktree, only when it is clean: a slice or a fix cut off before its
commit leaves changes, and step 3 stops on them with the files named.
The user commits or drops them, then runs again. The commits ahead of `BASE` are the first slices, one commit
each, in order: `git -C "$WT" rev-list --count <BASE>..HEAD` is the
number done, and the prompt starts at the next one. A count at or past
the number of slices means every slice is in, since fix rounds commit
only after the last slice: no builder, go to the gates at the end of
step 7. Before shots in
`PROOF` are kept. Every walk runs again from the start, since a video
must show the final code.

## Follow-up

`/build-and-prove <note>` with no plan path. A pane this chat started:
sort the note by plan-up step 5 (a big fork it leaves open goes to the
user first), shape it per `render.sh local prompt` § Answer when it
answers a `QUESTION`, else § Follow-up, `herdr-send <PANE> --file
<file>`, then back to step 7's sort. This chat started none: say so and
stop.

## Examples

**User:** `/build-and-prove ~/.agents/artifacts/plan/plan-acme-shop-42.md`
on Sonnet; the plan has `UI: web`, three walks, two videos.

Plan read, slug `acme-shop-42`. proofbox found. Worktree
`~/development/worktrees/acme/shop/feat-42-export-orders-csv` from
`main`. No setup script yet: written from `.nvmrc` and `pnpm-lock.yaml`;
`app.env` gets `PORT=3000` and an empty `STRIPE_KEY=`; the user fills it
in. `box.sh up` prints `SANDBOX=ns:us:abc`. Walk 1's `Before` names
steps: app started, walker in `before` mode, `before-1.png`. Prompt
written, this session builds four slices, each test red then green
through `box.sh run`. Gates green on `1a2b3c4`. Round 1: walk 3 fails,
its screenshot shows the `Export` button disabled with rows on screen:
an app bug, a follow-up, slice 4's code fixed, gates again. Round 2: all
pass. `proof.md` written, `box.sh down`, report.

**`box.sh up`** prints `stop: log in first: proofbox auth login namespace`.

Show it, `pbcopy` it, stop. Nothing to delete: no Sandbox was made.

**Walker** reports walk 2 failed: step 3 says click `Save`, the screen
shows `Save changes`, and after it the saved row is there.

The Done-when line holds; only the label in the plan was wrong. Small
fork: walk 2's step fixed in the plan, a `Decided` line, one line to the
user, round 2.
