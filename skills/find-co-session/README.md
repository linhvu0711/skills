# find-co-session

Finds a past Codex CLI session in this project from a rough description, and puts its ID on your clipboard.

## Use it when

You remember what a Codex session was about but not its ID. `/find-co-session the one where we fixed CI` in Claude Code, `$find-co-session ...` in Codex, or "which codex chat did I write the migration in yesterday?"

## What you get

One line with the ID, opening prompt, age, and prompt count, and the ID already copied:

```
019e631d-...  "add the orders migration"  yesterday  9 prompts  (copied)
```

Words like "yesterday" or "last week" narrow the search by date. When a few sessions fit, it lists them and asks you to pick. When nothing fits, it says so and shows the closest ones. The first run in a project builds a cache, so later runs take under a second.

## Needs

- `python3` (standard library only).
- `pbcopy` for the clipboard, so macOS as written.
- Codex rollouts under `~/.codex/sessions/`. It runs from Claude Code or Codex.

## Fits with

- [load-co](../load-co/) loads the session it finds; the skill offers it after a match.
- [find-cc-session](../find-cc-session/) is the same search for Claude Code sessions.
