# load-co-session

Pulls an earlier Codex CLI session into the chat you're in, as a short state brief you can pick up from.

## Use it when

You want to continue, or build on, work from a Codex session and you have its ID. `/load-co-session 019e631d` in Claude Code, `$load-co-session 019e631d` in Codex, or "what did codex do in that session?" A unique prefix of the ID is enough.

## What you get

A brief of the old session (goal, done, decisions, open, files, PRs and branches with their live state, next step), the last three things you typed there word for word, and a wait for your go. Say "go" and the agent starts on the next step. It skips what the brief says is done, and at the end it shows the goal working on the real thing.

```
Goal: add CSV export to the orders page
Done: export endpoint and its tests
Open: the button still has no loading state
PRs and branches: [merged #42] PR #42 · export endpoint
Next step: wire the button to the endpoint
```

Each PR and branch carries its live state from `gh` and `git`: merged, open, closed, a branch with no PR, or `[state unknown]` when `gh` cannot answer.

Codex encrypts its reasoning on disk, so nothing here can show what Codex was thinking. A full transcript counts the reasoning blocks and stops there.

## Needs

- `python3` (standard library only).
- The script in the shared core folder [`sessions/codex/`](../../shared/sessions/codex/), which retro uses too.
- A sub-agent to write the brief: the Explore agent in Claude Code, an `explorer` agent in Codex.
- The shared core file [`session-brief.md`](../../shared/session-brief.md), which holds the brief's shape.
- Codex rollouts under `~/.codex/sessions/` or `~/.codex/archived_sessions/`.
- `gh` and `git`, for the live state of each PR and branch.

## Fits with

- [find-co-session](../find-co-session/) finds the ID when you only remember what the session was about, then offers this skill.
- [load-cc-session](../load-cc-session/) does the same for Claude Code sessions.
