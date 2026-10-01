---
name: set-coding-standards
description: "Make a repo's first CODING_STANDARDS.md: research the stack, read the code and any scattered rules, grill the user, then write the Standard and the tool configs that enforce it. No commit."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

You set up the repo's first Standard: `CODING_STANDARDS.md` at the root,
enforced by the tools the project already has, pointed at from
`CLAUDE.md` and `AGENTS.md`. The research finds what current sources
say, the code shows what is true, scattered rules show what the team
already wrote, the grill settles what is wanted, then you write. Once
the Standard exists, `audit-coding-standards` checks and changes it.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Gate.** `CODING_STANDARDS.md` exists at the root: say "A Standard
   already exists. Run `/audit-coding-standards` to check and change
   it." Stop. Done when you know the root has no `CODING_STANDARDS.md`.

2. **Find and size.** Read `../../shared-skill-core/coding-standards/checks.md`.
   Run its `Find the rules` and `Size the repo`. Every rule found is
   scattered. Empty bucket: say what the table says, stop.

3. **Research.** Read `../../shared-skill-core/coding-standards/research.md`
   and follow it. With no Sources table, every stack part is due.
   Done when the done line at the end of `research.md` holds.

4. **Read the code and the scattered rules.** Run `Sample the code`.
   Then run the first three checks of `Check the rules` (outdated,
   drift, behind current practice) on the scattered rules.

   Build one proposal per area in `Areas`, the first that applies:

   - A scattered rule for the area that is not outdated: that rule,
     marked `scattered: <path>`, with its drift and behind findings.
   - Small bucket: the research's rule, with its source.
   - Middle and big: the code's majority pattern where the code has
     one, else the research's rule. Where the pattern and the research
     differ, the pattern is the proposal and the difference is a
     "behind current practice" finding.
   - Neither: down `research.md` § No source.

   Done when every scattered rule is checked, and every area has a
   proposal with its source or evidence, a `model's view` note, or
   `no source`.

5. **Report.** Print the report in `checks.md` § Report shape, the set
   lines. Done when it is in chat.

6. **Grill.** Read `../../shared-skill-core/coding-standards/write.md`
   and run its `Grill` with the report as the seed. A stopped grill
   ends the run there.

7. **Write.** Run `write.md` § Write. Every scattered rule the grill
   folded in leaves its old file.

8. **Hand off.** Run `write.md` § Hand off.

## Examples

**User:** `/set-coding-standards` in a fresh Next.js scaffold, 4 source files.

No `CODING_STANDARDS.md`. Find: `.eslintrc.json` and `.prettierrc` from
the template, no prose rules, so nothing is scattered. Small bucket.
Research agents for Next.js, React, TypeScript, and general return
proposals from nextjs.org, react.dev, and the TypeScript handbook, one
per area, each with its link; Vercel's React guide is level 2 and
agent-ready. Logging is `no source`. Grill: each proposal is a question
with the sourced rule as the recommended answer; Logging is left out.
Write `CODING_STANDARDS.md` with the Sources table, `.editorconfig`,
tighten `tsconfig.json` strictness as agreed. No `CLAUDE.md` exists, so
none is written. Hand-off offers Vercel's guide as an extra install.
Last line: `Ready for /commit`.

**User:** `/set-coding-standards` in a 3-year-old Django monolith, 900 files, 6
authors, no `CODING_STANDARDS.md`.

Find: `CONTRIBUTING.md` with a "Code style" section and rules in
`CLAUDE.md`, all scattered. Big bucket. Checks on the scattered rules:
`CONTRIBUTING.md` names `flake8`, but `ruff.toml` replaced it
(outdated). "Views are class-based" has 61 function views (drift).
Secrets are read at import, against the Django deployment checklist
(behind current practice). Proposals: the scattered rules where they
hold, the code's pattern for Names and Tests, the research for
Logging, `no source` for API shape. Grill: fold both files in (yes),
the view rule (keep, enforce), Logging (add: `structlog`, agreed
fields), secrets (change the code), API shape (left out, no public API).
Write `CODING_STANDARDS.md` with the Sources table, strip the section
from `CONTRIBUTING.md`, strip the rules from `CLAUDE.md` and leave the
pointer line, update `ruff.toml`. Hand off: one `chore` issue for the
61 function views and one for the secrets change, `Ready for /make-pr`.

**User:** `/set-coding-standards` in a repo that has `CODING_STANDARDS.md`.

Say a Standard already exists, and to run `/audit-coding-standards`.
Stop.

**User:** `/set-coding-standards`, and at the fourth grill question:
"stop, I'll finish this later."

Write nothing. Print the three settled decisions, one per line, and
stop.

**User:** `/set-coding-standards` in a repo with only a README.

Empty bucket. Say there are no source files, that a manifest or a first
module is what would start the standard. Stop.
