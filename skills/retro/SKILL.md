---
name: retro
description: "Look back over coding sessions from every harness, and PRs no session touched, find where the agent struggled and what worked, and turn the patterns into shared fixes to the repo's agent setup. One session by default; a time range, session IDs, a topic, or an orchestrate run reads many."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

The user asked for a **retrospective**. You suggest changes to the repo's agent **environment** (checks, pointers, review rules, standards, skills, steering files, tools) so future runs go better for everyone on the team. You change no code and no file here: every finding comes from the record (session transcripts and GitHub), and the user picks what becomes an issue.

Words from `CONTEXT.md` § Retro: **evidence list**, **pattern**, **one-time problem**, **repeated correction**, **repeated manual work**, **worth sharing**, **setup map**, **touched PR**, **session adapter**.

## Steps

1. **Scope.** Read the user's words for four things. Hold them as flags for the scripts below.
   - **Sessions.** Nothing named: the current session alone. Session IDs: those, each as `--id <prefix>`. A window: `today` is `--since <today>`; `last N days` is `--since <today minus N-1 days>`; `since Monday` is `--since` that day; `from X to Y` is `--since X --until Y`; dates as `YYYY-MM-DD`. A topic ("the handoff sessions"): `--query "<topic>"`. `run <folder>`: an orchestrate run, § Run scope. A window and a topic mix.
   - **Where.** This project by default. "All projects": `--all-projects` in place of the roots.
   - **Sources.** Every harness that has sessions, and GitHub, unless the user names some. A harness name is the name of its adapter folder; `PRs` and `issues` name GitHub. Words like "only Claude Code sessions" keep that harness and drop GitHub.
   - **Repo.** `gh repo view --json nameWithOwner -q .nameWithOwner`.

   This project's roots: the main checkout (the first `worktree` line of `git worktree list --porcelain`), every other worktree it lists, and `${WORKTREES_ROOT:-$HOME/development/worktrees}/<owner>/<repo>`.

   A window or a source you cannot read stops the run (§ Unhappy states, Bad input). Done when you hold the session flags, the roots or `--all-projects`, the sources, and the repo.

2. **Find.** The current session alone: its ID is the harness's own (in Claude Code, `$CLAUDE_CODE_SESSION_ID`); find its row with the adapter of the harness you run in, `find --root <root> --id <id>`, and go to step 3. Otherwise ask which harnesses hold sessions:

   ```bash
   python3 ../../shared/sessions/scan.py --root <root> [--root <root>...] [--since D] [--until D]
   ```

   Then, for each `adapters` entry with `sessions` above 0 that the sources keep:

   ```bash
   python3 ../../shared/sessions/<harness>/adapter.py find --root <root>... [--since D] [--until D] [--query "<topic>"] [--id <prefix>...]
   ```

   A topic score is a keyword count, so read each title and drop the ones that do not match the topic, as `../find-cc-session/SKILL.md` step 2 judges. Leave out the session running this retro when its first prompt is the `/retro` call. A row with `unreadable` is listed as not read, with its reason. Each `unread` line from the scan goes to the report as it is.

   Done when every row is kept or dropped with a reason, and every scan line is held for the report.

3. **Render.** Make a scratch folder outside every page folder. For each kept session `n`, render its transcript and each helper log in its `subagents`:

   ```bash
   python3 ../../shared/sessions/<harness>/adapter.py extract <path> --max-result-chars 300 > <scratch>/<n>-main.md
   python3 ../../shared/sessions/<harness>/adapter.py extract <helper path> --max-result-chars 300 > <scratch>/<n>-helper-<k>.md
   ```

   Done when every kept session has its files, or a line saying why one could not render.

