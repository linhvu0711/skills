# plan-up

Turns a ready GitHub issue, or a run of tickets from an epic, into a plan that a coding agent can follow cold: seams, tests, slices, doc updates, UI walks, and video scripts. It plans and never builds, and it leaves your repo as it found it.

## Use it when

You have a ticket that passes the readiness gate and you want it built by an agent that has no taste and can't cheaply ask you questions. Type `/plan-up` with the target (`$plan-up` in Codex). Name an issue or PR any way: a URL, `42`, `#42`, or words that point at one in the chat, such as "the CSV issue". A bare number is in the repo you are in. If it is not clear which one you mean, it asks.

- `/plan-up <issue>`: one ticket, one PR.
- `/plan-up <epic> #12 #14`: those tickets from the epic, as a stack of PRs.
- `/plan-up <issue> #14 #15`: a set of plain tickets, stacked the same way.
- `/plan-up <epic>`: every open ticket in the epic.
- `/plan-up <issue> on <pr>`: one more layer on an open stack.
- `/plan-up` with no issue named: plan the work this chat agreed on, with no issue. Words after it say which part of the chat to plan.

It reads every ticket with its comments, since a later comment can change what the ticket asks. Before it plans, it checks whether someone is already on each ticket: an open PR that closes or mentions it, an assignee who is not you, or a comment that claims the work. If it finds one, it names them and asks whether to review their PR, build anyway, or stop. When `gh` fails during the check, it says the check could not run and asks whether to go on. Your checkout can be on any branch, with edits or not: it reads a fresh copy of the base branch in a temp folder, removes the copy when it ends, and never touches your tree. A ticket that fails the gate comes back as a list of questions for [grill](../grill/) or [triage](../triage/).

With no issue named, there is no issue to read. It writes a short brief from the chat instead: a title, the task, the Done-when lines, and a size, by the same rules as an issue. It prints the brief and goes on, and the brief goes through the same gate. A plan with no issue has no claims to check, no short path, and a file named `plan-<owner>-<repo>-chat-<words>.md`. The words also name its branch, so it picks words that no other plan file and no branch uses yet, adding `-2` or `-3` when it must. Its PR has no `Closes #<n>` line, and only a local build can take it, since the cloud needs an issue.

## What you get

A plan file, `plan-<owner>-<repo>-<n>.md` (or `plan-<owner>-<repo>-chat-<words>.md` for a plan with no issue) under `~/.agents/artifacts/plan/`, and the same plan as an HTML page opened in your browser. The plan opens with its issue, size, and date and holds a short Summary that the page shows on its Overview tab. [build-page.py](scripts/build-page.py) builds the page from the `.md`.

The page opens on a Review tab, written for you, the person who approves the plan: what changes, the approach and why not the other way, the blast radius (the parts it touches, and whether it adds a dependency, a schema change, an API, config, or CI), the choices you should know about, at most three risks, how we know it works, and the scope. Each part has a size limit, and the builder refuses a plan that breaks one. A run shows the whole stack first, then a small block for each layer.

Under the blast radius sits a change map, drawn only when the plan adds or removes a part, moves a job between parts, or changes what flows between them. A box is a part with a job, named in your repo's words; an arrow is what moves, never an import; a gray area is the app or package. Green is new, amber is a changed job, red is removed, and a dashed border is outside the repo. An arrow finds its own way around the boxes, and its label sits on it where it covers no box or other label, on two lines when one has no room. Point at a box to see its files, and name its ref (`M3`) in chat to change it. A run gets one map for the whole stack, with each change tagged by its layer. The builder keeps every name, job, and arrow label short enough to fit; the limits live in the builder. The page routes every flow itself: `bend` is not a plan field.

