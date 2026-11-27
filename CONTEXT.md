# Skills

Agent skills for Claude Code, Codex, and Antigravity.

## Skills

**Harness**:
The app that runs an agent: Claude Code, Codex, or Antigravity. T3 Code is not a harness. It is the app that starts harnesses, and it can start a subagent in any of them, or in Devin, which we use only for its models.
_Avoid_: provider, runtime, tool

**Shared core**:
The `shared/` folder: files that two or more skills read.
_Avoid_: common, utils, lib

**Skill agent**:
A subagent that one skill owns. Its file is in `skills/<name>/agents/` and names its tier and whether it is a checker. `link.sh` installs it into Claude Code and Codex. The explorer and the runner are not skill agents; the shared core owns them.
_Avoid_: subagent config, custom agent, agent file

**Tier**:
How much a subagent's job needs from a model, from 1 to 4: 1 follows clear steps, 2 judges real code against a list, 3 reasons through unclear problems, 4 makes open design calls. `shared/model-tiers.md` names each company's model at each tier.
_Avoid_: level, model size

**Try order**:
The companies a subagent tries, in order, for its tier, its checker line, and the main agent's harness. In T3 each try runs in turn until one starts; outside T3 only the last one runs, the main agent's own company.
_Avoid_: home models, fallback chain

**Checker**:
A subagent whose file says `checker: yes`: it judges work the main agent's model family made, such as a plan, the grill's decisions, or a PR. Its try order puts another company before the main agent's own.

**Explorer**:
The read-only subagent that fetches facts for a skill. The repo ships it, with the same name in every harness.
_Avoid_: reader, Explore

**Runner**:
The subagent that runs a command and judges the result by a pass rule. The repo ships it, with the same name in every harness.

**Plain subagent**:
A harness's default subagent, with no set job: `general-purpose` in Claude Code, `default` in Codex, `self` in Antigravity.
_Avoid_: general-purpose (in skill text)

**Harness table**:
The one table in the shared core that says how each harness does a step a skill names, such as starting a subagent or waiting on a long command.
_Avoid_: per-harness branch

