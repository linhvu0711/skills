---
name: build-and-prove
description: "Build a /plan-up plan on this machine and prove it: Coding, the Gates the PR's CI does not run, and the perf measure run on the local machine, and one Cursor Proof agent per run takes the before shots and films the UI walks like a test user. Ends at a pushed branch, with no PR, one commit per slice, and a proof folder for /make-pr. /ship runs it by default."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

One plan, one branch, one Proof agent, one proof folder. Facts come
from reading, per `../../shared/facts.md`. Big forks go to
the user; everything else you decide, write down, and go on. You push
the branch so the Proof agent can check it out, and you never open a
PR: `/make-pr` does that with the proof folder.

In Claude Code every Bash call starts in the session's directory. Every
git command in the worktree is `git -C "$WT" …`.

## Proof agent

Coding runs on the local machine: each slice's red and green test,
typecheck, lint, and e2e spec files, in the worktree, with the repo's
packages installed there. One run has one Proof agent: a Cursor cloud
agent that starts at the same time as Coding. It takes the before shots
on the base, and after Coding it runs the app and films the walks on
the branch (ADRs 0019 and 0020 in this repo). The Gates and the perf
measure run per `references/checks.md`: the PR's CI or the local
machine, never the agent. It never edits code and never reads the
app's code (ADR 0010): its rules are `references/proof-agent.md`,
pasted whole into its prompt.

`CLIENT` is `../../shared/cursor/cursor.sh`, the Cursor client
`/handoff` runs too; it prints its usage with no arguments. This skill
uses `start`, `poll`, `wait`, `say`, `artifacts`, `download`, and
`down`. A `cursor.sh: ` line on stderr is the reason to stop.

- An agent holds runs: `start` makes run 1, each `say` the next. One
  run at a time: a `say` while a run is going stops with `409
  agent_busy`, so `wait` first, then `say` again.
- `wait` prints one line when the latest run ends: state, run, PRs,
  URL, and the agent's last message, tab separated. The state is
  `finished`, `error`, `cancelled`, or `expired`.
- `error`, `cancelled`, or `expired`: show the agent's last message,
  run `down`, and stop. The branch and its commits stay; a rerun starts
  a new agent.
- `Platform: macos-outpost`: the agent runs on a rented Namespace Mac
  (`start --platform macos --hold-mac`), held through Coding. Step 8
  gives it back, and every stop after step 3 runs `bash "$CLIENT" down
  "$AGENT"` first. On Cursor's own machines `down` prints `no Mac` and
  does nothing.

**Setup fault.** A run that ends with `SETUP FAULT: <tool> not found`,
or a walk or the app that fails on a tool `not found`, is the
agent's machine, not the code. A follow-up with `Install: <tool>`
(`references/walks.md` § 6a) has it install the tool and run the same
round again. It does not count as a round. After three in one run:
`down`, then stop with the last one.

## Forms

- `/build-and-prove <plan.md>`: the plan of one ticket.
- `/build-and-prove <plan.md> --layer <n> --base <branch>`: layer `n` of
  a run's plan, its branch made from `<branch>`. `/ship` uses this form.
- `/build-and-prove <note>`: an answer or follow-up for the pane this
  chat started (§ Follow-up).
- No plan named and none in this chat: say `Run /plan-up first.` and
  stop.

## Todo list

Before step 1, open a todo list: TodoWrite in Claude Code, `update_plan`
in Codex. It holds one item per step of § Steps, its number and bold
title word for word, as in `4. Coding.` Run by `/ship`, open no list of
your own: ship's list already holds these steps under its step 5, so
mark those items.

Mark each item in progress as it starts and done as it ends. A step the
run does not do stays in the list as `<title> skip: <reason>`. After
the chat is compacted, the list says where the run is: go on from the
first item that is not done.

## Steps

