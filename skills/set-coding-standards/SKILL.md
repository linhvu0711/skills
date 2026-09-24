---
name: set-coding-standards
description: "Run the coding-standards audit, grill the user on its findings, then write CODING_STANDARDS.md plus the tool configs that enforce it. Points CLAUDE.md and AGENTS.md at the file. No commit."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

You establish one source of truth for how code is written in this repo:
`CODING_STANDARDS.md` at the root, enforced by the tools the project already
has, pointed at from `CLAUDE.md` and `AGENTS.md`. The audit finds what is
true. The grill settles what is wanted. Then you write.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Audit.** Invoke the `audit-coding-standards` skill with the Skill
   tool and run it to its report. Its verdict decides:

   - Empty repo: repeat what the audit said. Stop.
   - `clean`: say it is clean, repeat the areas checked. Stop.
   - `needs work`: continue at step 2 with the report as the seed.

   Done when the report is in chat with a verdict.

2. **Grill.** Invoke the `grill` skill with the Skill tool. Seed: the
   audit report. Open decisions: fold scattered rules into one
   `CODING_STANDARDS.md` or keep them where they are; for each drifted
   rule, keep and enforce, or change the rule; for each gap, add a rule
   or leave the area out on purpose; for each proposal, accept, change,
   or drop. Then continue at step 3.

3. **Write.** Files in the working tree, nothing else:

   - `CODING_STANDARDS.md` at the root, in the shape under `File shape`. Every
     settled rule is in it. Rules folded in from other files are removed
     from those files.
   - `.editorconfig`, written or updated to match.
   - Configs of tools the project already has, updated so each rule a tool
     can check is checked. New tools and CI changes become issues in step 4.
   - `CLAUDE.md` and `AGENTS.md`, where they exist: one line, "Read
     `CODING_STANDARDS.md` before you write or review code." Code rules that
     lived in these files now live in `CODING_STANDARDS.md` and are gone from
     here.

   Done when every settled rule is in `CODING_STANDARDS.md` exactly once, every
   tool-checkable one is in a config, and `git status` lists only the files
   above.

4. **Hand off.** In chat:

   - Files changed, one line each.
   - Drift kept as code problems: one line per rule with count and the
     issue you recommend for it (`fix` ticket, or a `chore` when it is a
     sweep). Name `/to-issue` for one, `/capture` for a seed.
   - New tools or CI the rules need: one recommended issue each.
   - Last line: `Ready for /make-commit` or `Ready for /create-pr`.

## File shape

`CODING_STANDARDS.md` reads as rules, one per line, grouped by area heading in
the order of the `Areas` table in
`../audit-coding-standards/SKILL.md`. Each rule states the
positive form: "Files are `kebab-case`", "Errors are returned, never thrown
across a module edge". A rule a tool checks names the tool in brackets at
the end: `[prettier]`, `[ruff E501]`. A rule with a reason that is not
obvious gets one sentence of why under it. Areas left out on purpose are
listed once at the end under "Not covered", so the next reader knows it
was a choice.

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.

## Examples

**User:** `/set-coding-standards` in a fresh Next.js scaffold, 4 source files.

The audit finds `.eslintrc.json` and `.prettierrc` from the template, no
prose rules. Small bucket, stack Next.js with TypeScript. Proposals from
the Next.js and TypeScript defaults, one per area. Verdict: needs work.
Grill: each proposal is a question with the default as the recommended
answer. Write `CODING_STANDARDS.md`, `.editorconfig`, tighten
`tsconfig.json` strictness as agreed. No `CLAUDE.md` exists, so none is
written. Last line: `Ready for /make-commit`.

**User:** `/set-coding-standards` in a 3-year-old Django monolith, 900 files, 6
authors.

The audit finds `CONTRIBUTING.md` with a "Code style" section and rules in
`CLAUDE.md`. Big bucket. Outdated: `CONTRIBUTING.md` names `flake8`, but
`ruff.toml` replaced it. Drift: "views are class-based", 61 function
views, three examples. Gaps: Logging, API shape. Grill: fold both files
into `CODING_STANDARDS.md` (yes), the view rule (keep, enforce), Logging (add:
`structlog`, agreed fields), API shape (left out, no public API). Write
`CODING_STANDARDS.md`, strip the section from `CONTRIBUTING.md`, strip the
rules from `CLAUDE.md` and leave the pointer line, update `ruff.toml`.
Hand off: one `chore` issue for the 61 function views, `Ready for
/create-pr`.

**User:** `/set-coding-standards` in a repo with a good `CODING_STANDARDS.md`, touched
last month, no drift, no gaps.

The audit's verdict is clean. Say so, repeat the areas checked, stop.

**User:** `/set-coding-standards` in a repo with only a README.

The audit reports an empty bucket. Repeat it: no source files, a manifest
or a first module is what would start the standard. Stop.