**PR shape**:
The title and body that every pull request opened by these skills follows. It is kept once, in `shared/pr-shape.md`.
_Avoid_: PR template (that is a repo's own `.github/pull_request_template.md`)

**Demo**:
The PR part right after Summary that shows the change: before and after screenshots, then videos. Only a PR with screenshots or videos has one.
_Avoid_: media section

**Close-out**:
The grill's last step after `Grill done.`. It places the doc text the grill kept. When code follows, it files the issue or epic with the text under Docs to write; when that code changes a screen, it first suggests a prototype and waits for go. When no code follows, the docs are true now: it writes them and opens one docs PR. A caller can take the text back instead.
_Avoid_: wrap-up, finish

**Gap check**:
A second model's read of the decisions a grill settled, once, before the grill files an epic. It reports missing pieces and decisions that rest on a fact the code contradicts, and each one the chat has not answered becomes a question to the user.
_Avoid_: second opinion, grill review

**Docs to write**:
The section of an issue that holds doc text agreed on but not true yet: a glossary entry, an ADR, a README line, each with its file and full text. The PR whose code makes it true writes it. Until then other skills read it as decided, not built.
_Avoid_: pending docs, doc drafts

**Origin seed**:
The `seed` issue, or the cleared map, that the work grew from. It is rewritten in place into the ticket, the map, or the epic parent, so one number runs from the idea to the work. It is never closed for growing.
_Avoid_: parent seed, source issue

**Evidence label**:
How sure a stated fact is: Seen (read in a source, or run and observed), Inferred (follows from what was seen), Guess (no direct sign), Unknown (looked and found nothing). Guess and Unknown come only after tries to see it, and they name the tries.
_Avoid_: confidence level, certainty

**Candidate**:
One find in the improve-architecture report: a design change to one part of the code, shown as a card with a before and after diagram.
_Avoid_: finding, suggestion, row (a row is a find in the other two reports)

**Deepening**:
A candidate that merges shallow modules into one deep module, per `shared/codebase-design.md`.
_Avoid_: refactor (too broad), restructure

## Plans

**Review view**:
The first view of the plan page, made for a person who approves the plan: the change, the approach, the blast radius, the choices, the risks, how we know it works, and the scope. The slices, tests, and walks under it are for the executor.
_Avoid_: summary, overview

**Change map**:
The one diagram kind in the Review view. A box is a part with a job, named in the project's own words; an arrow is what moves between parts, or who asks whom; a gray area is the app or package the parts live in. A store box lists the tables, columns, or keys that change. Files are details of a box, never boxes.
_Avoid_: architecture diagram, component diagram, dependency graph

**File changes**:
The plan's list of every file it adds, edits, deletes, or moves, each with the slices that change it and a short note. The Review view draws it as a file tree under the Change map.
_Avoid_: file list, diff

**Claim**:
A sign that someone else is already on an issue: an open PR that closes or mentions it, an assignee, or a comment that takes the work. Plan-up asks before it plans a claimed issue.
_Avoid_: lock, reservation

**Plan check**:
A second model's read of a finished plan, with only the issue, the plan, and the code, before the user sees it. It has two parts that run side by side: a correctness check and a design check. Plan-up starts each part on a plan of size L or more when the plan shows that part's signs. The findings sit at the end of the plan file.
_Avoid_: plan review, critic, second opinion

**Not proved**:
A risk in the Review view that no probe has checked. Each risk names the `Proved` line that proves it, or says `not proved`. Reading the code does not prove a risk.
_Avoid_: unproven, unverified, assumed

**Lock test**:
A test that passes on the code before a refactor and must still pass after it. It pins today's behavior where no existing test does.
_Avoid_: pin test, characterization test, snapshot test

**Delete slice**:
A plan's first slice that deletes dead code in the area the ticket touches, alone, before any new code. Its tests are the old ones, passing before and after.
_Avoid_: cleanup slice, prep slice

**Type variant**:
The extra plan rules for a `fix`, `refactor`, or `perf` issue, on top of the plan that every type gets.
_Avoid_: playbook, mode

## Handoff

**Executor**:
The agent that does the work of a plan: Devin or Cursor in the cloud, through `/dispatch`, or local, through `/build-and-prove`.
_Avoid_: vendor, provider, backend

**Handoff ledger**:
The one list of handoff sessions, a row per session with its executor and issue. `/dispatch` reads it to send a follow-up to the executor that started the issue.
_Avoid_: session list, sessions file

## Local build

**Local machine**:
The machine the session runs on, where the worktree lives and the Builder edits. It can run macOS, Linux, or Windows. A proofbox Sandbox is never the local machine.
_Avoid_: Mac, laptop, host

**Coding**:
The part of `/build-and-prove` where the Builder writes the plan's slices, one at a time: a test that fails, the code that makes it pass, one commit. It runs on the local machine.
_Avoid_: the build (that word also names the Build command)

**Build command**:
The plan's `Build:` line, such as `pnpm build`, which turns the code into what the app runs. It is one of the Gates.
_Avoid_: the build (that word also names Coding)

**Gates**:
The checks a run proves on its head commit: the full suite, typecheck, lint, the Build command, and every command the repo's `AGENTS.md` or `CLAUDE.md` names as a check. After Coding, each Gate that the PR's CI does not run runs once, in the run's Sandbox for a plan with UI walks or on the local machine for a plan with no UI. The PR's CI runs the rest. Each line in `checks.txt` says where it ran, or that CI runs it.
_Avoid_: CI, final checks

**Builder**:
The agent in `/build-and-prove` that writes the code, the tests, and the commits: the session itself.
_Avoid_: implementer, coder

**Walker**:
The subagent that does a plan's UI walks on a proofbox Sandbox the way a test user would. It gets the walks and the pass rule for each, never reads or changes the code, and reports what passed and what broke, with videos and screenshots.
_Avoid_: tester, verifier, QA agent

**Sandbox fault**:
A failed walk whose screen shows the Sandbox, not the app, is wrong: a missing tool, or a mark drawn as other bytes for want of a UTF-8 locale. The setup script is fixed and the round runs again, and it does not count as a round.
_Avoid_: flaky walk, env failure

**Proof folder**:
What `/build-and-prove` leaves for `/make-pr`: the videos, the screenshots, `demo.md`, and `proof.md`. `/make-pr` makes the PR's Demo part from `demo.md` and its Proof part from `proof.md`.
_Avoid_: artifacts dir, media folder

**Follow-up**:
More work on a ticket after its first build: a change the user asks for, or a review fix after the PR is open. It redoes only what the change touches. `/build-and-prove` runs a local one; a rerun after a stop is a follow-up with no change. `/dispatch` sends a cloud one to the executor that started the issue.
_Avoid_: rework, second pass, iteration

## PRs

**Size**:
How many lines a change adds and removes, leaving out tests (unless it changes only tests), whitespace-only and blank-line changes, lockfiles, and `linguist-generated` files. XS is 0–9 lines, S 10–29, M 30–99, L 100–499, XL 500–999, XXL 1,000 or more. A script counts a PR's Size. A ticket's Size is a guess on the same scale, and no ticket is XXL.
_Avoid_: scope, effort, weight

**Readiness verdict**:
The one answer the readiness module gives for a PR: ready, waiting, or blocked, with the reason.
_Avoid_: PR status, ready state

## Review

**Risky finding**:
A review finding about security, privacy, login or permissions, money, a migration or schema, data loss, a race, or a step that breaks when run twice. The agent may fix one on its own, but it never rejects or delays one without asking.
_Avoid_: critical finding, sensitive finding

## Credit

**Upstream**:
The repo a copied or adapted skill came from, such as `mattpocock/skills`.
_Avoid_: source, origin

**Copy**:
A skill or file whose text is mostly the upstream's, word for word.
_Avoid_: fork, port

**Heavy adaptation**:
A skill that keeps the upstream's structure and some of its sentences, rewritten around this repo's skills.

**Idea only**:
A skill that takes the upstream's idea and none of its text.
_Avoid_: inspired by

## Checks

**Repo check**:
The GitHub Action that checks every pull request and every push to main: each skill has its README and license files, and every relative path points to a file that exists.
_Avoid_: CI lint

## CI audit

**Run part**:
One of the three parts of a CI job's time that improve-ci measures: waiting for a machine, setup (clone, install, caches), and work (the checks themselves).
_Avoid_: bucket, phase

**Target**:
The time a run part, or a whole PR result, should reach after a fix. improve-ci proposes it from measured runs and the repo's stack, and the user settles it in the grill. An issue's Done when names it.
_Avoid_: budget, goal

**Time limit**:
The run time past which a CI job fails, set per job from that job's own past runs, just above its slowest normal run.
_Avoid_: timeout, budget

**Skip list**:
The files a repo's PRs may change without running a given check, built per repo from which checks read which files. The skip happens inside the job, so a required check still reports.
_Avoid_: paths filter, ignore list

**Change detector**:
A test that fails on any change to the code it covers, even a correct one, so its fixes change only the test. improve-ci finds them in the fixes of merged PRs.
_Avoid_: brittle test

**Flaky run**:
A CI run that failed and then passed on the same commit, with no code change between.
_Avoid_: flake, intermittent failure

## Coding standards

**Level 1 source**:
The owner of a stack part: its official docs, official style guide, or the maintainers' repo. A coding-standards rule cites a level 1 source first.
_Avoid_: official source, primary source

**Level 2 source**:
A group that maintains a core part of the stack, or a source that the owner's docs link to, such as Vercel for Next.js and React patterns. When it disagrees with a level 1 source, level 1 wins unless the user picks otherwise.
_Avoid_: reputable source, trusted source

**Behind current practice**:
An audit finding that the code, or a rule, differs from what a level 1 or level 2 source says now. In middle and big repos the code still wins by default, and the user decides.
_Avoid_: outdated (that is a rule that names a tool, path, or version the repo no longer has)

**Sources table**:
The table in `docs/standards/sources.md` that lists each source a rule cites, and the main page searched for a stack part that gave no rule: stack part, name, link, version, and the date it was checked. The audit uses it to know which stack parts to check again.

**Standard**:
`CODING_STANDARDS.md` at the repo root, with the `docs/standards/` files it links to. It is the only rules file of a repo.
_Avoid_: style guide, conventions file, rule book

**One way for each job**:
The first area of the Standard: for each job the code does in many places, the one thing to use.
_Avoid_: preferred patterns, conventions

**Old way**:
In the Standard, a way to do a job that existing code still uses and new code must not. The mark names the ticket that removes the last uses, and it goes when they are gone.
_Avoid_: deprecated, legacy

**Scattered rules**:
Rules about code that live outside the Standard, in files such as `CONTRIBUTING.md`, `CLAUDE.md`, `.cursor/rules/`, or a `REVIEW.md` from before the Standard was the only rules file.
_Avoid_: legacy rules, old conventions

**Two ways**:
A row where the code does one job in two or more different ways. The same code in two places is a copy, which is a row of prune-codebase.
_Avoid_: inconsistency, duplication

## Clean codebase

**Row**:
One find in a clean-codebase report: one kind of problem, every place it shows, a count, and the agent's advice.
_Avoid_: finding, issue, item

**Still spreading**:
A row that has more places than at the last run. The report lists these rows first.
_Avoid_: trending, regression

**Known**:
A row or candidate that an open ticket already covers. The report shows it and asks nothing.
_Avoid_: duplicate, ignored

**Came back**:
A row whose ticket is closed and whose problem is in the code again.
_Avoid_: regression, reopened

**Keep and mark**:
The answer for a row that stays on purpose. A comment at the place, or one rule in the Standard, says why and links a ticket or an ADR.
_Avoid_: ignore, accepted debt, won't fix

**Change list**:
What a run does after the user's go: the tickets, the new rules, the lint settings, the skill's own edits (comment edits, scattered rules moved in, Sources table rows), and the ADRs.
_Avoid_: plan, summary

**Run table**:
The table in `docs/standards/runs.md` with one line for each clean-codebase run: the skill, the date, and the commit.
_Avoid_: run log, state file

**Hack**:
Code that goes around a problem and does not solve it: a check turned off, an unsafe cast, a wait that hides a timing problem, an error that is ignored.
_Avoid_: workaround, tech debt, smell

## Worktrees

**Safe to prune**:
A worktree that is clean, whose PR is merged on GitHub (or whose branch is in the default branch), whose branch tip is the PR's last commit, and that no live process has as its working folder. `clean-worktrees` removes it and its branch without asking. Any other worktree waits for the user.
_Avoid_: stale, old, abandoned

**Checkout resolver**:
The shared core module that finds, for an `owner/repo` and a branch, the main checkout, the worktree, and the default branch. It also finds the main checkout alone, lists a repo's worktrees, and names the GitHub repo of a checkout.
_Avoid_: repo finder, repo lookup

## Retro

**Evidence list**:
What one reader agent writes for one session or one PR: moments of trouble, repeated corrections, manual steps, and ways of working worth sharing, each with a quote and where it is.
_Avoid_: struggle list, summary, notes

**Pattern**:
Two or more moments, from two or more sessions or PRs, that one fix would stop. Moments that only look alike are not a pattern.
_Avoid_: trend, theme

**One-time problem**:
A moment from one session that is part of no pattern and cost a lot: lost work, a bad change that shipped, or many wasted turns. The report ranks it in its home repo's list with a `One-time` badge.
_Avoid_: outlier

**Repeated correction**:
The same thing a user or reviewer told the agent in two or more sessions or PRs. Its first fix is to delete the old code or the old way the agent keeps copying; then a check, a skill fix, and a steering line in `CLAUDE.md` or `AGENTS.md` last.
_Avoid_: feedback, nag

**Repeated manual work**:
The same steps the user did by hand, or spelled out one by one, in two or more sessions. Its fix is a new skill that runs those steps.
_Avoid_: chore, toil

**Worth sharing**:
A way of working that went well in two or more sessions or PRs, which a shared file would give the whole team.
_Avoid_: best practice, win

**Setup map**:
For one repo, the file that does each job for its agents (steering, coding standards, skills, checks and CI, docs), or none.
_Avoid_: config list

**Home repo**:
The repo that holds the file a retro card's fix changes. Retrospect finds it from that file's real place on disk and files the card there. An issue filed in any repo but the project's own leaves out the project's name.
_Avoid_: target repo, destination

**Open question**:
A problem retro's readers saw but no session found the cause of, so retrospect can name no fix. The report lists it in one line, not as a card.
_Avoid_: unknown card

**Touched PR**:
A PR that a session in scope names by number or URL. Retrospect does not read it.
_Avoid_: covered PR

**Session adapter**:
The scripts in `shared/sessions/<harness>/` that find and extract one harness's sessions. `shared/sessions/find_all.py` runs every adapter's find in one call.
_Avoid_: translator, parser

## Ship

**Ship mode**:
How far one /ship run takes a ticket: `review` stops after the plan for the user's `go`, `ready` stops at a ready-to-merge PR, `merge` merges it. The user forces it with an option; with none, the agent picks it from the plan.
_Avoid_: lane, path, mode (alone), auto

## Tasks

**Your step**:
A step of a task that only the user does: a password, a passkey or 2FA check, a payment, a Mac permission pop-up, or moving a secret.
_Avoid_: manual step, human step

**Ready thread**:
The thread orchestrate starts for a task issue when it gets the Task turn. It says what to have near you and how long it takes, then waits for go.
_Avoid_: draft thread, idle thread

## Orchestrator

**Orchestrator**:
The skill, and its T3 thread, that starts one thread for each issue in a Set when the issue has no open blocker and reaches a new Stage. It never builds or merges, and in the threads it starts it only sends `/ready-pr` to a thread whose PR has conflicts and settles a finished /grill or /triage thread whose issue moved on. The user handles each thread.
_Avoid_: factory, autopilot, scheduler

**Run**:
One orchestrator pass over one Set, from `/orchestrate` until every issue in the Set is closed or the user stops it. One live Run for each repo.
_Avoid_: session, job, batch

**Run repo**:
The repo a Run starts in. Its issues show as `#n`; issues from other repos show as `repo#n`.
_Avoid_: home repo (that is a retro card's repo), main repo

**Owner run**:
The Run that took an issue first. Another Run that holds the same issue only shows it and waits.
_Avoid_: first run, main run

**Set**:
The issues a Run must close. It is fixed at the start, from a list, an epic, or a rule such as "assigned to me". The user adds or removes issues. Issues the Run makes (sub-issues, follow-ups) join by themselves. Its issues can live in any repo.
_Avoid_: queue, backlog, scope

**Stage**:
Where an issue is, read from GitHub: unlabeled, seed, bug, ticket, too big (XXL), PR open, task, waiting, epic, or done. The Router turns a Stage into the skill a new thread starts with; at unlabeled, the user's answer to a Proposal picks it. One thread for each issue at each Stage.
_Avoid_: status, state, phase

**Task turn**:
The one slot on a Mac for a task issue that has a thread. Its Run holds it while the issue is open, until the issue gets `waiting` or is removed. Other task issues wait for it.
_Avoid_: lock, queue

**Check**:
One pass of the orchestrator's script. It reads the state file, GitHub, and T3, and prints what to start. The Watcher runs it every few minutes; the agent runs it when the Watcher wakes it or the user asks. A failed Check starts nothing.
_Avoid_: tick, poll, cycle

**Watcher**:
The background process of a Run that runs a Check every few minutes with no chat turn. It claims nothing, sends `/ready-pr` on a conflict, and wakes the orchestrator thread only when the agent must act: a thread to start, a proposal to make, a thread to settle, the Run done, or three failed Checks in a row.
_Avoid_: daemon, poller, timer

**Board**:
The local page that shows one Run: each issue of the Set as a card in a column by Stage, and who has the ball. It only reads.
_Avoid_: dashboard, kanban