4. **GitHub.** Skip when the sources dropped GitHub. Find what no session in scope touched:

   ```bash
   python3 scripts/github.py list <owner/repo> --transcripts <scratch> --since D [--until D]
   ```

   A window-less scope (named IDs, the current session) uses the days its sessions span. Each `skipped` entry is a PR not read, with its reason, for the report. Then write each `read_prs` entry's bundle, and one bundle for all `read_issues`, into a second folder:

   ```bash
   python3 scripts/github.py pr <owner/repo> <n> > <github>/pr-<n>.md
   python3 scripts/github.py issues <owner/repo> <n>... > <github>/issues.md
   ```

   Count the readers: one per session, one per PR, one for the issues. More than 20: print `<s> sessions, <p> PRs, <i> issues: <r> readers. Say go.` and wait for `go`; any other answer narrows the scope, and you go back to step 1. Done when every untouched PR and issue has its bundle, and the count is 20 or less or the user said `go`.

5. **Read.** One reader per session, per PR, and one for the issues, per `references/reader.md`: up to ten readers in one message, the next ten after those return. Each returns one evidence list. A reader that fails or returns no `# Evidence list`: send it once more; still nothing, that item is **not read**. Done when every item has an evidence list or is marked not read.

6. **Setup map.** For each job, find the file in this repo that does it: agent steering, review rules, coding standards, skills, checks and CI, docs. Follow the links in `AGENTS.md` and `CLAUDE.md` first, then look in every place `../../shared/review/rule-sources.md` § fixed list names. A job with no file maps to `none`. Done when every job maps to a file or `none`.

7. **Patterns.** Read the evidence lists, never the transcripts or bundles. Group moments by the fix that would stop them: two moments are one pattern only when **one fix** stops both, and a pattern needs two or more sessions or PRs. A moment from one item that cost a lot (lost work, a wrong change shipped, many turns wasted) is a one-time problem; the rest stay out. The same correction from the user or a reviewer in two or more items is a repeated correction. The same steps done by hand in two or more items are repeated manual work. The same way of working that went well in two or more items, from the lists' `Worth sharing`, is a worth-sharing pattern.

   For each candidate, name its kind and its fix per § Kinds of finding, and the file it lands in from the setup map. A job mapped to `none` gets "add one" and the skill that writes it: `set-review-rules` for review rules, `set-coding-standards` for standards, `write-for-agents` for a skill or steering text. Before you propose a check, read the repo's own: its check scripts, hooks, CI workflow. A check that exists but is unwired or broken is the finding. A proposed check names the past mistake it would have failed on: the item, its `Where`, and the quote; a check with no such mistake goes. Every candidate cites items and quotes from the evidence lists; one you cannot trace goes. Order by cost to future runs, then pick the top one.

   Done when every moment, manual-steps line, and worth-sharing line in every evidence list is in a pattern, a one-time problem, or judged too small.

8. **Report.** No card left: the report is the line `Nothing worth changing`, then what was read (§ Read line), and the run ends. Otherwise build the report page per `references/pages.md`, show it, and ask the user to paste the line its Copy button gives (`issue 1 3 4`). A fix whose text is steering, a skill, or a rule follows `../write-for-agents/SKILL.md`. Wait.

9. **File.** For each picked card, in order, in the repo the card's fix lives in:
   - Say the card in chat: its title, items, quotes, fix, and where. Then invoke the `to-issue` skill with the Skill tool, with the card as the conversation's last word and its repo named.
   - `to-issue`'s gate stops: invoke the `capture` skill with the Skill tool, with the card's title, fix, and quotes as the seed.
   - Neither can create it (no GitHub repo, no access): the card stays as text, with the reason.

   Done when the chat holds one line per pick: `card 3 → #123 (to-issue)`, `card 4 → #124 seed (capture: <the gate's gap>)`, or `card 5 → not filed: <reason>`.

In Codex, readers are `explorer` sub-agents.

## Run scope

`/retro run <folder>`, as orchestrate starts it when a run is done. The folder holds the run's `state.json`; read `repo`, `path`, `started_at`, `set`, `removed`, and each `threads[].thread`.

- **Sessions.** `python3 ../../shared/sessions/t3/thread_session.py <thread>...` prints the harness and session behind each thread. Find each with that harness's adapter, `find --root <path> --since <started_at day> --id <session>`. An `error` row is a session not found, named in the report. The run's sessions are the scope: skip the scan, and keep its `unread` lines out.
- **GitHub.** `scripts/github.py list <repo> --transcripts <scratch> --issues <set minus removed>`.
- **No stop.** The run set the scope, so step 4 does not wait for `go`.

