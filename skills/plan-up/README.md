# plan-up

Turns a ready GitHub issue, or a run of tickets from an epic, into a plan that a coding agent can follow cold: seams, tests, slices, doc updates, UI walks, and video scripts. It plans and never builds, and it leaves your repo as it found it.

## Use it when

You have a ticket that passes the readiness gate and you want it built by an agent that has no taste and can't cheaply ask you questions. Type `/plan-up` with the target (`$plan-up` in Codex):

- `/plan-up <issue-url>`: one ticket, one PR.
- `/plan-up <epic-url> #12 #14`: those tickets from the epic, as a stack of PRs.
- `/plan-up <issue-url> #14 #15`: a set of plain tickets, stacked the same way.
- `/plan-up <epic-url>`: every open ticket in the epic.
- `/plan-up <issue-url> on <pr-url>`: one more layer on an open stack.
- `/plan-up` with no URL: plan the work this chat agreed on, with no issue. Words after it say which part of the chat to plan.

It reads every ticket with its comments, since a later comment can change what the ticket asks. Before it plans, it checks whether someone is already on each ticket: an open PR that closes or mentions it, an assignee who is not you, or a comment that claims the work. If it finds one, it names them and asks whether to review their PR, build anyway, or stop. When `gh` fails during the check, it says the check could not run and asks whether to go on. Your checkout can be on any branch, with edits or not: it reads a fresh copy of the base branch in a temp folder, removes the copy when it ends, and never touches your tree. A ticket that fails the gate comes back as a list of questions for [grill](../grill/) or [triage](../triage/).

With no URL, there is no issue to read. It writes a short brief from the chat instead: a title, the task, the Done-when lines, and a size, by the same rules as an issue. It prints the brief and goes on, and the brief goes through the same gate. A plan with no issue has no claims to check, no short path, and a file named `plan-<owner>-<repo>-chat-<words>.md`. The words also name its branch, so it picks words that no other plan file and no branch uses yet, adding `-2` or `-3` when it must. Its PR has no `Closes #<n>` line, and only a local build can take it, since the cloud needs an issue.

## What you get

A plan file, `plan-<owner>-<repo>-<n>.md` (or `plan-<owner>-<repo>-chat-<words>.md` for a plan with no issue) under `~/.agents/artifacts/plan/`, and the same plan as an HTML page opened in your browser. The plan opens with its issue, size, and date and holds a short Summary that the page shows on its Overview tab. [build-page.py](scripts/build-page.py) builds the page from the `.md`.

The page opens on a Review tab, written for you, the person who approves the plan: what changes, the approach and why not the other way, the blast radius (the parts it touches, and whether it adds a dependency, a schema change, an API, config, or CI), the choices you should know about, at most three risks, how we know it works, and the scope. Each part has a size limit, and the builder refuses a plan that breaks one. A run shows the whole stack first, then a small block for each layer.

Under the blast radius sits a change map, drawn only when the plan adds or removes a part, moves a job between parts, or changes what flows between them. A box is a part with a job, named in your repo's words; an arrow is what moves, never an import; a gray area is the app or package. Green is new, amber is a changed job, red is removed, and a dashed border is outside the repo. An arrow finds its own way around the boxes, and its label sits on it where it covers no box or other label, on two lines when one has no room. Point at a box to see its files, and name its ref (`M3`) in chat to change it. A run gets one map for the whole stack, with each change tagged by its layer. The builder keeps every name, job, and arrow label short enough to fit; the limits live in the builder. The page routes every flow itself: `bend` is not a plan field.

The tabs after it are for the agent that builds. The plan holds the facts it proved by a probe, one Proof row per Done-when line, the seams, one slice per change in tracer-bullet order, each with the tests that prove it (Given, When, and a literal Then) and the docs its change makes stale, so code and docs land in one commit, UI walks and videos for each line a person checks by looking (a web page, a window, or a command's output in a terminal), each walk step one action, so a typed command stands alone in backticks and the builder refuses a step that types text with no backticks, types two commands, joins commands with `;` or `&&`, or starts with `clear`, or a terminal walk whose `Must not` names `stderr` or `stdout`, a before shot for each walk that changes a screen that exists already, the gates, and every small decision it made, so you can veto any of them by name. Big decisions, and every new dependency, are asked in chat first, one question at a time, with the cleaner option as the pick, package or not.

When reading leaves a doubt the plan hangs on (does this tool do what we need, what does this API really return), it runs a small probe first, in a temp folder or a throwaway worktree, never in your tree. Probes run in parallel sub-agents, like the code search. Only doubts that change the plan get a probe. A free, safe probe runs on its own; one that costs money, needs a credential, or touches anything shared waits for your yes.

Chat gets only a summary:

```
Plan: #42 Export orders as CSV · size/M · base main
6 done-when · 6 slices · 1 doc · 1 probe · 3 walks · 2 videos · 1 fork answered (A, stream)
http://127.0.0.1:8765/plan-acme-shop-42.html
Say ok, or name a ref (S2, W1, D3, #4) and what to change.
```

A `ready-to-build` ticket takes a short path: its Steps are trusted and only the gaps are read.

## Needs

- `gh`, signed in, and `git`.
- `python3`, to check for claims and to build and serve the page. `curl` and `lsof` for the local server.
- A browser (`open` on macOS, `xdg-open` on Linux). Without one, the `to-artifact` skill (not in this repo) publishes the page instead.
- Sub-agents that read code (Explore agents in Claude Code, with web search for library docs; Codex reads the files itself), and sub-agents that run commands for probes (general-purpose in Claude Code; Codex runs them itself).
- From the shared core: [facts.md](../../shared-skill-core/facts.md), [grilling.md](../../shared-skill-core/grilling.md) for the question format and how to pick, [issue-rules.md](../../shared-skill-core/issue-rules.md) for the gate, [plan-page.md](../../shared-skill-core/plan-page.md) for the page, and [serve.sh](../../shared-skill-core/serve.sh) to serve the page.

## Fits with

- Takes tickets from [to-issue](../to-issue/) and runs from [to-epic](../to-epic/).
- Sends a failed gate to [grill](../grill/) or [triage](../triage/).
- Its plan goes to [build-and-prove](../build-and-prove/), which builds it on your machine with proofbox, or to [handoff](../handoff/), which sends it to Devin or Cursor. [ship](../ship/) picks one.
- [ship](../ship/) runs it as its first step, and [kickoff](../kickoff/) runs it in a new pane.

## Tests

The cases for [claims.py](scripts/claims.py) are in [tests/claims.sh](tests/claims.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.

The cases for [prune.sh](scripts/prune.sh) are in [tests/prune.sh](tests/prune.sh). It deletes a plan once its issues are closed, and a plan with no issue 30 days after its file last changed.

The cases for [build-page.py](scripts/build-page.py) are in [tests/build-page.sh](tests/build-page.sh), with Markdown inputs and expected page data in [tests/build-page/](tests/build-page/).

A plan with no issue must end with a `## Brief` block that holds a `Task:` line and a `Done when:` list; the builder refuses it without one, since the build prompt quotes them.

The agent writes only the Markdown, never `DATA`. On an invalid block the builder names each problem, writes no page, and leaves an existing page in place.

A slice can prove several lines joined by `and` or commas. A map's quoted file locations stay whole, even when a path contains a comma.

## Credits

The idea of planning test-first slices for an agent to build comes from the `tdd` and `implement` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Thanks. No text was copied.
