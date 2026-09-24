---
name: find-cc-session
description: "Find a past Claude Code session in the current project by what it was about and return its session ID. Works from Claude Code and from Codex. Fires on '/find-cc-session ...' in Claude Code, '$find-cc-session ...' in Codex, 'find the claude session where we fixed CI', 'which claude chat did I do X in'. Not for the current Claude Code session's own ID (that is `$CLAUDE_CODE_SESSION_ID`), not for loading a session whose ID is already known (that is load-cc), and not for Codex sessions (that is find-co-session)."
---

# find-cc-session

Claude Code keeps each session as a JSONL transcript under `~/.claude/projects/<encoded-cwd>/`. The script does the mechanical part: it lists the current project's sessions, scores their keyword overlap with the description, and prints the top candidates. You judge which one the user meant.

Sibling: **find-co-session** does the same for Codex CLI sessions. Both run in Claude Code and in Codex; only the load offer at the end differs.

## Steps

1. **Run the finder.**
   `python3 find_sessions.py "<description>"`
   No description: ask for one, or run `--all` to list recent sessions for the user to pick from. Another project: `--project-dir <path>`. `--help` lists the other flags.

2. **Judge the candidates.** The score is a keyword heuristic, so read each title, opening prompt, and snippet. A wide gap between #1 and #2 is one match. A tight cluster is an ambiguous description. A low top score that shares only incidental words is no match. In Claude Code, set the `← current session` line aside unless the description clearly names it; in Codex that line never appears.

3. **Act on the verdict.**
   - One match: `printf "%s" "<id>" | pbcopy`, then report the ID with its title, age, and prompt count on one line.
   - Several: list them (title, age, prompts, ID), ask which one, and copy the pick. A tie-breaker in the description ("the most recent") settles it without asking.
   - None: say so, show the closest one or two, and suggest a rephrase, `--all`, or a check that this is the right project folder.

Done when the ID is on the clipboard, or the user knows there is no match. After a copy, offer `/load-cc <id>` in Claude Code or `$load-cc <id>` in Codex; load only on request.
