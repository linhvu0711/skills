# build-and-prove

Builds a plan on your machine and proves it, the way a cloud agent would, without its cost. Coding, each slice's test, typecheck, and lint, runs on the local machine. Then, for a plan with UI walks, one proofbox Sandbox runs the Gates (the full suite, lint, the build, and the repo's own checks) and the app, and a walker films the walks like a test user. A plan with no UI starts no Sandbox and needs no proofbox: each Gate the PR's CI runs is left to CI, and your machine runs the rest, one at a time.

## Use it when

You have a plan from [plan-up](../plan-up/) and want it built and proved with videos, with the full suite and the app kept off your machine. [ship](../ship/) runs it for you by default. Run it alone with:

- `/build-and-prove <plan.md>`: the plan of one ticket.
- `/build-and-prove <plan.md> --layer <n> --base <branch>`: one layer of a run.
- `/build-and-prove <plan.md> follow-up <change>`: more work on a branch it built, such as a change you ask for or review fixes. With no change, it picks up a build that stopped.

It only runs when you call it.

## What you get

A worktree under `~/development/worktrees` on the issue's branch (a plan with no issue gets a branch with no number, as in `feat/export-orders-csv`), with one commit per slice, every Gate green in the Sandbox, green on your machine, or left to the PR's CI. The branch is not pushed. Next to it, a proof folder at `~/.agents/artifacts/proof/<slug>/`, named like the plan file (`<owner>-<repo>-<n>`, or `<owner>-<repo>-chat-<words>`): the videos, the before and after screenshots, `proof.md`, the PR's `Proof` part, and `checks.txt`, the Gates it ran on the head commit, each line ending with where it ran, so make-pr runs none of them again. A Gate the Sandbox cannot run runs on your machine; one that can run in neither place is marked for CI. `box.sh gates` writes those lines too, from its `--on-local` and `--not-run` options, so no Gate line is written by hand. [make-pr](../make-pr/) turns that into the PR.

On the way:

- **A todo list.** It lists its steps at the start and marks each one done, or skipped with the reason, so a compacted chat keeps its place. With no todo tool in the host, it keeps the list in the chat. Run by [ship](../ship/), its steps sit in that skill's list.
- **One Sandbox, only for a plan with UI walks.** A plan with no UI runs its Gates with `box.sh gates --local`, which writes the same `checks.txt` lines, ending `(local machine)`, and a `not run: CI runs it` line for each Gate the PR's CI runs. It asks the shared `ci-covers.sh`, which uses one strict rule: the exact command on a `run:` line of a GitHub workflow that runs on pull requests. A longer command, a comment, or a workflow that runs only on push does not count, so that Gate runs on your machine. A Gate whose tool your machine lacks stops and asks you to install it. The Sandbox starts after Coding. `scripts/box.sh` creates it, runs the app there, and runs every Gate there in one `gates` call. That call keeps each Gate's own exit code, exits 3 when a Gate is red and 1 when it has to stop, so the two are never mixed up, writes `checks.txt` itself, and keeps each Gate's full output in a temp file it names when the Gate is red. It makes the Sandbox again from its Snapshot when it dies, so a run can outlast one Sandbox. Namespace deletes a Sandbox after 30 idle minutes on Linux and 10 on a Mac, where a minute costs ten times more, and after proofbox's 3-hour max life, which every Namespace plan allows. A new one takes 1 to 3 minutes, and your code stays on your local machine, so nothing is lost. A Sandbox the builder started early, for a tool your machine lacks, is the same one the run keeps. In a repo with e2e tests, each slice runs the e2e spec files it touches there before its commit, so the Sandbox starts with the first such slice. The report says how many times it was made again. `up` shows what proofbox prints as it makes the Sandbox: the setup script's last lines when it fails, the Snapshot line when it reuses one. Each command there is a `proofbox upload` of the changed files plus a `proofbox exec`. `box.sh start` runs the app in its own process group and waits until it answers; `box.sh stop` ends the app and every process it started, and waits until its port is free before the next start.
- **A builder.** This chat builds, on the model you run. It follows the handoff rules for a local build, so its tests check what the code gives back, never which of its own functions it called, a fix's first test fails for the bug's reason before the change, a test that is green before its change is broken once on purpose and must go red, a test that says no must fail at its own check, and a red that two fixes did not turn green gets a tested belief before a third fix, and a second surprise of the same kind stops the build with a question, and so does a change to the look of a screen the issue does not name. Its comments say why, never what, and it checks data at the edge where it comes in. It writes skill and steering files by [write-for-agents](../write-for-agents/), and runs [unslop](../unslop/) on README and doc prose.
- **A walker.** A Sonnet subagent at high effort that does each walk as a test user: it gets the walks and what it must see, pasted as text in its brief, never the code, records each video with proofbox, each in a browser with an empty profile, Chromium with `--no-sandbox` so it starts in the Sandbox, opened with `box.sh open` in its own process group and closed with `box.sh close` by that group after each video, never by name; before each recording it checks with `box.sh fit` that the browser window ends above the Sandbox's taskbar, and a page taller than the screen films nothing and fails its walks as `page taller than the screen`; a browser that will not start is tried once more, then reported with its error text. It types one command per step and looks at the screen after each Enter, so a viewer can follow each step; it waits 3 s after each click, shoots a state that lasts under 3 s with the action that shows it, and runs a timed run of steps, such as `click Undo within 5 s`, as one Sandbox command, so it fits its window on linux and macOS, after a try before the recording that finds where a button the run makes appear will be, and with a shot of a state the run shows halfway, and says what passed and what broke. Each shot it takes only to look goes in its own temp folder, so the proof folder holds only the files its report names. The before and after runs write their own reports, `walk-report-before-<round>.md` and `walk-report-after-<round>.md`. A before shot that fails is deleted and taken again, so no failed shot reaches the PR. A reply that does not end in its report lines goes back once; a second one stops the run. It never deletes outside its folder to reset a walk; a walk that runs only once per Sandbox is a finding. A walk that fails because the Sandbox lacks a tool or a UTF-8 locale is a Sandbox fault: the setup script is fixed and the round runs again, not counted. After each video, the session reads a strip sheet of its cut labels and the frames next to each cut, and fails a walk whose video hides a step's action. A broken walk goes back to the builder when the app is wrong, or into the plan, with a written reason, when the walk is wrong; a walk whose pass rule changed is filmed again before it counts. A later round, or a follow-up, films again only the videos with a failed walk or with a walk a changed file reaches, and keeps the rest; the PR says which commit a kept video was filmed on. A walk that sets the clock opens the app at that time, so no run waits for the real clock. At most three rounds.
- **A follow-up.** It reads what is done from the worktree and the proof folder. It builds any slice not built yet, then the change. Then it does again only what the change reaches: the missing before shots, the videos whose screens the change touches, and the perf measure when the change touches the code the perf command runs. Once the PR is open, it runs only the Gates the PR's CI does not run. It starts a Sandbox only when one of these needs it, and stops it at the end. It never pushes: [make-pr](../make-pr/) updates the PR from the proof folder.
- **Setup files.** On the first run for a repo it writes `~/.agents/proofbox/<owner>-<repo>/setup-<os>.sh` from the repo, with the tools its checks and its walks need, kept in `/tmp/pb`, outside the Work folder, and put in reach of every command through `$PROOFBOX_ENV`, with a UTF-8 locale, and an `app.env` with an empty line for each secret you fill in, which `box.sh` passes to proofbox as `--secrets`. Later runs reuse them. An optional `size` file there, one line such as `8x16`, sets the Sandbox size for that repo; without it proofbox's default applies.