The tabs after it are for the agent that builds. The plan holds the facts it proved by a probe, one Proof row per Done-when line, the seams, one slice per change in tracer-bullet order, each with the tests that prove it (Given, When, and a literal Then, and for a fix's first test a Red line, what it shows on the base; each test named for what the code does, never how, and run on the repo's test database when it has one, not on a mock of it) and the docs its change makes stale, so code and docs land in one commit (doc text a grill agreed on, under the issue's `## Docs to write`, goes in word for word), UI walks and videos for each line a person checks by looking (a web page, a window, or a command's output in a terminal), a walk whose screen depends on the time setting the clock in its setup, so it never waits for the real clock, each walk step one action, so a typed command stands alone in backticks and the builder refuses a step that types text with no backticks, types two commands, joins commands with `;` or `&&`, or starts with `clear`, or a terminal walk whose `Must not` names `stderr` or `stdout`, a before shot for each walk that changes a screen that exists already, the gates, and every small decision it made, so you can veto any of them by name. Big decisions, and every new dependency, are asked in chat first, one question at a time, with the cleaner option as the pick, package or not.

A new module or seam must earn its place, by the rules improve-architecture uses too. The plan says what a new module hides, so deleting it would push work back into its callers, and a seam that swaps one thing for another needs two adapters, such as the real one and a test fake.

Before it plans the steps, it asks what each part the work touches would look like if it was built today, from first principles, and reads the code for signs that the current design is wrong: a flag for one case, the same logic twice, callers that work around it. A design that fits is extended by the simplest clear change. A design that does not fit is rebuilt, and you pick: the patch is shown as the other option, with what it costs later. A rebuild is planned as the new form, each caller moved, and the old form deleted last, in the same PR.

Before it adds, it looks for dead code in the area the ticket touches: a function, file, flag, or stub that no caller uses, or an old way that a newer one replaced. Code is dead only when a search finds no caller in the code, strings, scripts, and config, and nothing calls it by name at run time; anything else stays, with a line that says why. Dead code goes in the plan's first slice, alone, with the tests that cover the area passing before and after; with no such test, the search that found no caller must find nothing after the delete. With no dead code, the plan has no such slice.

The plan names the data shape before the logic: the type, the table, or the file format. A new need goes into that shape, not into a flag at the side. Each kind of ID gets its own type, data from outside is parsed into a type at the edge, and a type comes from a schema when one exists. A step that writes a file, a row, or a remote call is safe to run twice and after a crash, and a test runs it twice. Two writers get their own targets before the plan names any lock.

A `fix` plan proves the bug is gone. The type comes from the title's first word, and a repo that writes `bug:` for a fix counts too. The issue's repro is the first Proof row, and the first test runs it through code the base already has: on the base it fails on its assertion and shows the wrong result, never on a missing name. A bug you can see gets a walk whose before shot shows it. A `refactor` plan proves nothing changed: it names the tests that cover the code, or adds a lock test that passes before the change and after it. Every caller moves to the new form, the old form is deleted in the same PR, and a rename gets a search for the old name in strings, docs, and config.

When reading leaves a doubt the plan hangs on (does this tool do what we need, what does this API really return), it runs a small probe first, in a temp folder or a throwaway worktree, never in your tree. Probes run in parallel sub-agents, like the code search. Only doubts that change the plan get a probe. A free, safe probe runs on its own; one that costs money, needs a credential, or touches anything shared waits for your yes.

Chat gets only a summary:

```
Plan: #42 Export orders as CSV · size/M · base main
6 done-when · 6 slices · 1 doc · 1 probe · 3 walks · 2 videos · 1 fork answered (A, stream)
http://127.0.0.1:8765/plan-acme-shop-42.html
Say ok, or name a ref (S2, W1, D3, #4) and what to change.
```

A `perf` ticket's plan gets a Perf block (Metric, Command, Before, and a Pass rule with its run count) from the issue's Baseline and Target, read by the shared benchmark checklist.

