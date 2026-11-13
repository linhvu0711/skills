---
name: plan-up
description: "Turn one ready GitHub issue, a run of epic tickets, a set of plain tickets, a whole epic, stacked as PRs, or work this chat agreed on with no issue, into a plan an executor can follow cold: seams, tests, slices, docs, UI walks, video scripts. Settles doubts by reading and by small probes, and leaves the repo as it was. Ends with the plan as a local HTML page open in the browser, a short summary in chat, and waits for ok, then /handoff."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

The rules live in `references/`: `plan.md`, the plan rules,
`executor.md`, and `probes.md`. Each step names the section it reads,
as `references/plan.md` § Change map: read from that heading to the
next heading of its level or higher, not the whole file. A heading
inside a code fence belongs to a template, not a section. A step that
needs a whole file says so and why. First read `references/plan.md`
§ Vocabulary: its words run through every step. At steps 8 and 9,
read `../../shared/plan-page.md`: where the plan is written
and how it is shown. Before a `Decided` line adds a module or a seam, on the full
path or the short one, read `../../shared/codebase-design.md`:
the new one must pass its deletion test, and a seam needs two adapters.
This file is the order of operations.

You plan; you do not build, and the repo is left as you found it. Facts
come from reading, and from a probe when reading leaves a doubt the plan
hangs on. Big forks go to the user. Everything else you decide and write
down.

## Facts

Read `../../shared/facts.md` first: you are the brain, readers
retrieve, and a brief that needs outside facts asks for the web in plain
words.

## Six forms

Name each issue or PR any way: a URL, `42`, `#42`, `issue 42`, `PR
80`, or words that point at one in this chat, such as "the CSV issue"
or "the one we just made". Work out which ones the user means. A bare
number is in this repo, or in the repo of a URL next to it. Unclear, or
two match: ask. Then go on with their URLs.

- `/plan-up <issue>`: one ticket, one PR. Base is the default branch.
- `/plan-up <epic> #12 #14 #15`: a **run**. The epic is a graph; a run
  is one path through it, landed as a stack of PRs, one ticket per
  **layer**, in the order given. The user names the tickets and owns
  what is taken; you check only the edges. Base is the default branch.
- `/plan-up <issue> #14 #15`: a **set**. Plain tickets with no shared
  parent, the first one named being the first ticket. A set is a run without a
  parent: every rule below for a run applies, and the parent steps are
  skipped. The first issue having no sub-issues is what makes it a set.
- `/plan-up <epic>`: the **whole epic** as one run. The tickets are
  every open sub-issue, in the order the parent body lists them: phase
  by phase, and inside a phase top to bottom. Closed tickets are skipped.
  From there it is a run.
- `/plan-up <issue> on <pr>`: one ticket as a new layer on top of an
  open stack. Base is that PR's head branch.
- `/plan-up`, no issue named, words after it or none: a **chat plan**. The work
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
   its submodules, in a temp folder. It also installs the packages the
   base's lockfile names, with no install scripts run, so the copy holds
   the library code and types a reader looks up. `stop:` on stderr: show
   it, stop. A `warn:` line on stderr: show it and go on; that copy has
   no packages. Hold `BASE_WT` and
   `BASE_SHA` from its line. Every repo fact comes from `BASE_WT`: each
   Explore brief names it as the folder to read, every command that
   reads the code runs there, and a `file:line` is a line there, written
   from the repo root. Nothing is written in it but what the script
   installs. The checkout you start
   in is never read for facts and never changed.

   The copy lives until the run ends, by `ok` or by any stop. Then
   `bash scripts/base-copy.sh --remove <BASE_WT>`.

   Then prune old plans: `python3 scripts/prune.py`.
   It deletes the files of every plan whose issues are all closed. Its
   result never stops the run. Chat gets its last line only when it
   pruned something or printed a `stray` line; name the strays.

