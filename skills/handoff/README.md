# handoff

Turns the plan that `/plan-up` wrote in this chat into a prompt, starts a Devin cloud session or a Cursor cloud agent with it, and watches it until the PR is ready.

## Use it when

You have a plan you said `ok` to and want a cloud agent to build it, with its own machine, browser, and screen recorder.

- `/handoff [devin|cursor] <issue-url>`: the first prompt for one ticket. No URL: the plan this chat holds. A plan with no issue (plan-up's chat plan) stops here: a cloud session needs an issue, so make one with [to-issue](../to-issue/) first.
- `/handoff [devin|cursor] <epic-url>`: the first prompt for a run, one PR per ticket, stacked.
- `/handoff [devin|cursor] <note>`: a follow-up or an answer for the session on this chat's issue. A plan for a new layer on the open stack goes this way too, with the facts its probes proved.
- `--model <id>` picks the Cursor model.

With no executor named, a follow-up goes to the executor that started the issue, and a new issue goes to Devin. An issue that already has a session asks you first: send the plan to that session, or start a new one. It only runs when you call it.

## What you get

A prompt file holding the issue, the plan, and the build rules. Devin gets it as an attachment, on a machine picked for the repo (Linux unless it needs macOS or Windows, whatever your local machine runs). Cursor gets it whole as the agent's prompt, and the agent commits as you and opens the PR on the branch the plan names. Missing size labels are created; a size-label bot in the base branch's workflows, whatever branch your checkout is on, owns them instead. The prompt itself stays out of the chat:

```
Prompt: ~/.agents/artifacts/plan/prompt-acme-shop-42.md (412 lines)
Session started: https://app.devin.ai/sessions/… · devin · linux
```

The build rules make the agent ask two things of each test before it commits: would it fail if the code returned the wrong value, and would it fail if every function the test imports returned `undefined`. A fix's first test must also fail before the change, on its assertion and for the bug's reason, not on a missing name. When the same red stays after two fixes, the agent writes down the cause it believes and tests that belief before a third fix; a belief it cannot test comes to you as a question. Two surprises of the same kind make it stop and ask, since the plan's design may be wrong. Its code comments say why, never what the line does, and it checks data at the edge where it comes in, not again inside the code.

The PR shows each screen the change touches, next to the old screen when the change alters one that exists already, plus a video of each walk, recorded at real speed and checked for length before it is attached.

Then it watches. When the agent asks something, this chat answers from the plan and the repo, and only brings you the big decisions. Cursor has no "waiting for you" state, so a run that ends with a question is treated as one. When the agent finishes, it checks every review thread, reply, and filed issue, sends back anything missing, and reports the PR URL, its size, and the issues filed.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

A `perf` PR proves its speed line with one Proof row: the metric and unit, `before → after`, the run count, and the command, plus the issue's Baseline when the base median falls outside its spread.

On a `perf` plan the cloud executor runs the plan's command in turns on the base and the head, by the benchmark checklist its rules carry, and writes `before → after` in the Proof; a review fix to the measured code measures again.

## Needs

- For Devin: an account with API access, `DEVIN_API_KEY` and `DEVIN_ORG_ID`, in the environment or as `export` lines in `~/.zshrc`. Optional `DEVIN_USER_ID` makes a service-user key start sessions as you. A `GH_TOKEN` secret in Devin's settings, holding your GitHub token, so Devin opens the PR and replies as you.
- For Cursor: cloud agents and an API key in `CURSOR_API_KEY` (environment or `~/.zshrc`), the repo connected to Cursor, and a `GH_TOKEN` secret in Cursor's Cloud Agents settings with `repo` scope. Without it the agent can push but cannot open the PR.
- `curl`, `jq`, `gh` (signed in), `git`, and `python3`.
- A plan from [plan-up](../plan-up/), and [to-issue](../to-issue/)'s `../to-issue/scripts/conventions.py` for the repo's size labels.
- The shared core files in `../../shared-skill-core/handoff/` (prompt and rules templates, `render.sh`), `../../shared-skill-core/plan-page.md`, `../../shared-skill-core/issue-rules.md`, and `../../shared-skill-core/benchmark.md`, which the rules paste into a cloud prompt for a perf plan.

## Fits with

- Reads the plan from [plan-up](../plan-up/).
- Sorts review questions the way [validate-pr-review](../validate-pr-review/) does, and files `fix later` findings with [capture](../capture/).
- Called by [ship](../ship/) when the command names `devin` or `cursor`, or a Windows plan goes to Devin.
- Shares its prompt and rules templates with [build-and-prove](../build-and-prove/), which renders them for the local builder.
- Its module, `scripts/handoff.sh`, keeps one ledger of sessions for both executors; a repo that requires verified commit signatures goes to Devin.

## Credits

The `undefined` test question and the root-cause rules (a tested belief before a third fix, a stop on two surprises of one kind, data checked at its edge) take ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

The perf part takes an idea from the `benchmark-checklist` skill in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