A `ready-to-build` ticket takes a short path: its Steps are trusted and only the gaps are read. It still looks for dead code, and a delete slice goes before the Steps. It also reads the data the Steps touch, and a Step that breaks the data shape, rerun, or one-writer rules sends the ticket down the full path. A Step that adds a module or a seam still meets the rules above; one that fails them sends the ticket down the full path. A Step that patches a part whose design does not fit also sends it down the full path.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

## Needs

- `gh`, signed in, and `git`.
- `python3`, to check for claims and to build and serve the page. `curl` and `lsof` for the local server.
- A browser (`open` on macOS, `xdg-open` on Linux). Without one, the `to-artifact` skill (not in this repo) publishes the page instead.
- Readers, per the reader job in `../../shared/facts.md`, with the web for library docs (Codex reads the files itself), and runners for probes, per the runner job in the same file (Codex runs them itself).
- From the shared core: [facts.md](../../shared/facts.md), [grilling.md](../../shared/grilling.md) for the question format and how to pick, [codebase-design.md](../../shared/codebase-design.md) for the rules a new module or seam must pass, [issue-rules.md](../../shared/issue-rules.md) for the gate, [plan-page.md](../../shared/plan-page.md) for the page, [benchmark.md](../../shared/benchmark.md) for a perf plan, and [serve.sh](../../shared/serve.sh) to serve the page.

## Fits with

- Takes tickets from [to-issue](../to-issue/) and runs from [to-epic](../to-epic/).
- Sends a failed gate to [grill](../grill/) or [triage](../triage/).
- Its plan goes to [build-and-prove](../build-and-prove/), which builds it on your machine with proofbox, or to [handoff](../handoff/), which sends it to Devin or Cursor. [ship](../ship/) picks one.
- [ship](../ship/) runs it as its first step: with its page and a wait in ship mode `review`, with no wait in `ready` or `merge`. [kickoff-herdr](../kickoff-herdr/) runs it, or ship, in a new pane.

## Tests

The cases for [claims.py](scripts/claims.py) are in [tests/claims.sh](tests/claims.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.

The cases for [prune.sh](scripts/prune.sh) are in [tests/prune.sh](tests/prune.sh). It deletes a plan once its issues are closed, and a plan with no issue 30 days after its file last changed.

The cases for [build-page.py](scripts/build-page.py) are in [tests/build-page.sh](tests/build-page.sh), with Markdown inputs and expected page data in [tests/build-page/](tests/build-page/).

A perf plan's `## Perf` block shows on the Overview tab under the facts, and the builder refuses a Perf block that lacks one of its four lines, and a `[perf]` ticket or run layer with no Perf block.

A plan with no issue must end with a `## Brief` block that holds a `Task:` line and a `Done when:` list; the builder refuses it without one, since the build prompt quotes them.

The agent writes only the Markdown, never `DATA`. On an invalid block the builder names each problem, writes no page, and leaves an existing page in place. It also refuses a long dash or a curly quote outside backticks, and names the line.

A slice can prove several lines joined by `and` or commas. A map's quoted file locations stay whole, even when a path contains a comma.

A slice headed `Slice 1, deletes dead code: <area>` proves no line and the page marks it so, and its Read this first note names slice 2 as where the build starts; the builder refuses that heading on any slice but the first of a layer, and with any number but 1.

## Credits

The idea of planning test-first slices for an agent to build comes from the `tdd` and `implement` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Thanks. No text was copied.

Naming a test for what the code does and running the repo's own database for real take ideas from `tdd/tests.md` and `tdd/mocking.md` in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). No text was copied.

The perf block takes an idea from `poteto-mode/playbooks/perf-issue.md` and `benchmark-checklist` in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

Deleting dead code before adding takes an idea from `principle-subtract-before-you-add` in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.

Right design first, shape first, rerun and crash, and one writer take ideas from `principle-foundational-thinking`, `principle-redesign-from-first-principles`, `principle-model-the-domain`, `principle-type-system-discipline`, `principle-make-operations-idempotent`, and `principle-separate-before-serializing-shared-state` in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
