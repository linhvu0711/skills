---
name: set-coding-standards
description: "Run the coding-standards audit, grill the user on its findings, then write CODING_STANDARDS.md, each rule tied to a source read on the run, plus the tool configs that enforce it. Points CLAUDE.md and AGENTS.md at the file. No commit."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

You write one source of truth for how code is written in this repo:
`CODING_STANDARDS.md` at the root, enforced by the tools the project already
has, pointed at from `CLAUDE.md` and `AGENTS.md`. The audit finds what is
true and what current sources say, the grill settles what is wanted,
then you write. A rule comes from a source the audit read, the code, or
the user; `../audit-coding-standards/research.md` defines the source
levels.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Audit.** Invoke the `audit-coding-standards` skill with the Skill
   tool and run it to its report. Its verdict decides:

   - Empty repo: repeat what the audit said. Stop.
   - `clean`: say it is clean, repeat the areas checked. When the audit
     re-checked sources, set their date checked in the Sources table to
     today; that file is the only change. Stop.
   - `needs work`: continue at step 2 with the report as the seed.

   Done when the report is in chat with a verdict.

2. **Grill.** Invoke the `grill` skill with the Skill tool. Seed: the
   audit report. Open decisions: fold scattered rules into one
   `CODING_STANDARDS.md` or keep them where they are; for each drifted
   rule, keep and enforce, or change the rule; for each gap, add a rule
   or leave the area out on purpose; for each proposal, accept, change,
   or drop; for each "behind current practice" finding, change the code
   (a `chore` issue) or keep the code's way as the rule; for each
   conflict, the level 1 rule or the level 2 rule, with both links shown;
   for each `model's view, no source` note, keep the pattern or change
   it; for each `no source` area, the user writes the rule or leaves the
   area out. A stack part the user names as planned during the grill is
   researched per `../audit-coding-standards/research.md` before its
   areas are settled. Then continue at step 3.

3. **Write.** Files in the working tree, nothing else:

   - `CODING_STANDARDS.md` at the root, in the shape under `File shape`. Every
     settled rule is in it. Rules folded in from other files are removed
     from those files.
   - `docs/standards/<topic>.md` for a topic past about 40 rules, per
     `File shape`.
   - `.editorconfig`, written or updated to match.
   - Configs of the tools the project already has, so each rule a tool can
     check is checked. New tools and CI changes become issues in step 4.
   - `CLAUDE.md` and `AGENTS.md`, where they exist: one line, "Read
     `CODING_STANDARDS.md` before you write or review code."

   Done when every settled rule is in `CODING_STANDARDS.md` or one topic
   file exactly once, every rule from a source names a row of the
   Sources table, every tool-checkable rule is in a config, and
   `git status` lists only the files above.

4. **Hand off.** In chat:

   - Files changed, one line each.
   - Drift kept as code problems: one line per rule with count and the
     issue you recommend for it (`fix` ticket, or a `chore` when it is a
     sweep). Name `/to-issue` for one, `/capture` for a seed.
   - New tools or CI the rules need: one recommended issue each.
   - Agent-ready sources the audit found: one line each, "you can install
     <name> as an extra: <URL>".
   - Stack parts under `Not researched`: name them, and say to run
     `/set-coding-standards` again with web access.
   - Last line: `Ready for /commit` or `Ready for /make-pr`.

## File shape

`CODING_STANDARDS.md` reads as rules, one per line, grouped by area heading in
the order of the `Areas` table in
`../audit-coding-standards/SKILL.md`. Each rule states the
positive form: "Files are `kebab-case`", "Errors are returned, never thrown
across a module edge". Each rule is in our own words, never the source's
text copied. A rule from a source ends with the source's name in
parentheses, then a rule a tool checks names the tool in brackets:
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

| Name | Link | Version | Checked |
|---|---|---|---|
| react-docs | https://react.dev/reference/rules | 19 | 2026-09-30 |
```

`Version` is the stack part's version the source covers, or `-` when it
has none. `Checked` is the date the audit read it. A later audit reads
this table to know which sources are due.

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.

## Examples

**User:** `/set-coding-standards` in a fresh Next.js scaffold, 4 source files.

The audit finds `.eslintrc.json` and `.prettierrc` from the template, no
prose rules. Small bucket, stack Next.js with TypeScript. Proposals from
nextjs.org, react.dev, and the TypeScript handbook, one per area, each
with its link; Vercel's React guide is level 2 and agent-ready. Logging
is `no source`. Verdict: needs work. Grill: each proposal is a question
with the sourced rule as the recommended answer; Logging is left out.
Write `CODING_STANDARDS.md` with the Sources table, `.editorconfig`,
tighten `tsconfig.json` strictness as agreed. No `CLAUDE.md` exists, so
none is written. Hand-off offers Vercel's guide as an extra install.
Last line: `Ready for /commit`.

**User:** `/set-coding-standards` in a 3-year-old Django monolith, 900 files, 6
authors.

The audit finds `CONTRIBUTING.md` with a "Code style" section and rules in
`CLAUDE.md`. Big bucket. Outdated: `CONTRIBUTING.md` names `flake8`, but
`ruff.toml` replaced it. Drift: "views are class-based", 61 function
views, three examples. Behind current practice: secrets read at import,
against the Django deployment checklist. Gaps: Logging, API shape.
Grill: fold both files into `CODING_STANDARDS.md` (yes), the view rule
(keep, enforce), Logging (add: `structlog`, agreed fields), secrets
(change the code), API shape (left out, no public API). Write
`CODING_STANDARDS.md` with the Sources table, strip the section from
`CONTRIBUTING.md`, strip the rules from `CLAUDE.md` and leave the pointer
line, update `ruff.toml`.
Hand off: one `chore` issue for the 61 function views and one for the
secrets change, `Ready for /make-pr`.

**User:** `/set-coding-standards` in a repo with a good `CODING_STANDARDS.md`, touched
last month, no drift, no gaps.

The audit's verdict is clean. Say so, repeat the areas checked, stop.

**User:** `/set-coding-standards` in a repo whose Sources table was
checked 7 months ago; the sources still agree with every rule.

The audit re-checks those sources and its verdict is clean. Set their
date checked to today, say so, stop.

**User:** `/set-coding-standards` in a repo with only a README.

The audit reports an empty bucket. Repeat it: no source files, a manifest
or a first module is what would start the standard. Stop.
