# audit-coding-standards

Checks how your repo writes code against the rules it says it follows, and reports what is outdated, broken, or missing. It changes nothing.

## Use it when

You want to know if your coding rules still match the code: "audit our conventions", "check for drift against CODING_STANDARDS.md", or `/audit-coding-standards`. The agent can also pick it up on its own from those phrases, and [set-coding-standards](../set-coding-standards/) runs it as its first step.

## What you get

One report in chat, then it stops. Drift comes with a count and three `file:line` examples. In a repo with no rules file you get proposals instead, one per area (names, layout, errors, logging, tests, and so on), taken from the stack's defaults or from what most of the code already does.

```
Stack: Python, Django, ruff       Size: big, 900 files, 6 authors
Rules found in: CONTRIBUTING.md, CLAUDE.md
Outdated: "run flake8" — ruff.toml replaced it
Drift: "views are class-based" — 61, e.g. shop/views.py:40 ×3
Gaps: Logging, API shape
Verdict: needs work
```

## Needs

- `git`, for the author count and the age of the rules file.
- The shared core file `../../shared-skill-core/facts.md`.
- An agent that can start subagents, for sampling the code in big repos.

## Fits with

- Called by [set-coding-standards](../set-coding-standards/), which turns the report into a `CODING_STANDARDS.md`.
