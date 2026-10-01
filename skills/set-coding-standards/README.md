# set-coding-standards

Makes your repo's first `CODING_STANDARDS.md`: it researches your stack, reads your code and any rules you already wrote, asks you what you want, then writes the file and the tool configs that enforce it.

## Use it when

Your repo has no `CODING_STANDARDS.md` yet, and you want one file that says how code is written here, and tools that check it. Rules spread over `CONTRIBUTING.md`, `CLAUDE.md`, or `.cursor/rules/` count as no file yet: this skill checks them and moves them in. Type `/set-coding-standards` in the repo. It only runs when you call it. When the file already exists, it stops and points you to [audit-coding-standards](../audit-coding-standards/).

## What you get

First, a report: the rules it found and what is wrong with them (outdated, broken by the code, behind what the docs say now), and one proposed rule per area (names, layout, errors, logging, tests, and so on). Then a grill: one question per finding, with a recommended answer. Stop at any question and the Standard and configs are not written; the decisions made so far are printed so you can reuse them.

When the grill ends, a `CODING_STANDARDS.md` at the root, one rule per line, grouped by area. Each rule comes from a source read on this run, from your code, or from you, never from the model's memory. A rule from a source names it, and a Sources table at the end lists each one with its stack part, link, version, and the date it was checked. A stack part that gave no rules still gets a row, so the next audit knows it was checked. Rules a tool can check name the tool, as in `Lines are at most 88 characters [ruff E501]`. A topic with more than about 40 rules moves to `docs/standards/<topic>.md`. It also updates `.editorconfig` and the configs of the tools you already have, and adds one line to `CLAUDE.md` and `AGENTS.md` that points at the file. Rules it folds in are removed from where they lived. Nothing is committed. The chat ends with the files changed, the drift left as code problems, agent-ready sources you can install as extras, and:

```
Ready for /commit
```

## Needs

- The [grill](../grill/) skill, which it uses to ask you about each finding.
- The shared core files `../../shared-skill-core/facts.md` and `../../shared-skill-core/coding-standards/` (`checks.md`, `research.md`, `write.md`), which it shares with the audit.
- `git`, for the author count and the age of the rules files.
- `gh`, to read open issues for planned work.
- Web search or the context7 MCP server, for the research. Without them the code checks still run, the research is marked not done, and the hand-off tells you to run the audit later with web access.
- An agent that can start subagents, for the research and for sampling the code. In Codex it does both itself, one after the other.

## Fits with

- Calls [grill](../grill/).
- Hands off to [commit](../commit/) or [make-pr](../make-pr/), and names [to-issue](../to-issue/) or [capture](../capture/) for drift left as code problems.
- [audit-coding-standards](../audit-coding-standards/) takes over once the file exists.