2. **Read the issue.** `gh issue view <n> --json number,title,body,labels,comments`.
   Read the comments too; a later comment can change a line. Carrying
   `ready-to-build`: the **short path**, `plan.md` § Ready-to-build. The
   Steps are trusted. Step 4 asks only what that section lists, step 5
   closes only the issue's `Open` lines, steps 6 to 9 run as written.

   The title's leading word is the issue's type, read through the
   repo's `words` map, per `plan.md` § Type variants, its opening
   lines. A `fix`, a `refactor`, or a `perf` also follows the part of
   § Type variants for its type, `plan.md` § fix, § refactor, or § perf:
   step 4 asks what that section adds, and steps 6 and 7 hold its rules.

   A run: read the parent and every ticket, each with its comments, by
   the command above. A set: no parent, read every ticket the same way,
   first one first. A bare epic: list the
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
   fails names the pair, stop. A `ready-to-build` ticket in a run takes
   the short path too: its Steps become the layer's slices per `plan.md`
   § Ready-to-build, and its facts round asks only what that section lists.

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
   `../../shared/grilling.md`. A PR named: `A` review their
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
   instead, per `../../shared/issue-rules.md`: a `Title`
   (§ Title, the repo's style), a `Task` in one to three lines, the
   `Done when` lines (§ Done when), the `Known` and `Open` lines of
   § Context, and a size (§ Size). A chat plan has no Steps and takes
   no short path, whatever its size. The facts are only what the chat
   said or ran; nothing is made up to fill a line. Its slug is picked
   free, per `../../shared/plan-page.md` § Files, before
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
   `../../shared/issue-rules.md` to the issue
   text, each ticket of a run on its own; to a chat plan's brief, and
   its gaps name `/grill` only. Pass: continue. Fail: name the
   ticket, list the gaps, each as the question that closes it, name
   `/grill` or `/triage`, stop. Nothing is planned.

4. **Facts.** First read `plan.md` § Slices with its `####` rules: the
   asks below feed them, and step 5 sorts forks by them. Round 1 is one
   message, one Explore agent per concern, and in a run per ticket and
   concern:
   - the code each Done-when line touches, with tests, and every caller
     with what it assumes: the shape it reads, the error it expects, the
     order it relies on;
   - what the repo already holds that does the job, or part of it: a
     helper, a service, a component, a type, a fixture, a script; where
     each lives, who calls it, how far it reaches. The plan extends
     these before it adds when their design fits, per `plan.md`
     § Slices;
   - for each part the work touches: what it would look like if built
     today for every job it has, the new one too; the signs in the code
     that its current design is wrong, as `plan.md` § Slices, Right
     design first lists them; and the simplest path to that
     design: what can stay, what moves, how many callers move. The plan
     picks extend or rebuild per `plan.md` § Slices, Right design first;
   - the data the work reads and writes: its type, table, file, or key;
     where its type is defined (a schema, a spec, a generator, or by
     hand); and every other code that writes it. The plan builds on
     these per `plan.md` § Slices, Shape first and One writer;
   - the dead code in the area the ticket touches: a function, a file, a
     flag, or a stub that no caller uses, and an old way that a newer
     way replaced; for each, the searches that show no caller in the
     code, in strings, in scripts, and in config, and whether it can be
     called by name at run time. The plan deletes it first, per
     `plan.md` § Slices;
   - how the repo runs test, typecheck, lint, build, and the app, read
     from CI config, package scripts, and README;
   - the nearest existing test at each candidate seam, how the repo
     mocks its borders, and, for each Done-when line, each test at any
     level that already checks it, whole or in part, per `plan.md`
     § Tests that can fail;
   - when any line is on a screen: the UI kind and how it is opened,
     the mockup the issue links, and the repo's look rules: `DESIGN.md`,
     tokens, the shared component folder, the nearest existing screen,
     and, for a screen that exists on the base, what it shows there
     now, for the walk's `Before` line;
   - the repo's own words and code rules, wherever they live:
     `CONTEXT.md`, `CODING_STANDARDS.md`, `CONTRIBUTING.md`,
     `CONVENTIONS.md`, `STYLE*.md`, `docs/**`, ADRs, the
     `## Docs to write` of other open issues in the area
     (decided, not built: they bind the plan like an ADR), `AGENTS.md`,
     `CLAUDE.md`, `.cursor/rules/**`, `.editorconfig`, lint and formatter
     configs; and where no file rules, the shape the code keeps: names,
     layout, errors, logging, tests. The plan's names and every `Change`
     follow them;
   - the parts around each seam the work touches, for the Change map:
     each part's job in the repo's words (`CONTEXT.md`, then the code),
     who asks whom, what data moves between them, which app or package
     holds each, and the files behind each part;
   - each Open line in the issue's Context, as its own ask;
   - the docs for each library the work leans on, in a reader brief
     that asks for the web;
   - the docs that describe what each Done-when line changes: `README`,
     `docs/**`, guides, `CHANGELOG`, ADRs, API docs, `--help` text,
     `.env.example`, and the rules files above. The plan updates each
     one in the slice that makes it stale, per `plan.md` § Slices. Each
     entry under the issue's `## Docs to write` is such a doc, its text
     given.

   Known lines in the issue's Context are facts in hand, proved by a run.
   Take them as read. Ask for nothing a Known line settles. In a run, a
   seam that an earlier layer creates is not in the repo; it is in that
   layer's plan, and a later layer points there (see `plan.md` § Run).

   A round ends when every ask came back, or came back "not found". You
   hold the picture: run another round for whatever it still lacks.

   **Probes.** A doubt that reading leaves, and the plan hangs on, is
   run, per `references/probes.md`, read whole before the first probe,
   since a probe uses every part of it, from When to What it leaves:
   does the tool do it, what does the
   API return, where is the limit. Probe only what changes the plan;
   never to be thorough. Probes fan out like Explore agents, one
   sub-agent each, in one message, beside any round still open. A free
   probe runs without asking; one that costs money, needs a credential,
   or touches anything shared waits for a yes. Each answer is a
   `Proved` line. A doc a probe finds wrong or missing joins the docs
   the plan updates.

   A gap that neither reading nor a probe can close becomes a question.

5. **Forks.** Sort every choice the facts leave open by two tests:
   - **The user's fact**: the right pick needs a fact only the user
     holds: what they meant, how the product should act, what it may
     cost, how far the scope goes, or a number the repo does not hold,
     such as data size, traffic, or who else calls this. A Known line
     that holds the fact settles this test. It holds for a Done-when
     line that reads two ways, and for a rebuild of a part whose design
     the facts round found wrong (`plan.md` § Slices, Right design
     first), with the patch as a lower option and what it costs later.
   - **Hard to undo**: a wrong pick ships to data or callers you cannot
     see, or the next issue copies it. It looks like: a schema or stored
     data, a public API, auth, input a user controls, a secret, data
     that leaves the system, a pattern new to the repo (first queue,
     cache, job), a move of work between layers, a choice that scales
     with size or load.

   The user's fact holds: **big fork**. Ask the user, one question per
   message, in the question format of
   `../../shared/grilling.md`, the `file:line` behind each
   option on the question's `Seen:` line. Wait. A Done-when line that
   reads two ways is asked as what the line means: each reading in the
   user's words, with one small example of what the user sees under it.
   The code follows from the answer, so the options never name code.

   Only hard to undo holds: look for a **clear winner**, the option a
   careful senior engineer would ship, per `../../shared/grilling.md`
   § Your pick, where each other option is a shortcut or plainly worse
   and gains nothing the user would weigh. A clear winner: decide it.
   Its `Decided` line gives the `file:line` that settles it and ends
   `(hard to undo)`, and the Review lists it under `Choices` with its
   Risk and the same mark, so the user sees it and can veto it. For
   example, a saved record is always read and written whole, and the
   test database cannot group writes: one row per record wins over two
   tables, so decide it. No clear winner, the options trade off
   something real, or you are not sure: **big fork**, ask as above. A
   new dependency never takes this path: it is asked, per the next
   paragraph, however clear its win.

   **A new dependency is a big fork every time.** The two tests do not
   apply; do not reason it down to a small fork. A dependency is any
   package, library, tool, or outside service the repo does not hold
   today: a new line in `package.json`, `pyproject.toml`, `go.mod`,
   `Cargo.toml`, `Gemfile`, a lockfile, a Dockerfile, a CI config, or a
   new SDK and API key. A version bump of one already there counts too.
   Ask before the plan names it. The question holds at least two
   options: the dependency, with the docs fact from round 1, or the
   `Proved` line from its probe, that says it does the job; and the nearest thing the repo already has, named
   by what it does, with why it does not serve and its `file:line` on the
   `Seen:` line, or hand-written
   code when the repo has nothing. Either can be `A`, by `grilling.md`
   § Your pick. Wait. The answer goes under `Decided`,
   marked `(user)`. A plan that adds a dependency the user did not pick
   is not done.

   Neither holds: **small fork**. The repo shows the answer. Decide,
   write it under `Decided` with the `file:line` that settles it. Code
   shape, which seam to test at, and extend-or-add when the part's
   design fits (`plan.md` § Slices) are small forks.

   A probe can settle either test. A big fork asked after a probe carries
   its `Proved` line in the option it backs.

   Every Open line from the issue closes here, by a fact or by a question.
   None survives into the plan.

6. **Write the plan** per `plan.md`. First read `references/executor.md`
   whole: its three parts say what the executor has, lacks, and does,
   and every block is written for that. Then `plan.md` § Shape, the
   opening lines of § Filling the blocks, and each block's section under
   it as you write that block, with § Look and § Before shots for a plan
   with walks. A run first reads § Run, a chat plan § Chat plan. Proof
   table first, one row per
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

8. **Check.** Write the plan to its `.md`, per
   `../../shared/plan-page.md` § Files. Then decide which second
   models check it, with fresh eyes, before the user sees it (ADR
   0020, ADR 0021, ADR 0023). Two checkers can run, side by side,
   each on its own signs: `plan-correctness-checker` looks for what
   would make the build fail or ship the wrong thing, and
   `plan-design-checker` looks for a code shape the plan should not
   build. Hold one `Plan check:` line for the summary.

   - **Who gets them.** Size the plan as `../../shared/size.md` sizes
     a ticket, from its Blast radius and its slices. XS: neither, and
     the line is `Plan check: skipped · size XS`. A plan you wrote
     while you run on Fable: neither, and the line is
     `Plan check: skipped · made by Fable`. In Codex: neither, and the
     line is `Plan check: skipped · not in Claude Code`. Else judge
     each checker by its own signs, never by a fixed list:
     - **Correctness**: run it when you can name what a wrong plan
       would break and that fix costs real work. Weigh the Risks
       marked `not proved`, and a table, an API, or a data migration
       in the Blast radius: a plan that adds a column to the orders
       table gets it.
     - **Design**: run it when the plan adds or moves a part (a new
       module, a new seam, logic that moves from one file to
       another), or touches a part where the facts round found a sign
       of a wrong design, per `references/plan.md` § Slices, Right
       design first, whether the plan patches that part or rebuilds
       it. A plan that adds a helper module gets it; a plan that fixes
       a date inside one function does not.

     Unsure: skip that checker. A skipped checker's part of the line
     gives the reason, as `design skipped · no new or moved part, no
     sign of a wrong design`.
   - **Start them.** Each checker due, per `../../shared/facts.md`
     § Skill agents, both in one message when both are due. Each
     brief holds the issue text with its comments (a run or a set:
     the parent and every ticket; a chat plan: its `## Brief` block),
     the plan path, `BASE_WT`, and the full path of
     `../../shared/facts.md`. The design checker's brief adds the full
     paths of `../../shared/codebase-design.md` and
     `references/plan.md`. Nothing else: no notes, no reasons, no
     chat. A checker not found: `general-purpose` with its body pasted
     and the model `fable` on the Agent call.
   - **Sort each finding.** Design findings first, since one can
     change the approach and leave a correctness finding about a step
     that is gone; that finding is `kept`, with that reason. One you
     agree with: fix the plan. One you disagree with, or whose fix is
     a big fork by step 5's sort: ask the user, one question per
     message in the format of `../../shared/grilling.md`, with the
     finding as one option and the plan as the other. Wait. Then fix
     the plan by the answer. A design finding that turns a patch into
     a rebuild, or a rebuild into a patch, is a big fork (step 5).
   - **Look again.** A fix that changed the `Approach` line or a
     `Decided` line: send each checker that ran the changed blocks,
     by SendMessage, once, and sort its answer the same way.
   - **Record.** A `## Plan check` block, last in the `.md`, per
     `references/plan.md` § Plan check. The line has one part per
     checker, correctness first, joined by `; `. Each part is
     `<n> found · <f> fixed · <a> asked you`, `none found`,
     `skipped · <why>`, or `failed · <why>`, as
     `Plan check: correctness 3 found · 2 fixed · 1 asked you; design skipped · no new or moved part`.
   - **One fails.** An error, a refusal, or a usage limit: the plan
     goes on without that checker, which gets no line in the block,
     and its part of the line is `failed · <why>`. The other
     checker's findings stand. No checker that ran is left: no block.

9. **Present.** Per `../../shared/plan-page.md`: run
   `python3 scripts/build-page.py <plan .md>`, and on problem lines fix
   the `.md` and run it again. Never write `DATA`: the builder makes it.
   Serve with `../../shared/serve.sh`, open it in the browser, or publish it on a
   headless host. Chat
   gets the summary block from `plan-page.md` § Chat, nothing more. Wait. An
   edit: change the `.md`, rebuild, bump `v`, show the summary
   again. `ok`: remove the base copy (step 1), say
   `Ready for /handoff.` (a chat plan: `Ready for /ship.`, since the
   cloud needs an issue), and stop.

## Examples

Sample plans and stops: `references/examples.md`.
Read it when a step here is unclear.
