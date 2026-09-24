# handoff-cursor

Turns the plan that `/plan-up` wrote in this chat into a prompt, starts a Cursor cloud agent with it, and watches the agent until the PR is ready.

## Use it when

You have a plan you said `ok` to and want a Cursor cloud agent to build it instead of Devin.

- `/handoff-cursor <issue-url> [--model <id>]`: the first prompt for one ticket.
- `/handoff-cursor <epic-url> [--model <id>]`: the first prompt for a run, one PR per ticket, stacked.
- `/handoff-cursor <note>`: a follow-up or an answer for the agent this chat started, including a new layer on its stack.

It only runs when you call it.

## What you get

A prompt file holding the issue, the plan, and the build rules, sent whole as the agent's prompt. The agent opens the PR itself, on the branch the plan names, as you. The prompt stays out of the chat:

```
Prompt: ~/.agents/artifacts/plan/prompt-acme-shop-42.md (412 lines)
Agent started: https://cursor.com/agents/bc-…
```

Then it watches. Cursor has no "waiting for you" state, so a run that ends with a question is treated as one: this chat answers from the plan and the repo, and only brings you the big decisions. When the agent finishes, it checks every review thread, reply, and filed issue, sends back anything missing, and reports the PR URL, its size, and the issues filed.

## Needs

- A Cursor account with cloud agents and an API key in `CURSOR_API_KEY` (environment or `~/.zshrc`).
- A `GH_TOKEN` secret in Cursor's Cloud Agents settings, holding your GitHub token with `repo` scope. Without it the agent can push but cannot open the PR.
- `curl`, `jq`, `gh` (signed in), `git`, and `python3`.
- A plan from [plan-up](../plan-up/), and [to-issue](../to-issue/)'s `../to-issue/scripts/conventions.py` for the repo's size labels.
- The shared core files in `../../shared-skill-core/handoff/` (prompt and rules templates, `render.sh`), `../../shared-skill-core/plan-page.md`, and `../../shared-skill-core/issue-rules.md`.

## Fits with

- Reads the plan from [plan-up](../plan-up/).
- Sorts review questions the way [validate-pr-review](../validate-pr-review/) does, and files `fix later` findings with [capture](../capture/).
- The Cursor twin of [handoff-devin](../handoff-devin/): same plan, same prompt shape, same steps. A repo that requires verified commit signatures goes to handoff-devin instead.
