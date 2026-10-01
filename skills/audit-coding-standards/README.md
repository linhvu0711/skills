# audit-coding-standards

Checks your `CODING_STANDARDS.md` against your code and against what the stack's own docs say today, then asks you how to fix what it found and writes the changes.

## Use it when

Your repo has a `CODING_STANDARDS.md` and you want to know if it still holds: after a big upgrade, before a release, or every few months. Type `/audit-coding-standards` in the repo. It only runs when you call it. With no `CODING_STANDARDS.md` yet, it stops and points you to [set-coding-standards](../set-coding-standards/).

## What you get

First, a report with a verdict. Drift comes with a count and three `file:line` examples. Rules found outside the file (in `CLAUDE.md`, say) show up as gaps.

```
Stack: Python, Django, ruff       Size: big, 900 files, 6 authors
Rules found in: CODING_STANDARDS.md, CLAUDE.md
Outdated: "run flake8" — ruff.toml replaced it
Drift: "views are class-based" — 61, e.g. shop/views.py:40 ×3
Behind current practice: secrets read at import — the deployment checklist loads them from the environment (https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/)
Gaps: CLAUDE.md, Logging
Not researched: none
Verdict: needs work
```

On `needs work`, the grill starts at once: one question per finding, with a recommended answer. When it ends, the settled changes go into `CODING_STANDARDS.md` and the tool configs, nothing else moves, and nothing is committed: the changes and any glossary entry or ADR the grill wrote wait together on your branch. The chat ends with the files changed, the drift left as code problems, and `Ready for /commit`. To keep only the report, say stop at the first question. Stop later and the Standard and configs stay as they are; the decisions made so far are printed so you can reuse them.

On `clean`, the only change is the date and version on the Sources table rows it checked again.

Research only runs for the stack parts that are due. It reads the Sources table at the end of `CODING_STANDARDS.md` and checks a part again only after a major version bump, after 6 months, or when the part has no row yet. Each finding cites what it came from: a page read on this run, or what most of the code already does, never the model's memory. The details are in [research.md](../../shared-skill-core/coding-standards/research.md).

## Needs

- The [grill](../grill/) skill, which it uses to ask you about each finding.
- The shared core files `../../shared-skill-core/facts.md` and `../../shared-skill-core/coding-standards/` (`checks.md`, `research.md`, `write.md`), which it shares with set.
- `git`, for the author count and the age of the rules file.
- `gh`, to read open issues for planned work.
- Web search or the context7 MCP server, for the research. Without them the code checks still run, the research is marked not done, and the hand-off tells you to run it again with web access.
- An agent that can start subagents, for the research and for sampling the code. In Codex it does both itself, one after the other.

## Fits with

- Takes over from [set-coding-standards](../set-coding-standards/), which writes the first `CODING_STANDARDS.md`.
- Calls [grill](../grill/).
- Hands off to [commit](../commit/) or [make-pr](../make-pr/), and names [to-issue](../to-issue/) or [capture](../capture/) for drift left as code problems.
