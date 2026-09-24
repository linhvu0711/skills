---
name: find-co-session
description: "Find a past Codex CLI session in the current project by what it was about and return its session ID. Works from Claude Code and from Codex. Fires on '/find-co-session ...' in Claude Code, '$find-co-session ...' in Codex, 'find the codex session where we fixed CI', 'which codex chat did I do X in'. Not for loading a session whose ID is already known (that is load-co), and not for Claude Code sessions (that is find-cc-session)."
---

# find-co-session

Codex keeps each session as a rollout under `~/.codex/sessions/YYYY/MM/DD/`. The script does the mechanical part: it lists the sessions started in the current folder, scores their keyword overlap with the description, and prints the top candidates. You judge which one the user meant.

Sibling: **find-cc-session** does the same for Claude Code sessions. Both run in Claude Code and in Codex; only the load offer at the end differs.

## Steps

1. **Run the finder.**
   `python3 find_session.py "<description>"`
   Turn a relative date in the description into a flag first: "yesterday" is `--date yesterday`, "last week" is `--days 7`. No description: ask for one, or run `--all` to list recent sessions for the user to pick from. Another project: `--cwd <path>`; a parent folder: add `--include-subdirs`. `--help` lists the other flags. The first run in a project parses its rollouts once and caches them under `~/.cache/find-co-session/`, or `/tmp/find-co-session/` when the Codex sandbox makes the home cache read-only; later runs take under a second.

2. **Judge the candidates.** The score is a keyword heuristic, so read each opening prompt and snippet. A wide gap between #1 and #2 is one match. A tight cluster is an ambiguous description. A low top score that shares only incidental words is no match. `--show <id>` prints one candidate's user prompts, and only those, so it stays small. In Codex, the session you are in is a rollout too; set it aside unless the description clearly names it.

3. **Act on the verdict.**
   - One match: `printf "%s" "<id>" | pbcopy`, then report the ID with its opening prompt, age, and prompt count on one line.
   - Several: list them (opening prompt, age, prompts, ID), ask which one, and copy the pick. A tie-breaker in the description ("the most recent") settles it without asking.
   - None: say so, show the closest one or two, and suggest a rephrase, `--all`, `--include-subdirs`, or a check that this is the right project folder.

Done when the ID is on the clipboard, or the user knows there is no match. After a copy, offer `/load-co <id>` in Claude Code or `$load-co <id>` in Codex; load only on request.
