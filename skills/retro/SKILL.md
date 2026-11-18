---
name: retro
description: "Look back over coding sessions from every harness, and PRs no session touched, find where the agent struggled and what worked, and turn the patterns into shared fixes to the repo's agent setup. One session by default; a time range, session IDs, a topic, or an orchestrate run reads many."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

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

   A topic score counts words, not meaning, so read each title and drop the ones that do not match the topic, as `../find-cc-session/SKILL.md` step 2 judges. Leave out the session running this retro when its first prompt is the `/retro` call. A row with `unreadable` is listed as not read, with its reason. Each `unread` line from the scan goes to the report as it is.

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

7. **Patterns.** Read the evidence lists, never the transcripts or bundles. Group moments by the fix that would stop them: two moments are one pattern only when **one fix** stops both, and a pattern needs two or more sessions or PRs. A moment from one item is a one-time problem only when its `Cost` shows a real cost: lost work, a bad change that shipped, or many wasted turns; the rest stay out. A moment whose cause no item found, so no fix can be named, is an **open question**: one line for the report, never a card. The same correction from the user or a reviewer in two or more items is a repeated correction. The same steps done by hand in two or more items are repeated manual work. The same way of working that went well in two or more items, from the lists' `Worth sharing`, is a worth-sharing pattern.

   For each candidate, name its one kind, the one that best names its fix, as a repeated correction whose fix is a new lint rule is an automated check; then its fix per § Kinds of finding, and the file it lands in from the setup map. A job mapped to `none` gets "add one" and the skill that writes it: `set-review-rules` for review rules, `set-coding-standards` for standards, `write-for-agents` for a skill or steering text. Before you propose a check, read the repo's own: its check scripts, hooks, CI workflow. A check that exists but is unwired or broken is the finding. Every fix names the moment it would have stopped: the item, its `Where`, and the quote; a fix that stops no moment goes. Every candidate cites items and quotes from the evidence lists; one you cannot trace goes. Count each candidate: its moments (`times`), the items they came from out of all read (`3 of 12 items`), and its cost, the sum of its moments' `Cost` lines in their own units, as `14 tool calls, 3 user turns`. A worth-sharing card has a count and no cost.

   Done when every moment, manual-steps line, and worth-sharing line in every evidence list is in a pattern, a one-time problem, or judged too small.

8. **Home.** A card's **home** is the repo that holds the file its fix changes. Find it from the file's real place on disk, so a skill linked into this project from another repo has that repo as its home:

   ```bash
   python3 scripts/github.py home <path>...
   ```

   One path per file the cards' fixes name, from the setup map; a file the fix adds is named by the path it will have. Each row gives the card's `home` (`owner/name`) and `file`, its path in the home. A row with `unknown` gives the reason: the card stays in this project's group, marked `home unknown (<reason>)`. A fix with files in two homes becomes one card per home. A home is this project when it matches the step 1 repo, letters in any case. Group the cards by home: this project first, then each other home. Inside a home, one list, most important first, ranked by count and cost, each card with its kind. The first card is the top pick.

   Then check each home before its cards show. First take its name as GitHub keeps it, so a renamed repo or other letter case still matches: `gh repo view <home> --json nameWithOwner -q .nameWithOwner`. Then, card by card:

   ```bash
   python3 scripts/github.py latest <home> <file>
   gh issue list --repo <home> --state all --search "<2 or 3 words of the card's problem>" --limit 20 --json number,title,url,state,closedAt
   ```

   - `latest` gives the file on the home's default branch. The fix is in it already: drop the card, and `What was read` names it as `already fixed in <home>: <title>`. `missing`: the file is not there yet, so the fix is not either.
   - The search gives the home's issues for the words. An open one that is clearly this card's problem: the card shows `open #<n>`. A closed one whose problem shows again in an item dated after its `closedAt`: the card shows `the fix did not hold #<n>`.
   - A `stop:` line from `latest`, or a failed `gh` call: show the card, and `What was read` says `<home>: check skipped (<the error line>)`.

   Done when every card has a home or `home unknown`, and each home was checked or named as skipped.

