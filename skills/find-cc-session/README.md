# find-cc-session

Finds a past Claude Code session in this project from a rough description, and puts its ID on your clipboard.

## Use it when

You remember what a session was about but not its ID. `/find-cc-session the one where we fixed CI` in Claude Code, `$find-cc-session ...` in Codex, or "which claude chat did I set up the release script in?"

## What you get

One line with the ID, title, age, and prompt count, and the ID already copied:

```
3f9c21ab-...  "fix the flaky CI job"  2 days ago  14 prompts  (copied)
```

When a few sessions fit, it lists them and asks you to pick. When nothing fits, it says so and shows the closest ones. It never loads the session unless you ask.

## Needs

- `python3` (standard library only).
- `pbcopy` for the clipboard, so macOS as written.
- Claude Code transcripts under `~/.claude/projects/`. It runs from Claude Code or Codex.

## Fits with

- [load-cc](../load-cc/) loads the session it finds; the skill offers it after a match.
- [find-co-session](../find-co-session/) is the same search for Codex sessions.
