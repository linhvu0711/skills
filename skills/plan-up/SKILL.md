---
name: plan-up
description: "Turn one ready GitHub issue, a run of epic tickets, a set of plain tickets, a whole epic, stacked as PRs, or work this chat agreed on with no issue, into a plan an executor can follow cold: seams, tests, slices, docs, UI walks, video scripts. Settles doubts by reading and by small probes, and leaves the repo as it was. Ends with the plan as a local HTML page open in the browser, a short summary in chat, and waits for ok, then /handoff."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Read `references/plan.md` first: the plan shape, how each block is
filled, and the done rule. Read `references/executor.md` too: what the
executor has and how it works a plan, so the plan fits it. At step 8,
read `../../shared-skill-core/plan-page.md`: where the plan is written
and how it is shown. At step 4, read `references/probes.md` before the
first probe. This file is the order of operations.

You plan; you do not build, and the repo is left as you found it. Facts
come from reading, and from a probe when reading leaves a doubt the plan
hangs on. Big forks go to the user. Everything else you decide and write
down.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, `SEARCH=on` for outside facts.

## Six forms

- `/plan-up <issue-url>`: one ticket, one PR. Base is the default branch.
- `/plan-up <epic-url> #12 #14 #15`: a **run**. The epic is a graph; a run
  is one path through it, landed as a stack of PRs, one ticket per
  **layer**, in the order given. The user names the tickets and owns
  what is taken; you check only the edges. Base is the default branch.
- `/plan-up <issue-url> #14 #15`: a **set**. Plain tickets with no shared
  parent, the first URL being the first ticket. A set is a run without a
  parent: every rule below for a run applies, and the parent steps are
  skipped. The first issue having no sub-issues is what makes it a set.
- `/plan-up <epic-url>`: the **whole epic** as one run. The tickets are
  every open sub-issue, in the order the parent body lists them: phase
  by phase, and inside a phase top to bottom. Closed tickets are skipped.
  From there it is a run.
- `/plan-up <issue-url> on <pr-url>`: one ticket as a new layer on top of an
  open stack. Base is that PR's head branch.
- `/plan-up`, no URL, words after it or none: a **chat plan**. The work
  this chat agreed on, with no issue: one ticket, one PR. Base is the
  default branch. The words, when given, say which part of the chat to
  plan. Step 2 § Chat plan takes the place of the issue.

## Steps