9. **Report.** No card left, or every card dropped as already fixed: the report is the line `Nothing worth changing`, then what was read (§ Read line) with each dropped fix, and the run ends. Otherwise build the report page per `references/pages.md`, show it, print one line per card in chat, as `2. Add a check for unpushed worktrees · linhvu0711/skills · 5 times in 3 of 12 items · 9 user turns`, and ask in chat: `Which cards should become issues? Give their numbers, as 1 3 4, or none.` A fix whose text is steering, a skill, or a rule follows `../write-for-agents/SKILL.md`. Card text and the chat list use short sentences and plain words, and explain an inside name, such as a tool or a role, the first time it appears, as `to-issue (the skill that writes an issue)`. Wait.

10. **File.** `none` ends the run. A number no card has: name it and ask again. A tip's number: `card 5 → not filed: a tip`.
   - **Group.** Join the picks in each home into one issue per skill or part they change: the skill's folder, or else the file or folder the setup map names. A card marked `open #<n>` joins no group. Show the groups in chat, one line per home, as `linhvu0711/skills: plan-up (cards 2, 5), build-and-prove (3, 4, 6)`, then `card 7 → comment on #88` for each open-issue card, and wait. A change, as `move 4 to its own issue`, regroups, shows the groups again, and waits again. Nothing is filed before `ok`.
   - **Leave out the project.** In a home that is not this project, the issue or comment follows `../../shared/issue-rules.md` § Written for a stranger, Nothing of the source repo. Its words to leave out are this project's name, its `owner/name`, and each root from step 1.
   - **File.** For each group, in order: say its cards in chat (titles, items, quotes, fixes, where), then, in a home that is not this project, the line `File this in <home>. Leave out: <name>, <owner/name>, <each root>.`, and invoke `to-issue` with the Skill tool. Its gate stops: invoke `capture` with the Skill tool, with the group's titles, fixes, and quotes as the seed. It stops on size XL: say `<home> <part> is too big for one issue`, show the groups again, and wait for a split. It stops on an open issue that is the same work, filed since step 8: the group takes the Comment path on that issue.
   - **Comment.** A card marked `open #<n>`, or a group sent here: read that issue with `gh issue view <n> --repo <home> --comments`, and post only the quotes it does not hold yet, with `gh issue comment <n> --repo <home> --body-file <file>`.
   - `home unknown`: `card <n> → not filed: home unknown (<reason>)`.

   Done when the chat holds one line per pick: `cards 2, 5 → #123 (to-issue)`, `card 7 → comment on #88`, `card 4 → #124 seed (capture: <the gate's gap>)`, or `card 5 → not filed: <reason>`, the number taken from the URL to-issue or capture prints. A filing that fails for any other reason: `card <n> → not filed: <reason>`, the card's text stays in chat. The run ends there. Retro makes no code change, runs no `git pull`, no install, and no build, and starts no other skill's build; the issues carry the work.

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

- **Error.** An item that cannot render or be read is listed as not read, with the reason. A T3 thread with no log is a session not found. A `stop:` line from `scripts/github.py`: read sessions only, and the report says GitHub was skipped and why. A home whose check fails: the card still shows, and `What was read` names the home and says its check was skipped.
- **Empty.** Nothing in scope: say what you searched (window, topic, roots or all projects, sources) and stop. Nothing passes the bar, or every card is already fixed: `Nothing worth changing`, step 9.
- **Slow.** Many readers: after each batch of ten, one line, `read <k> of <n>`.
- **Bad input.** A window you cannot turn into dates, a source that is no adapter folder and not `PRs` or `issues`, or a run folder with no `state.json`: say what you could not read, give one example of each form (`today`, `last 3 days`, `from 2026-10-01 to 2026-10-05`, `run <folder>`, a harness name), and stop.
- **No permission.** `gh` not logged in or with no access to the repo: read sessions only, and the report gives `gh auth login`. A harness with data and no adapter: its scan line, `found <harness> sessions, cannot read them yet`.

## Read line

The report says how many sessions, PRs, and issues were read, names each item not read or read in part with the reason, each touched PR with the transcript that named it, each scan line, each fix dropped as already in its home, and each home whose check was skipped.

## Reference

### Implementation and review

Work goes through two stages. The implementing agent carries the most context pressure: it explores, writes code, and debugs. The reviewing agent gets a diff and little else. So a rule goes to review, where there is room to apply it, and steering files stay for navigation pointers.

### Files

- `CLAUDE.md` and `AGENTS.md` load into every session in the repo. Use them sparingly, mostly for navigation pointers.
- Review rules and coding standards files are read during review, not implementation.
- Docs are reference files that other files point to. Look for one before proposing a new one.
- Skills hold docs whose description earns a place in context, and commands the user types.
