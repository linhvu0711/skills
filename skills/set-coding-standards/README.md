# set-coding-standards

Audits how your repo writes code, asks you what you want, then writes `CODING_STANDARDS.md` and the tool configs that enforce it.

## Use it when

You want one file that says how code is written here, and tools that check it. Type `/set-coding-standards` in the repo. It only runs when you call it.

## What you get

A `CODING_STANDARDS.md` at the root, one rule per line, grouped by area. Rules a tool can check name the tool, as in `Lines are at most 88 characters [ruff E501]`. It also updates `.editorconfig` and the configs of the tools you already have, and adds one line to `CLAUDE.md` and `AGENTS.md` that points at the file. Rules it folds in are removed from where they lived. Nothing is committed. The chat ends with the files changed, the drift left as code problems, and:

```
Ready for /make-commit
```

## Needs

- The [audit-coding-standards](../audit-coding-standards/) skill, which it runs first.
- The [grill](../grill/) skill, which it uses to ask you about each finding.
- The shared core file `../../shared-skill-core/facts.md`.
- An agent that can start subagents (the audit uses them on big repos).

## Fits with

- Calls [audit-coding-standards](../audit-coding-standards/) and [grill](../grill/).
- Hands off to [make-commit](../make-commit/) or [create-pr](../create-pr/).
- [audit-coding-standards](../audit-coding-standards/) points here when you want the standard written, not just checked.