1. **Plan.** Read the plan `.md` whole: steps 3 and 4 paste its blocks
   into the prompts. A run: read the blocks above the first
   `## Layer` heading, then this layer's, from `## Layer <n>` to the
   next `## Layer`; no other layer is held. Stop with one line on each
   of these:
   - no file at the path: `No plan at <path>.`
   - no `# Plan:` heading, or no `Repo:` line under `## Facts`: `<path>
     is not a /plan-up plan.`
   - a `## Stack` block and no `--layer`: `A run: /ship builds it
     layer by layer, or name --layer <n>.`
   - `Platform: windows`: `Cursor's machines run no Windows. Use Devin:
     /ship <issue-url> devin?` and wait for the answer. A chat plan (no
     `#<n>` in its `# Plan:` line) has no issue for Devin: `Cursor's
     machines run no Windows, and Devin needs an issue. Run /to-issue
     first.` and stop.

   Hold `REPO` (the `Repo:` line), `BASE` (`--base`, else the `Base:`
   line), the issue number `N`, `UI` (the `UI:` line), the platform
   (`linux`, or `macos` for `macos-outpost`), `PERF` (the plan's `Perf`
   block, or none), and the layer's blocks: for a run, only the blocks
   under `## Layer <n>`, and `PERF` is the layer's. The slug is
   `<owner>-<repo>-<N>`. A chat plan
   (`../plan-up/references/plan.md` § Chat plan) has no `N`: its slug
   is the plan file's, `plan-<slug>.md`. `PROOF` is
   `$HOME/.agents/artifacts/proof/<slug>`. Make it.

2. **Worktree.** The branch follows the PR shape § Branch
   (`../../shared/pr-shape.md`): the issue's type, its
   number, two to four words, as in `fix/133-uninstall-reverses-setup`.
   A chat plan: the type from its title, then the words of its slug
   after `chat-`, as in `feat/export-orders-csv` for
   `acme-shop-chat-export-orders-csv`. The slug was picked so that no
   branch had this name, so an existing branch here is this plan's
   rerun.

   ```bash
   bash ../../shared/checkout.sh <REPO> <branch> --base <BASE>
   ```

   `stop:` on stderr: show it, stop. Hold `WT` from the `WORKTREE=`
   line. The branch has commits ahead of `BASE` already: this is a
   rerun (§ Rerun).

3. **Proof agent.** Before Coding, so a missing key, credit, or secret
   shows in minutes, and the before shots are ready when Coding ends.

   **Secrets.** The names the app needs from outside: each name in
   `$WT/.env.example` whose value there is empty or a placeholder, and
   each `$NAME` the plan's `Run` line reads that no file in the repo
   sets. A name whose value the repo shows, a test port or a local URL,
   is not one. Hold them as `SECRETS`, or none. Never a value.

   **Prompt.** Write `$HOME/.agents/artifacts/plan/proof-prompt-<slug>.md`:
   the head lines `Repo: <REPO>`, `Base branch: <BASE>`, `Branch:
   <branch>`, `Platform: <platform>`, and `Before shots: walks <w>,
   <w>`, the walks whose `Before` line names steps and that have no
   `before-<walk>.png` in `PROOF` yet, or `Before shots: none`; then `# Secrets`, the `SECRETS`
   names one per line, or `none`; `# Facts`, the plan's `Facts` block;
   `# UI walks` and `# Videos`, the plan's blocks verbatim; then
   `# Rules`, `references/proof-agent.md` whole, unchanged, once. Check: zero placeholders. Say `Proof prompt:
   <path> (<n> lines)`.

   **Start.**

   ```bash
   bash "$CLIENT" start <prompt-path> --repo <REPO> --base <BASE> --title "Proof: <slug>"
   ```

   `macos` adds `--platform macos --hold-mac`. Its line is `<agent>\t<url>`.
   Write `$PROOF/agent.env`: `AGENT=<agent>`, `URL=<url>`, and
   `PLATFORM=<platform>`, one per line. Hold `AGENT`. Say `Proof agent:
   <url>`. A stop line here comes before Coding:
   - `cursor.sh: no CURSOR_API_KEY …`: show it, and the command that
     puts a key in `~/.zshrc`, `echo 'export CURSOR_API_KEY=<your crsr_
     key>' >> ~/.zshrc`, copied with `../../shared/copy.sh` (any other
     exit than 0: say `Clipboard copy skipped.`). The user makes the key
     at cursor.com/dashboard, API Keys. Stop.
   - Any other `cursor.sh:` line, such as `HTTP 402 on POST /agents:
     …` with no credit, or a repo not connected to Cursor: show it
     whole, the API's reason in it, and stop.

   A rerun: an `agent.env` from an earlier run is replaced; `down` its
   `AGENT` first, so no Mac of it stays rented.

