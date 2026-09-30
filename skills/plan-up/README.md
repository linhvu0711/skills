# plan-up

Turns a ready GitHub issue, or a run of tickets from an epic, into a plan that a coding agent can follow cold: seams, tests, slices, doc updates, UI walks, and video scripts. It plans and never builds, and it leaves your repo as it found it.

## Use it when

You have a ticket that passes the readiness gate and you want it built by an agent that has no taste and can't cheaply ask you questions. Type `/plan-up` with the target (`$plan-up` in Codex):

- `/plan-up <issue-url>`: one ticket, one PR.
- `/plan-up <epic-url> #12 #14`: those tickets from the epic, as a stack of PRs.
- `/plan-up <issue-url> #14 #15`: a set of plain tickets, stacked the same way.
- `/plan-up <epic-url>`: every open ticket in the epic.
- `/plan-up <issue-url> on <pr-url>`: one more layer on an open stack.

It reads every ticket with its comments, since a later comment can change what the ticket asks. It needs a clean tree on the base branch. A ticket that fails the gate comes back as a list of questions for [grill](../grill/) or [triage](../triage/).

## What you get

A plan file, `plan-<owner>-<repo>-<n>.md` under `~/.agents/artifacts/plan/`, and the same plan as an HTML page opened in your browser.

The page opens on a Review tab, written for you, the person who approves the plan: what changes, the approach and why not the other way, the blast radius (the parts it touches, and whether it adds a dependency, a schema change, an API, config, or CI), the choices you should know about, at most three risks, how we know it works, and the scope. Each part has a size limit, and the check fails a page that breaks one. A run shows the whole stack first, then a small block for each layer.

Under the blast radius sits a change map, drawn only when the plan adds or removes a part, moves a job between parts, or changes what flows between them. A box is a part with a job, named in your repo's words; an arrow is what moves, never an import; a gray area is the app or package. Green is new, amber is a changed job, red is removed, and a dashed border is outside the repo. An arrow finds its own way around the boxes, and its label sits where it covers no box or other label. Point at a box to see its files, and name its ref (`M3`) in chat to change it. A run gets one map for the whole stack, with each change tagged by its layer. The check keeps every name, job, and arrow label short enough to fit, and fails when the page's map says something the plan does not.

The tabs after it are for the agent that builds. The plan holds the facts it proved by a probe, one Proof row per Done-when line, the seams, one slice per change in tracer-bullet order, each with the tests that prove it (Given, When, and a literal Then) and the docs its change makes stale, so code and docs land in one commit, UI walks and videos for each line a person checks by looking (a web page, a window, or a command's output in a terminal), a before shot for each walk that changes a screen that exists already, the gates, and every small decision it made, so you can veto any of them by name. Big decisions, and every new dependency, are asked in chat first, one question at a time.

When reading leaves a doubt the plan hangs on (does this tool do what we need, what does this API really return), it runs a small probe first, in a temp folder or a throwaway worktree, never in your tree. Probes run in parallel sub-agents, like the code search. Only doubts that change the plan get a probe. A free, safe probe runs on its own; one that costs money, needs a credential, or touches anything shared waits for your yes.

Chat gets only a summary:

```
Plan: #42 Export orders as CSV · size/M · base main
6 done-when · 6 slices · 1 doc · 1 probe · 3 walks · 2 videos · 1 fork answered (A, stream)
http://127.0.0.1:8765/plan-acme-shop-42.html
Say ok, or name a ref (S2, W1, D3, #4) and what to change.
```

A `handoff-ready` ticket takes a short path: its Steps are trusted and only the gaps are read.

## Needs

- `gh`, signed in, and `git`.
- `python3`, to build, serve, and check the page. `curl` and `lsof` for the local server.
- A browser (`open` on macOS, `xdg-open` on Linux). Without one, the `to-artifact` skill (not in this repo) publishes the page instead.
- Sub-agents that read code (Explore agents in Claude Code, with web search for library docs; Codex reads the files itself), and sub-agents that run commands for probes (general-purpose in Claude Code; Codex runs them itself).
- From the shared core: [facts.md](../../shared-skill-core/facts.md), [grilling.md](../../shared-skill-core/grilling.md) for the question format, [issue-rules.md](../../shared-skill-core/issue-rules.md) for the gate, and [plan-page.md](../../shared-skill-core/plan-page.md) for the page.

## Fits with

- Takes tickets from [to-issue](../to-issue/) and runs from [to-epic](../to-epic/).
- Sends a failed gate to [grill](../grill/) or [triage](../triage/).
- Its plan goes to [handoff-devin](../handoff-devin/) or [handoff-cursor](../handoff-cursor/).
- [ship](../ship/) runs it as its first step, and [kickoff](../kickoff/) runs it in a new pane.

## Credits

The idea of planning test-first slices for an agent to build comes from the `tdd` and `implement` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Thanks. No text was copied.
