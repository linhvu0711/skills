# load-cc

Pulls an earlier Claude Code session into the chat you're in, as a short state brief you can pick up from.

## Use it when

You want to continue, or build on, work from another Claude Code session and you have its ID. `/load-cc 6090081d` in Claude Code, `$load-cc 6090081d` in Codex, or "pull that other chat in here". A unique prefix of the ID is enough.

## What you get

A brief of the old session, then a wait for your go:

```
Goal: move the settings page to the new form library
Done: fields and validation ported, tests green
Decisions: keep the old save endpoint for now
Open: the date picker still uses the old component
Files: src/settings/Form.tsx, src/settings/schema.ts
Next step: port the date picker
```

The last three things you typed in that session come along word for word. Say "go" and the agent starts on the next step. Ask for the whole transcript and you get that instead, trimmed to fit.

## Needs

- `python3` (standard library only).
- A sub-agent to write the brief: the Explore agent in Claude Code, an `explorer` agent in Codex.
- The shared core file [`session-brief.md`](../../shared-skill-core/session-brief.md), which holds the brief's shape.
- Claude Code transcripts under `~/.claude/projects/`.

## Fits with

- [find-cc-session](../find-cc-session/) finds the ID when you only remember what the session was about, then offers this skill.
- [load-co](../load-co/) does the same for Codex sessions.