4. **Coding.** Install the repo's packages in `$WT` on the local
   machine, with the install command its lockfile calls for; a repo
   with no lockfile installs nothing. The install fails because the
   local machine lacks its tool (`command not found`, exit 127): say
   `<tool> is not installed on this machine; install it and run again.`,
   `down`, and stop.

   Assemble the prompt per
   `bash ../../shared/handoff/render.sh local prompt`: the
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

   **The Proof agent's run 1** ends while Coding goes on. In Claude
   Code, run `bash "$CLIENT" wait "$AGENT"` in the background; the tool
   wakes you when it ends. As the builder yourself, or in Codex, run
   `bash "$CLIENT" poll "$AGENT"` after each slice's commit. When it
   ends, sort its last message:
   - `MISSING SECRETS: <names>`: one message, while Coding goes on:
     `The Proof agent lacks <names>. Add them to this repo's environment
     on cursor.com (Cloud Agents, Secrets).` Never ask for or print a
     value. Hold the names: step 6's first note checks them again.
   - `SETUP FAULT: <tool> not found`: a setup fault (§ Proof agent),
     its note the same round 1 again.
   - `BEFORE` lines: hold them; step 6 downloads the shots.
   - `error`, `cancelled`, or `expired`: § Proof agent. A pane that
     still builds keeps its commits, and a rerun starts at its first
     slice with no commit.

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
     line and hold `PANE`, and its `AGENT` as `AGENT_PANE`, apart from the Proof agent's. Then wait:

     ```bash
     ~/.claude/bin/herdr-wait <PANE> --timeout-sec 21600
     ```

     In Claude Code run it in the background; the tool wakes you when
     it ends. In Codex run it in the foreground with a long timeout.
     Read the tail, `herdr agent read <AGENT_PANE> --source visible --lines
     80`, and sort:
     - The last message starts with `QUESTION` about a tool the local
       machine lacks: say `<tool> is not installed on this machine;
       install it, then say go.` and wait. On `go`, answer per
       `render.sh local prompt` § Answer that the tool is there now and
       to run the command again, send it, and wait again.
     - Any other `QUESTION`: sort it by the two
       tests in `../plan-up/SKILL.md` step 5. **Small fork**: the plan,
       the issue (a chat plan: its brief), or the repo holds the
       answer; fetch the `file:line` with Explore, shape it per `render.sh local prompt` § Answer,
       write it to a file, `~/.claude/bin/herdr-send <PANE> --file
       <file> --no-wait`, tell the user in one line what was asked and
       answered, and wait again. **Big fork** (the list in plan-up step
       5, plus a force push, a delete,
       another branch, a look change on a screen the issue does not name):
       quote the question in a fenced block, then one question to the
       user, two options at most, your pick first. The user answers
       `/build-and-prove <note>`. Stop.
     - The last line is `BUILT <branch>`: step 5.
     - The last line is `NOT BUILT <branch>: …`: show it, `down`, stop.
     - Neither, and no question: the pane stopped short. Show the last
       20 lines, `down`, and stop.
     - `STATUS=timeout`: say how long it ran, the pane's last lines,
       `down`, and stop.

   **Any other model**: you build. Read the prompt file and follow it
   whole as its builder, in `$WT`: slices in order, tests first, each
   slice's test, typecheck, lint, and e2e spec files on the local
   machine, in `$WT`, one commit per slice. A tool the local machine
   lacks: say `<tool> is not installed on this machine; install it,
   then say go.` and wait. Say `Build: slice <k> of <n>` as each slice
   is committed. Its § Surprises are yours: stop and ask the user where
   it says stop and ask. It ends at `BUILT <branch>`.

5. **Push.** The Proof agent checks the branch out from GitHub:

   ```bash
   git -C "$WT" push -u origin <branch>
   ```

   No PR. It fails: show git's error, `down`, and stop, before any
   follow-up. Run 1 still going: `bash "$CLIENT" wait "$AGENT"` first,
   and sort it as step 4 does.

