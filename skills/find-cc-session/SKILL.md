---
name: find-cc-session
description: "Find a past Claude Code session in the current project by what it was about and return its session ID. Works from Claude Code and from Codex. Fires on '/find-cc-session ...' in Claude Code, '$find-cc-session ...' in Codex, 'find the claude session where we fixed CI', 'which claude chat did I do X in'. Not for the current Claude Code session's own ID (that is `$CLAUDE_CODE_SESSION_ID`), not for loading a session whose ID is already known (that is load-cc), and not for Codex sessions (that is find-co-session)."
---

# find-cc-session

Claude Code sessions are JSONL transcripts under `~/.claude/projects/<encoded-cwd>/`. The helper script does the deterministic part (list the current project's sessions, score keyword overlap against the description, print the top candidates). You do the fuzzy part. Read the candidates and judge which one the user meant.

Sibling: **find-co-session** does the same for Codex CLI sessions. Both run in Claude Code and in Codex; only step 3's load offer differs.

## Steps

1. **Run the finder.**
   `python3 find_sessions.py "<description>"`
   No description given: ask for one, or run `--all` to list recent sessions so the user can recognize it. Another project: `--project-dir <path>`. `--help` lists the rest.

2. **Judge the candidates.** The score is a keyword heuristic; read each title, opening prompt, and snippet. A wide gap between #1 and #2 means one match. A tight cluster means the description is ambiguous. A low top score that shares only incidental words means no match. In Claude Code, set the `← current session` line aside unless the description clearly names it. In Codex that line never appears.

3. **Act on the verdict.**
   - One match: `printf "%s" "<id>" | pbcopy`, then report the ID with its title, age, and prompt count on one line.
   - Several: list them (title, age, prompts, ID) and ask which one; copy the pick. A tie-breaker in the description ("the most recent") settles it without asking.
   - None: say so, show the closest one or two, and suggest a rephrase, `--all`, or a check that this is the right project folder.

Done when the ID is on the clipboard, or the user has been told there is no match. After copying, offer `/load-cc <id>` in Claude Code or `$load-cc <id>` in Codex; load only on request.
