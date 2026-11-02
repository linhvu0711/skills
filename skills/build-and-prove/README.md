# build-and-prove

Builds a plan on your machine and proves it on a Cursor cloud agent. Coding, each slice's test, typecheck, lint, and e2e spec files, runs on the local machine. One Cursor agent per run, the Proof agent, does the rest: it takes the before shots, runs the Gates (the full suite, lint, the build, and the repo's own checks), films the UI walks as a test user, and measures perf. It only runs things and reports; it never edits code.

## Use it when

You have a plan from [plan-up](../plan-up/) and want it built and proved with videos, with the full suite and the app kept off your machine. [ship](../ship/) runs it for you by default. Run it alone with:

- `/build-and-prove <plan.md>`: the plan of one ticket.
- `/build-and-prove <plan.md> --layer <n> --base <branch>`: one layer of a run.
- `/build-and-prove <note>`: an answer or follow-up for the Claude Code pane this chat started.

It only runs when you call it.

## What you get

A worktree under `~/development/worktrees` on the issue's branch (a plan with no issue gets a branch with no number, as in `feat/export-orders-csv`), with one commit per slice, every Gate green on the Proof agent. The branch is pushed to GitHub, with no PR, so the agent can check it out. Next to it, a proof folder at `~/.agents/artifacts/proof/<slug>/`, named like the plan file (`<owner>-<repo>-<n>`, or `<owner>-<repo>-chat-<words>`): the videos, the before and after screenshots, and the walk reports, downloaded from the agent; `proof.md`, the PR's `Proof` part; `checks.txt`, the Gates run on the head commit, each line ending with where it ran, so make-pr runs none of them again; and `agent.env`, the agent's id, so [ship](../ship/) can ask the same agent to film a walk again after a review fix. A Gate the agent cannot run, such as one that needs Docker, runs on your machine; one that can run in neither place is marked for CI. [make-pr](../make-pr/) turns that into the PR.

On the way:

- **A todo list.** It lists its steps at the start and marks each one done, or skipped with the reason, so a compacted chat keeps its place. Run by [ship](../ship/), its steps sit in that skill's list.
- **One Proof agent per run.** It starts at the same time as Coding, on the base branch, through the shared Cursor client, `../../shared/cursor/cursor.sh`, which [handoff](../handoff/) uses too. Its prompt holds the plan's walks, the Gates, the perf block, and its rules from `references/proof-agent.md`: commit nothing, push nothing, never read the app's code. Its first run checks that each secret the app needs is set (the names from `.env.example` and the plan's `Run` line, never a value) and takes the before shots, so a missing secret shows in minutes and the shots are ready when Coding ends. A missing secret gets one message while Coding goes on: the names, and where to add them on cursor.com. When Coding ends, the branch is pushed and one follow-up asks for the Gates, the walks, and the perf measure. Each later round is a follow-up to the same agent with only the videos that need filming again. The session lists the agent's files and downloads each one into the proof folder; a file that does not come is asked for once more, then its walk is marked failed with the file named. A plan for `macos-outpost` runs the agent on a rented Namespace Mac, held through Coding and given back when the run ends, also on a stop.
- **A builder.** On Fable inside herdr, a Claude Code pane on Sonnet at high effort; on any other model, this chat. It follows the handoff rules for a local build, so its tests check what the code gives back, never which of its own functions it called, a fix's first test fails for the bug's reason before the change, a test that is green before its change is broken once on purpose and must go red, a test that says no must fail at its own check, and a red that two fixes did not turn green gets a tested belief before a third fix, and a second surprise of the same kind stops the build with a question, and so does a change to the look of a screen the issue does not name. A tool your machine lacks stops it with a question, and you install the tool. Its comments say why, never what, and it checks data at the edge where it comes in. It writes skill and steering files by [write-for-agents](../write-for-agents/), and runs [unslop](../unslop/) on README and doc prose.
- **Walks as a test user.** The agent does each walk from the plan's steps, never from the code, records each video at a person's pace, waits about 3 s after each click, shoots a state that lasts under 3 s with the action that shows it, and runs timed steps back to back. It says what passed and what broke, in the screen's words, in `walk-report-before-<round>.md` and `walk-report-after-<round>.md`. A report that does not end in its report lines is asked for once more; a second miss stops the run. A broken walk goes back to the builder when the app is wrong, or into the plan, with a written reason, when the walk is wrong; a walk whose pass rule changed is filmed again before it counts. A later round, or a rerun, films again only the videos with a failed walk or with a walk a changed file reaches, and keeps the rest; the PR says which commit a kept video was filmed on. At most three rounds.
- **Setup faults.** A run that fails because the agent's machine lacks a tool, such as `ffmpeg`, gets a follow-up to install it and run again. It does not count as a round; the third in one run stops it.

It stops before any code is written when the Cursor key is missing (the line that adds it to `~/.zshrc` goes on your clipboard, with a placeholder for the key), when the account has no credit, or when the repo is not connected to Cursor, and it shows the API's reason. It stops at once when the repo's install command needs a tool your machine lacks. Later it stops, with your commits kept, when the push fails, or when the agent's run ends with an error or expires: the last message shows, and a rerun starts a new agent. Run it again on the same plan and it picks up at the first slice with no commit. When a walk failed in an earlier round, a Must not went unchecked, or a walk's pass rule changed, the last message lists each one word for word under `Walk notes:`. The last message:

```
Built: #42 Export orders as CSV · feat/42-export-orders-csv · 4 commits
Checks: pnpm test, pnpm lint, pnpm build green on 1a2b3c4 on the Proof agent
Walks: 3 passed in round 2 · videos: 2 · built by: claude pane w4:p9M
Walk notes:
- after round 1 · walk 2: FAIL · step 3: no `Save` button; the screen shows `Save changes` · fail-2.png · video 1 @ step 3
- walk 1: not checked: no console errors
- W2 See changed after round 1: "Saved" → "Changes saved". The toast text is the app's
Proof agent: https://cursor.com/agents/bc-1a2b
Proof: ~/.agents/artifacts/proof/acme-shop-42
BUILT feat/42-export-orders-csv
```

Each fact it states carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

On a `perf` plan the agent runs the plan's command in turns on the base and the head, by the benchmark checklist, and the PR's Proof shows `before → after`, plus the issue's Baseline when the base median falls outside its spread.

A delete slice, a plan's first, deletes code that no caller uses: its tests exist already and must pass before the delete and after it; with no test near that code, the search that found no caller must find nothing after the delete.

The proofbox Sandbox and the walker subagent this skill used before are kept, unused, in `deprecated/proofbox/` at the repo root.

## Needs

- A Cursor API key in `CURSOR_API_KEY`, in `~/.zshrc` or the environment, with credit on the account. Make it at cursor.com/dashboard, API Keys.
- The repo connected to Cursor (cursor.com/dashboard, Integrations, GitHub), and each secret the app needs in that repo's Cursor environment (Cloud Agents, Secrets). The skill names the missing ones; it never sees a value.
- For a `macos-outpost` plan: the Namespace CLI `nsc`, signed in, and a personal Cursor key that starts with `crsr_`. No Windows.
- `git`, `curl`, `jq`, and `gh` (signed in) for the issue and the push.
- The shared core files `../../shared/facts.md`, `../../shared/checkout.sh`, `../../shared/copy.sh`, `../../shared/pr-shape.md`, `../../shared/benchmark.md`, the Cursor client and Mac script in `../../shared/cursor/`, and the templates in `../../shared/handoff/`.
- A clipboard tool, optional, for the key command, through [copy.sh](../../shared/copy.sh): macOS, Linux, or Windows. With none, it says the copy was skipped.
- For a Claude Code pane (Fable only): herdr with this chat inside it (`HERDR_ENV=1`), the Claude Code CLI `claude`, signed in, and the helpers `herdr-wait` and `herdr-send` in `~/.claude/bin`. These two helpers are not in this repo.

## Fits with

- Builds the plan [plan-up](../plan-up/) writes, with the rules [handoff](../handoff/) renders for a local builder, and shares handoff's Cursor client.
- Called by [ship](../ship/), which then runs [make-pr](../make-pr/) with the proof folder and [ready-pr](../ready-pr/).
- Uses [kickoff-herdr](../kickoff-herdr/)'s `equalize_columns.py` to even out pane widths.
- Why the proof runs on a Cursor agent, and why it never reads code: ADRs 0019 and 0010 in this repo.

## Credits

The builder's rule that a test checks what the code gives back, never which calls it made, takes an idea from `tdd/tests.md` in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). No text was copied.

The todo list takes an idea from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

The perf step takes an idea from the `benchmark-checklist` skill in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

The break that must turn a test red, and the rule that a test that says no fails at its own check, take ideas from the `test-audit` skill in [openclaw/openclaw](https://github.com/openclaw/openclaw) (MIT). No text was copied.