It stops at once when the repo's install command needs a tool your machine lacks, and, on a plan with walks, when proofbox is missing. On a plan with walks it checks the proofbox login first, before any code is written: a missing or expired login stops the run with the login command on your clipboard. A command in the Sandbox that cannot find a tool, as with a setup script from an older run, gets the script rewritten and a new Sandbox, whether it is a slice test, a Gate, the app, or a walk. Later it stops, with the Sandbox deleted and your commits kept, when a Sandbox will not start or the app will not start. Run it again on the same plan and it picks up at the first slice with no commit. When a walk failed in an earlier round, a Must not went unchecked, or a walk's pass rule changed, the last message lists each one word for word under `Walk notes:`. The last message:

```
Built: #42 Export orders as CSV · feat/42-export-orders-csv · 4 commits
Checks: pnpm test, pnpm lint, pnpm build green on 1a2b3c4 in the Sandbox
Walks: 3 passed in round 2 · videos: 2 · built by: session
Walk notes:
- after round 1 · walk 2: FAIL · step 3: no `Save` button; the screen shows `Save changes` · fail-2.png · video 1 @ step 3
- walk 1: not checked: no console errors
- W2 See changed after round 1: "Saved" → "Changes saved". The toast text is the app's
Proof: ~/.agents/artifacts/proof/acme-shop-42
BUILT feat/42-export-orders-csv
```

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

A `perf` PR proves its speed line with one Proof row: the metric and unit, `before → after`, the run count, and the command, plus the issue's Baseline when the base median falls outside its spread.

On a `perf` plan it runs the plan's command in turns on the base and the head, in the Sandbox, or on your machine for a plan with no UI, by the benchmark checklist, and the PR's Proof shows `before → after`.

A delete slice, a plan's first, deletes code that no caller uses: its tests exist already and must pass before the delete and after it; with no test near that code, the search that found no caller must find nothing after the delete.

The walks guide now has a heading for each of its three parts: start the app, walker, and sort. A step that needs one part names it, and a step that runs a whole round still reads the whole guide. A run reads only its own layer of the plan.

Starting and stopping the app, and opening and closing the walker's browser, are now `box.sh` commands with tests: `start`, `stop`, `open`, and `close`. Before, the session and the walker copied long shell lines by hand, and the two copies had different wait times. The waits stay the same: 30 s for the app to stop, 10 s for the browser. `box.env` also notes whether the Sandbox holds the base or the branch, and `start` prints which one it runs.

## Needs

- For a plan with UI walks: [proofbox](https://github.com/linhvu0711/proofbox), installed and logged in to its Provider. Its own config, `~/.config/proofbox/config`, picks the Provider per OS. No Windows.
- `git`, and `gh` (signed in) for the issue.
- `ffmpeg` on the local machine, to read frames from each video.
- The walker's agent file, `agents/walker.md`, which [link.sh](../../scripts/link.sh) links into Claude Code. Codex has no sub-agents, so the session walks under the same rules.
- The shared core files `../../shared/facts.md`, `../../shared/checkout.sh`, `../../shared/copy.sh`, `../../shared/pr-shape.md`, `../../shared/benchmark.md`, pasted into the cloud rules and read in its own perf step, and the templates in `../../shared/handoff/`.
- A clipboard tool, optional, for the login command, through [copy.sh](../../shared/copy.sh): macOS, Linux, or Windows. With none, it says the copy was skipped.

## Fits with

- Builds the plan [plan-up](../plan-up/) writes, with the rules [handoff](../handoff/) renders for a local builder.
- Called by [ship](../ship/), which then runs [make-pr](../make-pr/) with the proof folder and [ready-pr](../ready-pr/).
- Why Coding runs on the local machine and the Gates in the Sandbox, and why the walker never reads code: ADRs 0011 and 0010 in this repo. Why a plan with no UI starts no Sandbox: ADR 0019.

## Credits

The builder's rule that a test checks what the code gives back, never which calls it made, takes an idea from `tdd/tests.md` in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). No text was copied.

The todo list takes an idea from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

The perf step takes an idea from the `benchmark-checklist` skill in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

The break that must turn a test red, and the rule that a test that says no fails at its own check, take ideas from the `test-audit` skill in [openclaw/openclaw](https://github.com/openclaw/openclaw) (MIT). No text was copied.
