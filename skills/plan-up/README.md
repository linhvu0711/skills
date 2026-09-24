# plan-up

Turns a ready GitHub issue, or a run of tickets from an epic, into a plan that a coding agent can follow cold: seams, tests, slices, UI walks, and video scripts. It plans and never builds.

## Use it when

You have a ticket that passes the readiness gate and you want it built by an agent that has no taste and can't cheaply ask you questions. Type `/plan-up` with the target (`$plan-up` in Codex):

- `/plan-up <issue-url>`: one ticket, one PR.
- `/plan-up <epic-url> #12 #14`: those tickets from the epic, as a stack of PRs.
- `/plan-up <issue-url> #14 #15`: a set of plain tickets, stacked the same way.
- `/plan-up <epic-url>`: every open ticket in the epic.
- `/plan-up <issue-url> on <pr-url>`: one more layer on an open stack.

It needs a clean tree on the base branch. A ticket that fails the gate comes back as a list of questions for [grill](../grill/) or [diagnose](../diagnose/).

## What you get

A plan file, `plan-<owner>-<repo>-<n>.md` under `~/.agents/artifacts/plan/`, and the same plan as an HTML page opened in your browser. It holds one Proof row per Done-when line, the seams, one slice per change in tracer-bullet order, each with the tests that prove it (Given, When, and a literal Then), UI walks and videos when the ticket has a screen, the gates, and every small decision it made, so you can veto any of them by name. Big decisions, and every new dependency, are asked in chat first, one question at a time.

Chat gets only a summary:

```
Plan: #42 Export orders as CSV · size/M · base main
6 done-when · 6 slices · 3 walks · 2 videos · 1 fork answered (A, stream)
http://127.0.0.1:8765/plan-acme-shop-42.html
Say ok, or name a ref (S2, W1, D3, #4) and what to change.
```

A `handoff-ready` ticket takes a short path: its Steps are trusted and only the gaps are read.

## Needs

- `gh`, signed in, and `git`.
- `python3`, to build, serve, and check the page. `curl` and `lsof` for the local server.
- A browser (`open` on macOS, `xdg-open` on Linux). Without one, the `to-artifact` skill (not in this repo) publishes the page instead.
- Sub-agents that read code (Explore agents in Claude Code, with web search for library docs; Codex reads the files itself).
- From the shared core: [facts.md](../../shared-skill-core/facts.md), [grilling.md](../../shared-skill-core/grilling.md) for the question format, [issue-rules.md](../../shared-skill-core/issue-rules.md) for the gate, and [plan-page.md](../../shared-skill-core/plan-page.md) for the page.

## Fits with

- Takes tickets from [to-issue](../to-issue/) and runs from [to-epic](../to-epic/).
- Sends a failed gate to [grill](../grill/) or [diagnose](../diagnose/).
- Its plan goes to [handoff-devin](../handoff-devin/) or [handoff-cursor](../handoff-cursor/).
- [ship](../ship/) runs it as its first step, and [kickoff](../kickoff/) runs it in a new pane.

## Credits

The idea of planning test-first slices for an agent to build comes from the `tdd` and `implement` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Thanks. No text was copied.
