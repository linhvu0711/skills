# audit-coding-standards

Checks how your repo writes code against the rules it says it follows and against what the stack's own docs say today, and reports what is outdated, broken, behind, or missing. It changes nothing.

## Use it when

You want to know if your coding rules still match the code: "audit our conventions", "check for drift against CODING_STANDARDS.md", or `/audit-coding-standards`. The agent can also pick it up on its own from those phrases, and [set-coding-standards](../set-coding-standards/) runs it as its first step.

## What you get

One report in chat, then it stops. Drift comes with a count and three `file:line` examples. In a repo with no rules file you get proposals instead, one per area (names, layout, errors, logging, tests, and so on).

Each proposal cites what it came from: a page read on this run, or what most of the code already does. The research reads the owner's docs first (react.dev, docs.djangoproject.com), then groups that maintain a core part of the stack (Vercel for Next.js and React). Blog posts only lead to those. It covers only what your project uses or plans to add, found in the manifest, the code, open issues, ADRs, and plan docs. It never proposes a rule from the model's memory: an area with no source says so, and you decide. The details are in [research.md](research.md).

A later run reads the Sources table at the end of `CODING_STANDARDS.md`, which has a row for each stack part checked, also a part that gave no rules. It checks a part again only after a major version bump, after 6 months, or when the part has no row yet.

```
Stack: Python, Django, ruff       Size: big, 900 files, 6 authors
Rules found in: CONTRIBUTING.md, CLAUDE.md
Outdated: "run flake8" — ruff.toml replaced it
Drift: "views are class-based" — 61, e.g. shop/views.py:40 ×3
Behind current practice: secrets read at import — the deployment checklist loads them from the environment (https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/)
Gaps: Logging, API shape
Not researched: none
Verdict: needs work
```

## Needs

- `git`, for the author count and the age of the rules file.
- `gh`, to read open issues for planned work.
- Web search or the context7 MCP server, for the research. Without them the audit still checks the code, marks the research as not done, and tells you to run it again.
- The shared core file `../../shared-skill-core/facts.md`.
- An agent that can start subagents, for the research and for sampling the code. In Codex it does both itself, one after the other.

## Fits with

- Called by [set-coding-standards](../set-coding-standards/), which turns the report into a `CODING_STANDARDS.md`.
