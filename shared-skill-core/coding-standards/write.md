# Writing the Standard

How `set-coding-standards` and `audit-coding-standards` settle the
report with the user and write what was settled. The report comes from
`checks.md`, next to this file. A rule comes from a source the research
read, the code, or the user; `research.md` defines the source levels.

## Grill

Invoke the `grill` skill with the Skill tool. Seed: the report. Open
decisions, one per finding the report holds:

- Scattered rules: fold each file's rules into the Standard, or keep
  them where they are.
- Outdated rule: update it to what the repo has now, or drop it.
- Drifted rule: keep and enforce it, or change the rule to the code's
  way.
- Gap: add a rule, or leave the area out on purpose.
- Proposal: accept, change, or drop.
- Behind current practice: change the code (a `chore` issue), or keep
  the code's way as the rule.
- Conflict: the level 1 rule or the level 2 rule, with both links shown.
- `model's view, no source`: keep the pattern, or change it.
- `no source`: the user writes the rule, or leaves the area out.

A stack part the user names as planned during the grill is researched
per `research.md` before its areas are settled.

The grill ends with `Grill done.` and the settled list: go on to Write.
The user stops it first, at the first question or later: write
nothing. Print the decisions settled so far, one per line, so they can
go into the next run, and stop.

## Write

Files in the working tree, nothing else:

- `CODING_STANDARDS.md` at the root, in the shape under `File shape`.
  Every settled rule is in it. Rules folded in from other files are
  removed from those files.
- `docs/standards/<topic>.md` for a topic past about 40 rules, per
  `File shape`.
- `.editorconfig`, written or updated to match.
- Configs of the tools the project already has, so each rule a tool can
  check is checked. New tools and CI changes become issues in Hand off.
- `CLAUDE.md` and `AGENTS.md`, where they exist: one line, "Read
  `CODING_STANDARDS.md` before you write or review code."

The Sources table gets a row for every source in the report's
`Sources` line: a new row, or the version and date of a row already
there. A row that no rule cites any more and no stack part in use or
planned needs goes.

Done when every settled rule is in `CODING_STANDARDS.md` or one topic
file exactly once, every rule from a source names a row of the Sources
table, every tool-checkable rule is in a config, and `git status` lists
only the files above.

## File shape

`CODING_STANDARDS.md` reads as rules, one per line, grouped by area
heading in the order of `checks.md` § Areas. Each rule states the
positive form: "Files are `kebab-case`", "Errors are returned, never
thrown across a module edge". Each rule is in our own words, never the
source's text copied. A rule from a source ends with the source's name
in parentheses, then a rule a tool checks names the tool in brackets:
`Components that use state are Client Components (react-docs) [eslint]`.
A rule from the code or the user carries no source name. A rule with a
reason that is not obvious gets one sentence of why under it. Areas left
out on purpose are listed once at the end under "Not covered", so the
next reader knows it was a choice.

A topic past about 40 rules (one area, or one stack part's rules) moves
to `docs/standards/<topic>.md` in the same rule shape. Its heading stays
in `CODING_STANDARDS.md` with one line: "Rules are in
`docs/standards/<topic>.md`."

The file ends with the one Sources table, for all rules in all files:

```
## Sources

| Part | Name | Link | Version | Checked |
|---|---|---|---|---|
| react | react-docs | https://react.dev/reference/rules | 19 | 2026-09-30 |
| general | conventional-commits | https://www.conventionalcommits.org/en/v1.0.0/ | 1.0.0 | 2026-09-30 |
```

`Part` is the stack part, or `general`. `Version` is the stack part's
version the source covers, or `-` when it has none. `Checked` is the
date the research read it. A stack part that was searched and gave no
rule still gets a row, for the main page searched. The audit reads this
table to know which stack parts are due.

## Hand off

In chat:

- Files changed, one line each.
- Drift kept as code problems: one line per rule with count and the
  issue you recommend for it (`fix` ticket, or a `chore` when it is a
  sweep). Name `/to-issue` for one, `/capture` for a seed.
- New tools or CI the rules need: one recommended issue each.
- Agent-ready sources the research found: one line each, "you can
  install <name> as an extra: <URL>".
- Stack parts under `Not researched`: name them, and say to run
  `/audit-coding-standards` with web access.
- Last line: `Ready for /commit` or `Ready for /make-pr`.
