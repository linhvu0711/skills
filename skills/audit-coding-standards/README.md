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

On `needs work`, the grill starts at once: one question per finding, with a recommended answer. When it ends, the settled changes go into `CODING_STANDARDS.md` and the tool configs, nothing else moves, and nothing is committed: the changes and any glossary entry or ADR the grill wrote wait together on your branch. The chat ends with the files changed, the drift left as code problems, and `Ready for /commit`. Each rule goes in through the same shared step as in set: it first looks for a rule that already says it, and a tool setting is written only when no code breaks it today, or when the tool can limit it to new code; otherwise the setting is named in the issue that fixes the code. A rule a tool checks lives only in that tool's config; the Standard does not repeat it. To keep only the report, say stop at the first question. Stop later and the Standard and configs stay as they are; the decisions made so far are printed so you can reuse them.

On `clean`, the only change is the date and version on the Sources table rows it checked again. When it changes those rows, an older Standard also gets brought up to date: the three opening lines that explain its marks, the Layout area renamed Structure, and the Sources table moved from the end of `CODING_STANDARDS.md` to `docs/standards/sources.md`. An old line tagged with a tool, as `[eslint]`, is removed when that tool's config has the check on for every file the line covers, since the config holds the rule; otherwise the line stays and loses its tag. Checks that are on in a tool's config count as rules, and the tool reports their breaks where your repo runs it, such as in CI; the audit runs no tool. The other rules stay where they are.

Research only runs for the stack parts that are due. It reads the Sources table in `docs/standards/sources.md` (the Standard's shape is in [standard.md](../../shared/coding-standards/standard.md)) and checks a part again only after a major version bump, after 6 months, or when the part has no row yet. Each finding cites what it came from: a page read on this run, or what most of the code already does, never the model's memory. The details are in [research.md](../../shared/coding-standards/research.md).

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- The [grill](../grill/) skill, which it uses to ask you about each finding.
- The shared core files `../../shared/facts.md` and `../../shared/coding-standards/` (`checks.md`, `research.md`, `standard.md`, `write.md`), which it shares with set.
- `git`, for the author count and the age of the rules file.
- `gh`, to read open issues for planned work.
- Web search or the context7 MCP server, for the research. Without them the code checks still run, the research is marked not done, and the hand-off tells you to run it again with web access.
- An agent that can start subagents, for the research and for sampling the code.

## Fits with

- Takes over from [set-coding-standards](../set-coding-standards/), which writes the first `CODING_STANDARDS.md`.
- Calls [grill](../grill/).
- Hands off to [commit](../commit/) or [make-pr](../make-pr/), and names [to-issue](../to-issue/) or [capture](../capture/) for drift left as code problems.