1. **Base copy.** The base: the default branch from
   `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, or
   the `on` PR's head branch from `gh pr view <n> --json headRefName`.
   The checkout you start in can be on any branch, with edits or not.
   Note its `git status --porcelain` and `git worktree list`; the run
   leaves both as it found them. Then:

   ```bash
   bash scripts/base-copy.sh <base>
   ```

   It fetches `origin/<base>` and adds a detached worktree of it, with
   its submodules, in a temp folder. `stop:` on stderr: show it, stop. Hold `BASE_WT` and
   `BASE_SHA` from its line. Every repo fact comes from `BASE_WT`: each
   Explore brief names it as the folder to read, every command that
   reads the code runs there, and a `file:line` is a line there, written
   from the repo root. Nothing is written in it. The checkout you start
   in is never read for facts and never changed.

   The copy lives until the run ends, by `ok` or by any stop. Then
   `bash scripts/base-copy.sh --remove <BASE_WT>`.

   Then prune old plans: `bash scripts/prune.sh`.
   It deletes the files of every plan whose issues are all closed. Its
   result never stops the run. Chat gets its last line only when it
   pruned something or printed a `stray` line; name the strays.

2. **Read the issue.** `gh issue view <n> --json number,title,body,labels,comments`.
   Read the comments too; a later comment can change a line. Carrying
   `handoff-ready`: the **short path**, `plan.md` § Handoff-ready. The
   Steps are trusted. Step 4 asks only what that section lists, step 5
   closes only the issue's `Open` lines, steps 6 to 8 run as written.

   A run: read the parent and every ticket, each with its comments, by
   the command above. A set: no parent, read every ticket the same way,
   first URL first. A bare epic URL: list the
   tickets first, `gh issue view <P> --json subIssues -q '.subIssues.nodes[] | select(.state == "OPEN") | .number'`,
   and put them in the parent body's order (the `## Phases` tables, top
   to bottom). Say the list before you go on, so the user sees what the
   run holds.

   A ticket labelled `manual` is a `task`: human work in a platform, per
   the rules file § Task body. It is never planned. One named alone: say
   `This is yours, not an agent's.` and stop. Open tasks in an epic or a
   run: list them first, number and title, then ask in one line whether
   to plan the tickets they do not block, or wait. Plan only on a yes,
   with the tasks and the tickets they block left out.

   Walk the order: each
   ticket's `Blocked by` is closed, or earlier in this run. A ticket that
   fails names the pair, stop. A `handoff-ready` ticket in a run takes
   the short path too: its Steps become the layer's slices per `plan.md`
   § Handoff-ready, and its facts round asks only what that section lists.

   **Claims.** Check whether someone is already on a ticket before you
   plan it. Run `python3 scripts/claims.py <owner/repo> <n>...` once,
   with every ticket this run plans; the `manual` tasks and the tickets
   they block are already out. It prints one line per open PR that
   closes or mentions a ticket, and per assignee who is not you. Then
   read each ticket's comments, read above, for a claim: a comment that
   says its author is taking or doing the work ("I'll take this",
   "working on it"), by someone other than you (`gh api user -q .login`),
   and not given back by a later comment from that author or from you.
   Your own assignment and comments are not claims; an open PR is,
   whoever opened it.

   No claim: say nothing and go on. Any claim: one message lists each
   claimed ticket, number and title, and under it each claim: a PR as
   `PR #70 Add the claim check · @bob · <url>`, an assignee as
   `assigned to @dave`, a comment quoted whole with `@<author>`. Then
   one question for all of them, in the format of
   `../../shared-skill-core/grilling.md`. A PR named: `A` review their
   PR instead (pick: their code exists), `B` build anyway, `C` stop. No
   PR named: `A` stop (pick: ask them first), `B` build anyway. Wait;
   nothing is planned before the answer. Review: print one
   `/review-pr <url>` line per named PR, remove the base copy, and stop.
   Stop: remove the base copy and stop. Build anyway: go on.

   `claims.py` exits 1, or `gh api user` fails: say
   `Could not check who is on #<n>: <its error line>.`, ask in one line
   whether to go on, and wait. Yes: go on. No: remove the base copy and
   stop.

   **Chat plan.** No issue to read: write the **brief** from the chat
   instead, per `../../shared-skill-core/issue-rules.md`: a `Title`
   (§ Title, the repo's style), a `Task` in one to three lines, the
   `Done when` lines (§ Done when), the `Known` and `Open` lines of
   § Context, and a size (§ Size). A chat plan has no Steps and takes
   no short path, whatever its size. The facts are only what the chat
   said or ran; nothing is made up to fill a line. Its slug is picked
   free, per `../../shared-skill-core/plan-page.md` § Files, before
   step 8 writes a file. From here on, the brief stands for the issue:
   its `Done when` lines, `Known` lines, and `Open` lines are read as an
   issue's are. Print it in chat in this shape and go on, with no wait:

   ```
   Brief: [feat] Export orders as CSV · size/M
   Task: staff can download the orders list as a CSV file
   Done when:
   - the Export menu offers CSV next to JSON
   - an order note with a newline stays in one CSV field
   ```

   A chat plan has no `manual` label, no `Blocked by`, and no claim
   to check: skip all three.

3. **Gate.** Apply `## Readiness gate` from
   `../../shared-skill-core/issue-rules.md` to the issue
   text, each ticket of a run on its own; to a chat plan's brief, and
   its gaps name `/grill` only. Pass: continue. Fail: name the
   ticket, list the gaps, each as the question that closes it, name
   `/grill` or `/triage`, stop. Nothing is planned.

4. **Facts.** Round 1 is one message, one Explore agent per concern, and
   in a run per ticket and concern:
   - the code each Done-when line touches, with tests, and every caller
     with what it assumes: the shape it reads, the error it expects, the
     order it relies on;
   - what the repo already holds that does the job, or part of it: a
     helper, a service, a component, a type, a fixture, a script; where
     each lives, who calls it, how far it reaches. The plan extends
     these before it adds, per `plan.md` § Slices;
   - how the repo runs test, typecheck, lint, build, and the app, read
     from CI config, package scripts, and README;
   - the nearest existing test at each candidate seam, and how the repo
     mocks its borders;
   - when any line is on a screen: the UI kind and how it is opened,
     the mockup the issue links, and the repo's look rules: `DESIGN.md`,
     tokens, the shared component folder, the nearest existing screen,
     and, for a screen that exists on the base, what it shows there
     now, for the walk's `Before` line;
   - the repo's own words and code rules, wherever they live:
     `CONTEXT.md`, `CODING_STANDARDS.md`, `CONTRIBUTING.md`,
     `CONVENTIONS.md`, `STYLE*.md`, `docs/**`, ADRs, `AGENTS.md`,
     `CLAUDE.md`, `.cursor/rules/**`, `.editorconfig`, lint and formatter
     configs; and where no file rules, the shape the code keeps: names,
     layout, errors, logging, tests. The plan's names and every `Change`
     follow them;
   - the parts around each seam the work touches, for the Change map:
     each part's job in the repo's words (`CONTEXT.md`, then the code),
     who asks whom, what data moves between them, which app or package
     holds each, and the files behind each part;
   - each Open line in the issue's Context, as its own ask;
   - the docs for each library the work leans on, `SEARCH=on`;
   - the docs that describe what each Done-when line changes: `README`,
     `docs/**`, guides, `CHANGELOG`, ADRs, API docs, `--help` text,
     `.env.example`, and the rules files above. The plan updates each
     one in the slice that makes it stale, per `plan.md` § Slices.

   Known lines in the issue's Context are facts in hand, proved by a run.
   Take them as read. Ask for nothing a Known line settles. In a run, a
   seam that an earlier layer creates is not in the repo; it is in that
   layer's plan, and a later layer points there (see `plan.md` § Run).

   A round ends when every ask came back, or came back "not found". You
   hold the picture: run another round for whatever it still lacks.

   **Probes.** A doubt that reading leaves, and the plan hangs on, is
   run, per `references/probes.md`: does the tool do it, what does the
   API return, where is the limit. Probe only what changes the plan;
   never to be thorough. Probes fan out like Explore agents, one
   sub-agent each, in one message, beside any round still open. A free
   probe runs without asking; one that costs money, needs a credential,
   or touches anything shared waits for a yes. Each answer is a
   `Proved` line. A doc a probe finds wrong or missing joins the docs
   the plan updates.

   A gap that neither reading nor a probe can close becomes a question.

5. **Forks.** Sort every choice the facts leave open by two tests:
   - the right pick needs a fact the repo does not hold: data size,
     traffic, who else calls this, what it may cost, what the user meant.
     A Known line that holds the fact settles this test;
   - a wrong pick is hard to undo: it ships to data or callers you cannot
     see, or the next issue copies it.

   Either holds: **big fork**. Ask the user, one question per message, in
   the question format of
   `../../shared-skill-core/grilling.md`, each option with
   the `file:line` behind it. Wait. Big forks look like:
   a schema or stored data, a public API, auth, input a user controls,
   a secret, data that leaves the system,
   a pattern new to the repo (first queue, cache, job), a move
   of work between layers, a choice that scales with size or load, a
   Done-when line that reads two ways.

   **A new dependency is a big fork every time.** The two tests do not
   apply; do not reason it down to a small fork. A dependency is any
   package, library, tool, or outside service the repo does not hold
   today: a new line in `package.json`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `Gemfile`, a lockfile, a Dockerfile, a CI config, or a
   new SDK and API key. A version bump of one already there counts too.
   Ask before the plan names it. The question holds at least two
   options: the dependency, with the docs fact from round 1, or the
   `Proved` line from its probe, that says it does the job; and the nearest thing the repo already has, with
   its `file:line` and the line that keeps it from serving, or hand-written
   code when the repo has nothing. Either can be `A`, by `grilling.md`
   § Your pick. Wait. The answer goes under `Decided`,
   marked `(user)`. A plan that adds a dependency the user did not pick
   is not done.

   Neither holds: **small fork**. The repo shows the answer. Decide,
   write it under `Decided` with the `file:line` that settles it. Code
   shape, which seam to test at, and extend-or-add (`plan.md` § Slices)
   are small forks.

   A probe can settle either test. A big fork asked after a probe carries
   its `Proved` line in the option it backs.

   Every Open line from the issue closes here, by a fact or by a question.
   None survives into the plan.

6. **Write the plan** per `plan.md`. Proof table first, one row per
   Done-when line. Then the slices, one per test, in tracer-bullet order:
   the thinnest path end to end first, each next slice widening it, each
   with the `Docs` lines its change makes stale. Then UI walks, videos,
   gates, decided, out of scope. Last, the Review block and the Change
   map, from the blocks you just wrote, placed first in the file: the
   part a person reads to approve the plan. A run: `plan.md` § Run, one
   Stack block, one stack Review, one Change map, one Facts block, then
   the blocks above once per layer, each with its small Review, in stack
   order. `Proved` sits under `Facts`, once.

7. **Done rule.** Walk `plan.md` § Done, item by item. A miss sends you
   back to step 4 or 5.

8. **Present.** Per `../../shared-skill-core/plan-page.md`: write the plan to its `.md`,
   run `python3 scripts/build-page.py <plan .md>`, and on problem lines fix
   the `.md` and run it again. Never write `DATA`: the builder makes it.
   Serve with `../../shared-skill-core/serve.sh`, open it in the browser, or publish it on a
   headless host. Chat
   gets the summary block from `plan-page.md` § Chat, nothing more. Wait. An
   edit: change the `.md`, rebuild, bump `v`, show the summary
   again. `ok`: remove the base copy (step 1), say
   `Ready for /handoff.` (a chat plan: `Ready for /ship.`, since the
   cloud needs an issue), and stop.

## Examples

**User:** `/plan-up https://github.com/acme/shop/issues/42` (size/M feat,
export orders as CSV, six Done-when lines)

The tree is on `feat/old-work` with two edits; it stays as it is. Base
copy of `origin/main` in a temp folder. Gate passes. Round 1: five agents fetch
`orders/export.ts` and its callers, the `orders.test.ts` seam, the
`pnpm test` and `pnpm typecheck` scripts, how `ErrorToast.tsx:12` shows
errors, the `csv-stringify` docs, and the docs on export:
`README.md:88` lists JSON as the only export format. The docs say
`csv-stringify` escapes quotes but are silent on newlines inside a
field, and order notes hold newlines. One free probe, in a temp
folder: install `csv-stringify`, stream three rows, one note with a
newline. It comes back quoted and whole: a `Proved` line. Two big forks. First: a big shop
can hold more orders than one request should carry, and the repo has no
background jobs. Question with `A` stream the file in one request
(pick, `export.ts:31` streams JSON the same way) and `B` a job queue,
new to the repo. User: `A`. Second: `csv-stringify` is not in
`package.json`, a new dependency, so it is asked no matter what.
Question with `A` add `csv-stringify` (its docs show a stream API that
fits `export.ts:31`, and the probe shows a note with a newline comes
through whole) and `B` a hand-written `toCsvRow()` next to
`lib/format.ts:14`, which already quotes strings but has no escaping.
User: `A`. Both go under Decided marked `(user)`. Small forks under
Decided: stream, since `export.ts:31` does; the file response goes
through `lib/download.ts:8`, which already sets the headers, so no new
helper; file name `orders-<date>.csv`; delimiter `,`.
Plan: a Review block on top (Change: orders export as JSON only → as
JSON or CSV; Blast radius flags `Dependency: csv-stringify, D2` and
nothing else; one risk, backed by P1), one Proved line, six Proof rows,
six slices (slice 1 carries
`Docs: README.md:88`, CSV next to JSON), three UI walks (happy, empty,
failed), two videos: happy and failed from the seeded shop, empty from
an empty seed.
Done rule holds. Present, `ok`, `Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/shop/issues/88` (PR 90 by
`@bob` is open and closes #88)

`claims.py acme/shop 88` prints `#88 pr #90 "Add order notes" @bob
https://github.com/acme/shop/pull/90`. One message: `#88 Order notes`,
under it `PR #90 Add order notes · @bob · https://github.com/acme/shop/pull/90`,
then the question with `A` review their PR instead, `B` build anyway,
`C` stop. User: `A`. Print `/review-pr https://github.com/acme/shop/pull/90`,
remove the base copy. Stop.

**User:** `/plan-up https://github.com/acme/shop/issues/57` (size/XS fix,
`handoff-ready`, three Steps, two Done-when lines)

Step 2 sees the label: short path. One Explore round: `pnpm test` and
`pnpm typecheck` from `package.json`, the seam of `export.ts:57` is
`exportOrders()` and `export.test.ts` already tests it, `CODING_STANDARDS.md`
exists, no screen, `docs/export.md:12` shows the old date format. Steps 1 and 2 become slice 1 (`Change` at
`export.ts:57`, copy `export.ts:49`) with the test from step 3, `Then`
the ISO date from the issue, and `Docs: docs/export.md:12`, the ISO
date. No probe: the Steps leave no doubt. Two Proof rows: row 1 the case, row 2 the
`pnpm test export` command. No walks, no videos. Gates: the existing
`export.test.ts` cases. Decided: none, the issue had no `Open` line.
Done rule holds. Present, `ok`, `Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/tally/issues/12` (size/S fix,
a CLI; Done when: `status` wraps its hints on a narrow terminal, `rules
list` prints each id whole)

Round 1: both commands print through `format.ts:219`, and
`status.test.ts:83` already sets a fake width. A person reads both lines
in a terminal, so both are on a screen: `UI: terminal`, `Screen: 60 x
24`, `Open: tally status`. Each row gets its test at width 60 and a
walk: `Setup` a 60-column terminal, `Steps` run the command, `See` the
wrapped hint, the whole id. Both screens exist on the base, so each
walk's `Before` names the same command and the old output: the hint
cut at column 60, the id cut short. Plan: two slices, two walks, one
video.
Done rule holds. Present, `ok`, `Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/shop/issues/61` (body has What
to build, no Done when)

Gate fails on "Done means". One block: the question that closes it, and
`/grill` named. Stop.

**User:** `/plan-up https://github.com/acme/shop/issues/70 #71 #73 #74`
(epic "teams"; #71 Team entity M, #73 add member S, #74 invite S; #73
and #74 blocked by #71)

Base copy of `origin/main`. Edges hold: #71 first, #73 and #74 after it. Gates
pass. Round 1 fans out per ticket. #71's plan decides the seam
`teams/service.ts` `createTeam()`. #73's Seams block points at it as
`layer 1, slice 1`, since the file does not exist yet. One big fork on
#74 (invite token lifetime is not in the repo), asked, answered. Plan:
Stack block with three layers, one Facts block, 7 points, then Proof
through Out of scope for each layer. Done rule holds. Present, `ok`,
`Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/shop/issues/70` (same epic; #72
is closed)

Bare epic URL. Sub-issues that are open: #71, #73, #74. Parent body
lists them in that order. Say `Run: #71, #73, #74`, then continue as the
run above.

**User:** `/plan-up https://github.com/acme/shop/issues/75 on https://github.com/acme/shop/pull/80`
(#75 team switcher, S; PR 80 is the top of the open stack)

Base is PR 80's head branch; the base copy is of that branch. One layer, base named
in the Stack block as `PR #80`. Rest as a single ticket. Present, `ok`,
`Ready for /handoff.`
