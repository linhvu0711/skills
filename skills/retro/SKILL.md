---
name: retro
description: "Look back over one coding session or many, find where the agent struggled, and turn the patterns into fixes to its environment. One session by default; a time range, session IDs, or a topic reads many."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

The user asked for a **retrospective**. You suggest changes to the coding agent's **environment** (checks, pointers, review rules, skills, steering files, tools) so future runs go better. You change no code and no file here: every finding comes from the sessions' own record, and the user picks what becomes an issue.

Words from `CONTEXT.md` § Retro: **struggle list**, **pattern**, **one-time problem**, **repeated correction**.

## Steps

1. **Scope.** Read the user's words for three things:
   - **Sessions.** Nothing named: the current session. Session IDs: those. A time range ("last 3 days", "since Monday", "this week"): turn it into a day count `N`, today counting as day 1. A topic ("the handoff sessions"): the finders' query. Range and topic mix.
   - **Where.** This project by default. "All projects": every project on this machine.
   - **Tools.** Claude Code and Codex, both, unless the user names one.

   This project's roots: the main checkout (the first `worktree` line of `git worktree list --porcelain`), every other worktree it lists, and `${WORKTREES_ROOT:-$HOME/development/worktrees}/<owner>/<repo>` when `gh repo view --json nameWithOwner -q .nameWithOwner` names the repo. Done when you hold the sessions rule, the roots or "all projects", and the tools.

2. **List.** The current session alone (in Claude Code its ID is `$CLAUDE_CODE_SESSION_ID`), or one named ID, skips to step 4 with that one session; its path is the extractor's `--list` line. Otherwise run each finder once, with `--json --limit 0`, the day count, and the topic as the query (no topic: `--all`):

   ```bash
   python3 ../../shared-skill-core/sessions/claude/find_sessions.py "<topic>" --project-dir <root> [--project-dir <root>...] --include-subdirs --days <N> --json --limit 0
   python3 ../../shared-skill-core/sessions/codex/find_session.py "<topic>" --cwd <root> [--cwd <root>...] --include-subdirs --interactive --active-days <N> --json --limit 0
   ```

   Both count a session by its last activity: Codex keeps a resumed session in the folder of the day it started, so its window flag is `--active-days`. "All projects": `--all-projects` in place of the roots. Named IDs: `--all` in the window, kept by id prefix. A topic score is a keyword count, so read each title and first prompt and drop the ones that do not match the topic, as `../find-cc-session/SKILL.md` step 2 judges. Leave out the session running this retro when its first prompt is the `/retro` call. Each row keeps: tool, id, date of last activity (`modified`, for both tools), project (`cwd`), title (Claude `title`, else the first prompt), `size`, `path`, and `subagents`, its helper agents' logs.

   - No session left: say what you searched (window, topic, roots or "all projects", tools) and stop.
   - One left: go to step 4 with it.

   Done when every row is kept or dropped with a reason.

3. **Pick.** Build the session list page per `references/pages.md` § Session list, publish it, give the link, and ask the user to paste the line its Copy button gives. Wait. `go` reads every row; `go, drop 2 5` reads all but those. Done when you hold the kept rows.

4. **Render.** Make a scratch folder. For each kept session `n`, render its transcript and each helper log in balanced mode:

   ```bash
   python3 ../../shared-skill-core/sessions/<claude|codex>/extract_session.py <path> --max-result-chars 300 > <scratch>/<n>-main.md
   python3 ../../shared-skill-core/sessions/<claude|codex>/extract_session.py <subagent path> --max-result-chars 300 > <scratch>/<n>-helper-<k>.md
   ```

   Done when every kept session has its files, or a line saying why one could not render.

5. **Read.** One reader per session, per `references/reader.md`: up to ten readers in one message, the next ten after those return. Each returns one struggle list. A reader that fails or returns no `# Struggle list`: send it once more; still nothing, the session is **not read**. Done when every session has a struggle list or is marked not read.

6. **Patterns.** Read the struggle lists, never the transcripts. Group moments by the fix that would stop them: two moments are one pattern only when **one fix** stops both, and a pattern needs two or more sessions. A moment in one session that cost a lot (lost work, a wrong change shipped, many turns wasted) is a one-time problem; the rest stay out. The same correction from the user in two or more sessions is a repeated correction, a pattern of its own.

   For each candidate, name its kind and where the fix goes, per § Kinds of finding. Before you propose a new check, read the repo's own: its check scripts, hooks, CI workflow. A check that exists but is unwired or broken is the finding. Every candidate cites sessions and quotes from the struggle lists; one you cannot trace to a moment goes. Order by cost to future runs, then pick the top one.

   Done when every moment in every struggle list is in a pattern, a one-time problem, or judged too small.

7. **Report.** Build the report page per `references/pages.md` § Report, publish it, give the link, and ask the user to paste the line its Copy button gives (`issue 1 3 4`). A fix whose text is steering, a skill, or a rule follows `../write-for-agents/SKILL.md`. Wait.

8. **File.** For each picked card, in order, in the repo the card's fix lives in:
   - Say the card in chat: its title, sessions, quotes, fix, and where. Then invoke the `to-issue` skill with the Skill tool, with the card as the conversation's last word and its repo named.
   - `to-issue`'s gate stops: invoke the `capture` skill with the Skill tool, with the card's title, fix, and quotes as the seed.
   - Neither can create it (no GitHub repo, no access): the card stays as text, with the reason.

   Done when the chat holds one line per pick: `card 3 → #123 (to-issue)`, `card 4 → #124 seed (capture: <the gate's gap>)`, or `card 5 → not filed: <reason>`.

In Codex there is no Artifact tool: show each page's content in chat as a numbered list, and the user answers with the same line. Readers are `explorer` sub-agents.

## Kinds of finding

Each kind names where its fix lands. The repo's own files decide the exact place.

- **Navigation**: the agent took long to find a file or fact. Fix: a navigation pointer from a file it already reads.
- **Automated check**: a mistake a tool could catch: lint rule, type, test, hook, CI job. A repo with no guardrail (no hook and no CI job running its checks) is a finding of its own.
- **Coding standards**: the reviewer missed a judgement call. Fix: a rule in `REVIEW.md` (via `set-review-rules`) or `CODING_STANDARDS.md` (via `audit-coding-standards`). A mechanical rule (a fixed pattern, a banned API, an import shape, a file location) is an automated check instead.
- **Steering file**: `AGENTS.md` or `CLAUDE.md`, in the repo or global, is large. Fix: move its steering to standards or checks.
- **Tool economy**: a tool call was expensive for what it returned. Fix: streamline the tool or replace it.
- **No-op**: a steering line that changes nothing. Fix: delete it.
- **Information access**: the agent needed something it could not reach. Fix: widen its access, such as teeing a dev server log to a file or read-only access to a service.
- **Skill problem**: a skill's text led the agent wrong. Fix: a change to that skill, named by path.
- **Repeated correction**: the same thing the user said in two or more sessions. Fix, in this order: a check that fails, a skill fix, a steering line last.

## Reference

### Implementation and review

Work goes through two stages. The implementing agent carries the most context pressure: it explores, writes code, and debugs. The reviewing agent gets a diff and little else. So a rule goes to review, where there is room to apply it, and steering files stay for navigation pointers.

### Files

- `CLAUDE.md` and `AGENTS.md` load into every session in the repo. Use them sparingly, mostly for navigation pointers.
- `REVIEW.md` and `CODING_STANDARDS.md` are read during review, not implementation.
- Docs are reference files that other files point to. Look for one before proposing a new one.
- Skills hold docs whose description earns a place in context, and commands the user types.
