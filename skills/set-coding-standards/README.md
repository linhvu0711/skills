# set-coding-standards

Audits how your repo writes code, asks you what you want, then writes `CODING_STANDARDS.md` and the tool configs that enforce it.

## Use it when

You want one file that says how code is written here, and tools that check it. Type `/set-coding-standards` in the repo. It only runs when you call it.

## What you get

A `CODING_STANDARDS.md` at the root, one rule per line, grouped by area. Each rule comes from a source the audit read on this run, from your code, or from you, never from the model's memory. A rule from a source names it, and a Sources table at the end lists each one with its stack part, link, version, and the date it was checked. A stack part that gave no rules still gets a row, so the next audit knows it was checked. Rules a tool can check name the tool, as in `Lines are at most 88 characters [ruff E501]`. A topic with more than about 40 rules moves to `docs/standards/<topic>.md`. It also updates `.editorconfig` and the configs of the tools you already have, and adds one line to `CLAUDE.md` and `AGENTS.md` that points at the file. Rules it folds in are removed from where they lived. Nothing is committed. The chat ends with the files changed, the drift left as code problems, agent-ready sources you can install as extras, and:

```
Ready for /commit
```

## Needs

- The [audit-coding-standards](../audit-coding-standards/) skill, which it runs first.
- The [grill](../grill/) skill, which it uses to ask you about each finding.
- The shared core file `../../shared-skill-core/facts.md`.
- Web search or the context7 MCP server, for the audit's research.
- An agent that can start subagents (the audit uses them for research and code sampling).

## Fits with

- Calls [audit-coding-standards](../audit-coding-standards/) and [grill](../grill/).
- Hands off to [commit](../commit/) or [make-pr](../make-pr/).
- [audit-coding-standards](../audit-coding-standards/) points here when you want the standard written, not just checked.
