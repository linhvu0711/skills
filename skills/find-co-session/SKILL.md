---
name: find-co-session
description: "Find a past Codex CLI session in the current project by what it was about and return its session ID. Works from Claude Code and from Codex. Fires on '/find-co-session ...' in Claude Code, '$find-co-session ...' in Codex, 'find the codex session where we fixed CI', 'which codex chat did I do X in'. Not for loading a session whose ID is already known (that is load-co), and not for Claude Code sessions (that is find-cc-session)."
---

# find-co-session

Codex sessions are rollouts under `~/.codex/sessions/YYYY/MM/DD/`. The helper script does the deterministic part (list the sessions started in the current folder, score keyword overlap against the description, print the top candidates). You do the fuzzy part. Read the candidates and judge which one the user meant.

Sibling: **find-cc-session** does the same for Claude Code sessions. Both run in Claude Code and in Codex; only step 3's load offer differs.

## Steps

1. **Run the finder.**
   `python3 find_session.py "<description>"`
   Turn a relative date in the description into a flag first ("yesterday" is `--date yesterday`, "last week" is `--days 7`). No description given: ask for one, or run `--all` to list recent sessions so the user can recognize it. Another project: `--cwd <path>`; a parent folder with `--include-subdirs`. `--help` lists the rest. The first run for a project parses its rollouts once and caches them under `~/.cache/find-co-session/`, or `/tmp/find-co-session/` when the Codex sandbox keeps the home cache read-only; later runs take well under a second.

2. **Judge the candidates.** The score is a keyword heuristic; read each opening prompt and snippet. A wide gap between #1 and #2 means one match. A tight cluster means the description is ambiguous. A low top score that shares only incidental words means no match. To see a candidate's full prompt list, run `--show <id>`; that prints only the user's prompts, so it stays small. In Codex, the session you are in right now is also a rollout; set it aside unless the description clearly names it.

3. **Act on the verdict.**
   - One match: `printf "%s" "<id>" | pbcopy`, then report the ID with its opening prompt, age, and prompt count on one line.
   - Several: list them (opening prompt, age, prompts, ID) and ask which one; copy the pick. A tie-breaker in the description ("the most recent") settles it without asking.
   - None: say so, show the closest one or two, and suggest a rephrase, `--all`, `--include-subdirs`, or a check that this is the right project folder.

Done when the ID is on the clipboard, or the user has been told there is no match. After copying, offer `/load-co <id>` in Claude Code or `$load-co <id>` in Codex; load only on request.