The rest of the steps run as written.

## Kinds of finding

Each kind names where its fix lands. The setup map decides the exact file. A fix lands only in files the repo shares with the team; a person's own files stay out.

- **Navigation**: the agent took long to find a file or fact. Fix: a navigation pointer from a file it already reads.
- **Automated check**: a mistake a tool could catch: lint rule, type, test, hook, CI job. A repo with no guardrail (no hook and no CI job running its checks) is a finding of its own.
- **Coding standards**: the reviewer missed a judgement call. Fix: a rule in the setup map's review rules file (via `set-review-rules`) or standards file (via `audit-coding-standards`). A mechanical rule (a fixed pattern, a banned API, an import shape, a file location) is an automated check instead.
- **Steering file**: the repo's `AGENTS.md` or `CLAUDE.md` is large. Fix: move its steering to standards or checks.
- **Tool economy**: a tool call was expensive for what it returned. Fix: streamline the tool or replace it.
- **No-op**: a steering line that changes nothing. Fix: delete it.
- **Information access**: the agent needed something it could not reach. Fix: widen its access, such as teeing a dev server log to a file or read-only access to a service.
- **Skill problem**: a skill's text led the agent wrong. Fix: a change to that skill, named by path.
- **Missed skill**: a skill should have run and did not: the task matched it, and the agent did the work another way or the user had to name the skill. Fix: that skill's `description`, so it names the task and the words of that moment. A skill with `disable-model-invocation: true` starts only when the user types it, so it is never a missed skill.
- **Repeated manual work**: the user did the same steps by hand in two or more items. Fix: a proposed new skill that runs those steps: its name, its `description`, and the steps, from the items. Look first for a skill that already does the job. One the agent can start on its own is a missed skill. One the user must type (`disable-model-invocation: true`) needs no new skill and no change: its card is a **tip** that names the skill and its command, so the user types it next time. A tip is never filed.
- **Repeated correction**: the same thing the user or a reviewer said in two or more items. Fix, in this order: delete the old code or the old way the agent keeps copying; then a check that fails; then a skill fix; a steering line last.
- **Worth sharing**: a way of working that went well in two or more items: a prompt, a sequence of steps, a review habit. Fix: the shared file that gives it to the team: a skill, a doc line, or a rule.

## Unhappy states

- **Error.** An item that cannot render or be read is listed as not read, with the reason. A T3 thread with no log is a session not found. A `stop:` line from `scripts/github.py`: read sessions only, and the report says GitHub was skipped and why.
- **Empty.** Nothing in scope: say what you searched (window, topic, roots or all projects, sources) and stop. Nothing passes the bar: `Nothing worth changing`, step 8.
- **Slow.** Many readers: after each batch of ten, one line, `read <k> of <n>`.
- **Bad input.** A window you cannot turn into dates, a source that is no adapter folder and not `PRs` or `issues`, or a run folder with no `state.json`: say what you could not read, give one example of each form (`today`, `last 3 days`, `from 2026-10-01 to 2026-10-05`, `run <folder>`, a harness name), and stop.
- **No permission.** `gh` not logged in or with no access to the repo: read sessions only, and the report gives `gh auth login`. A harness with data and no adapter: its scan line, `found <harness> sessions, cannot read them yet`.

## Read line

The report says how many sessions, PRs, and issues were read, names each item not read or read in part with the reason, each touched PR with the transcript that named it, and each scan line.

## Reference

### Implementation and review

Work goes through two stages. The implementing agent carries the most context pressure: it explores, writes code, and debugs. The reviewing agent gets a diff and little else. So a rule goes to review, where there is room to apply it, and steering files stay for navigation pointers.

### Files

- `CLAUDE.md` and `AGENTS.md` load into every session in the repo. Use them sparingly, mostly for navigation pointers.
- Review rules and coding standards files are read during review, not implementation.
- Docs are reference files that other files point to. Look for one before proposing a new one.
- Skills hold docs whose description earns a place in context, and commands the user types.