6. **Proof rounds.** Rounds, at most three. Read
   `references/checks.md` whole: every round runs its local checks,
   the Gates and the perf measure, in round 1 and in each round after
   code changed. A plan with walks also reads `references/walks.md`
   whole and runs all three of its sections each round: 6a send first,
   so the agent films while the local checks run, then 6b fetch and 6c
   sort. A round is done when both are.

7. **Proof folder.** Write `$PROOF/proof.md`: the `## Proof` part per
   `../../shared/pr-shape.md` § Proof, one row per Done-when
   line from the plan's Proof table, the test case by name, and for a
   plan with walks the `Screenshot` and `Video` columns and the
   Screenshots and Videos parts, each image and video as `./<file>` in
   `PROOF`, each video's line with its commit from `videos.txt`. A row proved by a command carries the command, the short
   SHA, and the result from `checks.txt`. The Target line's row of a
   plan with a `PERF` block carries the perf line from `checks.txt`, per
   `../../shared/pr-shape.md` § Proof. A `not run` line from
   `checks.txt`, `CI runs it` too, goes in as its command, `not run:
   <why>`, and the words `CI must prove it`. `agent.env` stays: `/ship` sends its re-films to
   that agent.

8. **Give back.** `bash "$CLIENT" down "$AGENT"`. A Mac goes back to
   Namespace; on Cursor's machines it prints `no Mac`.

9. **Report.** Chat gets this and nothing more:

    ```
    Built: #42 Export orders as CSV · feat/42-export-orders-csv · 4 commits
    Checks: pnpm test, pnpm lint, pnpm build green on 1a2b3c4 on the Proof agent
    Walks: 3 passed in round 2 · videos: 2 · built by: claude pane w4:p9M
    Walk notes:
    - after round 1 · walk 2: FAIL · step 3: no `Save` button; the screen shows `Save changes` · fail-2.png · video 1 @ step 3
    - walk 1: not checked: no console errors
    - W2 See changed after round 1: "Saved" → "Changes saved". The toast text is the app's
    Proof agent: https://cursor.com/agents/bc-1a2b · setup faults: 1
    Proof: ~/.agents/artifacts/proof/acme-shop-42
    BUILT feat/42-export-orders-csv
    ```

    The `Walk notes:` block copies, word for word: each `FAIL` line of
    every `walk-report-before-<r>.md` and `walk-report-after-<r>.md` in
    `PROOF`, with its mode and round in front; each `not checked:` part
    of a walk's line, once per walk; and each `Decided` line this run
    added in the `W<w> ... changed after round <r>` shape
    (`references/walks.md` § 6c. Sort). None of them: no notes block, and the
    `Walks:` line says the walks passed, as above.

    `UI: none`: `Walks: none (no UI)`. No setup fault: the `Proof
    agent:` line has only the URL. A chat plan: the first line has no
    `#<n>`, as in
    `Built: [feat] Export orders as CSV · feat/export-orders-csv`. The
    worktree is `WT`, and the branch is pushed with no PR: `/make-pr`
    with the proof folder is next.

## Rerun

The same plan again after a stop. `checkout.sh` hands back the same
worktree, only when it is clean: a slice or a fix cut off before its
commit leaves changes, and step 2 stops on them with the files named.
The user commits or drops them, then runs again. Step 3 starts a new
Proof agent. The commits ahead of `BASE` are the first slices, one
commit each, in order: `git -C "$WT" rev-list --count <BASE>..HEAD` is
the number done, and the prompt starts at the next one. A count at or
past the number of slices means every slice is in, since fix rounds
commit only after the last slice: no builder, go to step 5. Before
shots in `PROOF` are kept, and the new agent's run 1 takes only the
ones missing. The videos in `PROOF` are kept too, and step 6 films
again only those `references/walks.md` § 6c. Sort names.

## Follow-up

`/build-and-prove <note>` with no plan path. A pane this chat started:
sort the note by plan-up step 5 (a big fork it leaves open goes to the
user first), shape it per `render.sh local prompt` § Answer when it
answers a `QUESTION`, else § Follow-up, `herdr-send <PANE> --file
<file>`, then back to step 4's sort. This chat started none: say so and
stop.

## Examples

Sample runs, a missing secret, a no-credit stop, and a wrong walk:
`references/examples.md`. Read it when a step here is unclear.
