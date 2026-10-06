# build-and-prove

Builds a plan on your machine and proves it, the way a cloud agent would, without its cost. Your Mac only edits files and runs git. One proofbox Sandbox runs every test, the build, and the app, and a walker films the UI walks like a test user.

## Use it when

You have a plan from [plan-up](../plan-up/) and want it built and proved with videos, while your Mac stays free for other work. [ship](../ship/) runs it for you by default. Run it alone with:

- `/build-and-prove <plan.md>`: the plan of one ticket.
- `/build-and-prove <plan.md> --layer <n> --base <branch>`: one layer of a run.
- `/build-and-prove <note>`: an answer or follow-up for the Claude Code pane this chat started.

It only runs when you call it.

## What you get

A worktree under `~/development/worktrees` on the issue's branch (a plan with no issue gets a branch with no number, as in `feat/export-orders-csv`), with one commit per slice, every check green in the Sandbox. The branch is not pushed. Next to it, a proof folder at `~/.agents/artifacts/proof/<slug>/`, named like the plan file (`<owner>-<repo>-<n>`, or `<owner>-<repo>-chat-<words>`): the videos, the before and after screenshots, `proof.md`, the PR's `Proof` part, and `checks.txt`, the repo's checks it ran on the head commit in the Sandbox, so make-pr runs none of them on your Mac. [make-pr](../make-pr/) turns that into the PR.

On the way:

- **One Sandbox per run.** `scripts/box.sh` creates it, runs each command there, and makes it again from its Snapshot when it dies, so a run can outlast one Sandbox. Namespace deletes a Sandbox after 30 idle minutes on Linux and 10 on a Mac, where a minute costs ten times more, and after proofbox's 3-hour max life, which every Namespace plan allows. A new one takes 1 to 3 minutes, and your code stays on your Mac, so nothing is lost. The report says how many times it was made again. `up` shows what proofbox prints as it makes the Sandbox: the setup script's last lines when it fails, the Snapshot line when it reuses one. Each test is a `proofbox upload` of the changed files plus a `proofbox exec`.
- **A builder.** On Fable inside herdr, a Claude Code pane on Sonnet at high effort; on any other model, this chat. It follows the handoff rules for a local build.
- **A walker.** A Sonnet subagent that does each walk as a test user: it gets the walks and what it must see, never the code, records each video with proofbox, types one command per step and looks at the screen after each Enter, so a viewer can follow each step, and says what passed and what broke. A broken walk goes back to the builder when the app is wrong, or into the plan when the walk is wrong. At most three rounds.
- **Setup files.** On the first run for a repo it writes `~/.agents/proofbox/<owner>-<repo>/setup-<os>.sh` from the repo, with the tools its checks and its walks need, and an `app.env` with an empty line for each secret you fill in. Later runs reuse them. An optional `size` file there, one line such as `8x16`, sets the Sandbox size for that repo; without it proofbox's default applies.

It stops, with the Sandbox deleted and your commits kept, when proofbox is missing, a login is missing or expired (the login command goes to your clipboard), a Sandbox will not start, or the app will not start. Run it again on the same plan and it picks up at the first slice with no commit. The last message:

```
Built: #42 Export orders as CSV · feat/42-export-orders-csv · 4 commits
Checks: pnpm test, pnpm lint, pnpm build green on 1a2b3c4 in the Sandbox
Walks: 3 passed in round 2 · videos: 2 · built by: claude pane w4:p9M
Proof: ~/.agents/artifacts/proof/acme-shop-42
BUILT feat/42-export-orders-csv
```

## Needs

- [proofbox](https://github.com/linhvu0711/proofbox), installed and logged in to its Provider. Its own config, `~/.config/proofbox/config`, picks the Provider per OS. No Windows.
- `git`, and `gh` (signed in) for the issue.
- The walker's agent file, linked once into Claude Code: `ln -s "$PWD/skills/build-and-prove/agents/walker.md" ~/.claude/agents/walker.md`, run from this repo's root. Codex has no sub-agents, so the session walks under the same rules.
- The shared core files `../../shared-skill-core/facts.md`, `../../shared-skill-core/checkout.sh`, `../../shared-skill-core/pr-shape.md`, and the templates in `../../shared-skill-core/handoff/`.
- For a Claude Code pane (Fable only): herdr with this chat inside it (`HERDR_ENV=1`), the Claude Code CLI `claude`, signed in, and the helpers `herdr-wait` and `herdr-send` in `~/.claude/bin`. These two helpers are not in this repo.

## Fits with

- Builds the plan [plan-up](../plan-up/) writes, with the rules [handoff](../handoff/) renders for a local builder.
- Called by [ship](../ship/), which then runs [make-pr](../make-pr/) with the proof folder and [ready-pr](../ready-pr/).
- Uses [kickoff](../kickoff/)'s `equalize_columns.py` to even out pane widths.
- Why every command runs in the Sandbox, and why the walker never reads code: ADRs 0009 and 0010 in this repo.
