# handoff-devin

Turns the plan that `/plan-up` wrote in this chat into a prompt, starts a Devin cloud session with it, and watches the session until the PR is ready.

## Use it when

You have a plan you said `ok` to and want Devin to build it in the cloud, with its own machine, browser, and screen recorder.

- `/handoff-devin <issue-url>`: the first prompt for one ticket.
- `/handoff-devin <epic-url>`: the first prompt for a run, one PR per ticket, stacked.
- `/handoff-devin <note>`: a follow-up or an answer for the session this chat started. A plan for a new layer on the open stack goes this way too.

It only runs when you call it.

## What you get

A prompt file holding the issue, the plan, and the build rules, sent to Devin as an attachment. It picks the machine (Linux unless the repo needs macOS or Windows) and creates any missing size labels. The prompt itself stays out of the chat:

```
Prompt: ~/.agents/artifacts/plan/prompt-acme-shop-42.md (412 lines)
Session started: https://app.devin.ai/sessions/… · linux
```

Then it watches. When Devin asks something, this chat answers from the plan and the repo, and only brings you the big decisions. When Devin finishes, it checks every review thread, reply, and filed issue, sends back anything missing, and reports the PR URL, its size, and the issues filed.

## Needs

- A Devin account with API access: `DEVIN_API_KEY` and `DEVIN_ORG_ID`, in the environment or as `export` lines in `~/.zshrc`. Optional `DEVIN_USER_ID` makes a service-user key start sessions as you.
- A `GH_TOKEN` secret in Devin's settings, holding your GitHub token, so Devin opens the PR and replies as you.
- `curl`, `jq`, `gh` (signed in), and `python3`.
- A plan from [plan-up](../plan-up/), and [to-issue](../to-issue/)'s `../to-issue/scripts/conventions.py` for the repo's size labels.
- The shared core files in `../../shared-skill-core/handoff/` (prompt and rules templates, `render.sh`), `../../shared-skill-core/plan-page.md`, and `../../shared-skill-core/issue-rules.md`.

## Fits with

- Reads the plan from [plan-up](../plan-up/).
- Sorts review questions the way [validate-pr-review](../validate-pr-review/) does, and files `fix later` findings with [capture](../capture/).
- Called by [ship](../ship/) for plans with UI walks and for stacks.
- [handoff-cursor](../handoff-cursor/) is its twin for Cursor; both use the same prompt and rules templates.
