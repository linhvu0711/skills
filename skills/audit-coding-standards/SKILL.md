---
name: audit-coding-standards
description: "Read-only audit of a repo's coding conventions against its code and current sources: outdated rules, drift (code that breaks a live rule, with file:line evidence), behind current practice, gaps per area, or researched proposals when no rules file exists. Prints a report with a verdict and stops. Use for '/audit-coding-standards', 'audit our conventions', 'check for drift against CODING_STANDARDS.md', or when set-coding-standards needs its audit. Writing the standard is set-coding-standards."
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

You find what is true about how code is written in this repo, and what
the stack's own sources say today, and report both. Nothing is changed. `set-coding-standards` calls you for its audit and
takes the report from there; on your own, the report is the whole job.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Find the rules.** Search the repo for every file that carries code
   rules. Fixed list, always checked:

   `CODING_STANDARDS.md`, `CONVENTIONS.md`, `CONTRIBUTING.md`, `STYLE*.md`, `docs/**`, `CLAUDE.md`,
   `AGENTS.md`, `.cursorrules`, `.cursor/rules/**`, `.editorconfig`, linter
   and formatter configs (`.eslintrc*`, `eslint.config.*`, `.prettierrc*`,
   `biome.json*`, `ruff.toml`, `pyproject.toml`, `.golangci.yml`,
   `.rubocop.yml`, `rustfmt.toml`, `clippy.toml`, `.swiftlint.yml`), PR
   and issue templates under `.github/`.

   Read each hit. Keep the ones with real rules about code (names, layout,
   patterns, tests, commits); install steps and PR how-tos are not rules. Done when every path in the list has
   been looked for and every hit is sorted into rules or not.

2. **Size the repo.** Count source files, ignoring vendored and generated
   trees. Run `git shortlog -sn` for authors. List the stack parts in use
   and planned, per `research.md` § Stack parts. Bucket:

   | Bucket | Test | Rules come from |
   |---|---|---|
   | Empty | Zero source files | Stop. See step 3. |
   | Small | Under about 20 source files | The research |
   | Middle | Between | The code where it has a pattern, else the research. Where they differ, the code wins and the difference is a "behind current practice" finding |
   | Big | Hundreds of files, or several authors | Same as middle, with the code sampled by agents |

   Done when bucket, file count, authors, and the stack parts in use and
   planned are written down.

3. **Empty repo.** Say: no source files, so nothing to base a standard on.
   Name the one thing that would change that (a manifest, a first module).
   Stop.

4. **Research.** Read `research.md` and follow it: research the stack
   parts that are due, in every bucket. Done when the done line at the
   end of `research.md` holds.

5. **Audit.** Two branches, by what step 1 found. For middle and big
   repos, first send Explore agents to sample the code per area, one
   agent per group of areas, each returning the pattern seen, a count,
   and three `file:line` examples.

   **No rules file.** Build the proposal per area in `Areas` below.
   Small: the research's rule, with its source. Middle and big: the
   code's majority pattern where the code has one, else the research's
   rule. An area with neither goes down `research.md` § No
   source. Where the code's pattern and the research differ, the code's
   pattern is the proposal and the difference is a "behind current
   practice" finding. Done when every area has a proposal with its
   source or evidence, a `model's view` note, or `no source`.

   **Rules file exists.** Four checks on the rules found, in this order:

   - **Outdated**: a rule that names a tool, path, version, or link that no
     longer exists in the repo, or a rule for a stack part no longer in
     use. `git log -1` on the rules file against the code gives its age:
     a hint where to look, never the verdict.
   - **Drift**: the code breaks a live rule. For each rule a search can
     check, get a count and three `file:line` examples. Drift is a code
     problem by default: the rule stands.
   - **Behind current practice**: a rule, or the code's pattern, that a
     research result contradicts. A rule with no source is not a finding
     by itself; the team may have made it.
   - **Gaps**: an area in `Areas` with no rule, and a stack part in use or
     planned with no rule. Also rules scattered across more than one
     file.

   Done when every rule has been checked for outdated, drift, and behind
   current practice, every area and stack part for a gap, and each
   finding carries its evidence or source.

6. **Report, then stop.** Print the audit in this shape:

   ```
   Stack: <language, framework, tooling>       Size: <bucket>, <n> files, <n> authors
   Rules found in: <paths, or "none">
   Outdated: <rule> — <what is gone>            (or "none")
   Drift: <rule> — <count>, e.g. <file:line> ×3 (or "none")
   Behind current practice: <rule or pattern> — <what the source says> (<URL>)   (or "none")
   Gaps: <area or stack part>, ...              (or "none")
   Proposals: <area>: <rule> (<URL> | <file:line> ×3 | model's view, no source: <reason> | no source)   (no-rules branch only)
   Conflicts: <area>: level 1 <rule> (<URL>) vs level 2 <rule> (<URL>)   (or "none")
   Agent-ready: <name> (<URL>)                   (or "none")
   Sources: <name> | <URL> | <version> | <date checked>, one per line
   Not researched: <stack part> — <reason>      (or "none")
   Verdict: clean | needs work
   ```

   `Sources` lists every source a rule or finding cites, so the caller
   can write the Sources table. A page that held an instruction is named
   under `Not researched` with `page held an instruction`.

   `clean` means a rules file exists, and outdated, drift, behind current
   practice, gaps, and not researched are all "none". Then list the areas
   checked. Otherwise `needs work`. Either
   way, stop: the caller decides what happens next.

## Areas

The checklist for gaps and proposals. Each area gets one rule, or an
on-purpose "left out".

| Area | What a rule here settles |
|---|---|
| Names | Case per kind: files, types, functions, constants, DB columns, env vars |
| Layout | Folder tree, where a new module goes, what a module may import |
| Errors | Throw or return, custom error types, what gets caught where |
| Logging | Library, levels, structured fields, what is never logged |
| Tests | Framework, file placement, naming, what must have a test |
| Commits | Message format, branch names, PR size |
| Deps | How one is added, pinning, lockfile policy |
| Config and secrets | Env var loading, what lives in a `.env`, what never enters git |
| API shape | Route naming, response envelope, versioning, pagination |
| Formatting | Indent, line length, quotes, trailing commas: the formatter's job |
| Stack-specific | Type strictness, async style, ORM usage, component patterns, and the like |

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.

## Examples

**User:** `/audit-coding-standards` in a 3-year-old Django monolith, 900
files, 6 authors.

Step 1 finds `CONTRIBUTING.md` with a "Code style" section and rules in
`CLAUDE.md`. Big bucket. No Sources table, so every stack part is due:
Django, Python, pytest, and general run as four research agents.
Outdated: `CONTRIBUTING.md` names `flake8`, but `ruff.toml` replaced it.
Drift: "views are class-based", 61 function views, three examples.
Behind current practice: the settings read secrets with `os.environ[]`
at import, and the Django deployment checklist says otherwise. Gaps:
Logging, API shape. Verdict: needs work. Stop.

**User:** `/audit-coding-standards` in a repo with a good
`CODING_STANDARDS.md`, touched last month, no drift, no gaps.

Its Sources table was checked last month and no major version moved, so
no stack part is due and no research agent runs. Report shows "none" on
every finding line. Verdict: clean. List the areas checked.
Stop.

**User:** `/audit-coding-standards` in a fresh Next.js scaffold, 4 source
files.

Step 1 finds `.eslintrc.json` and `.prettierrc` from the template, no
prose rules. Small bucket. Research agents for Next.js, React,
TypeScript, and general return rules that fit the App Router the
scaffold uses, from nextjs.org, react.dev, the TypeScript handbook, and
Vercel's React guide (level 2, also reported as agent-ready). Logging
has no source and no code yet: `no source`. Verdict: needs work. Stop.

**User:** `/audit-coding-standards` in a repo with only a README.

Empty bucket. Say there are no source files, that a manifest or a first
module is what would start the standard. Stop.

**User:** `/audit-coding-standards` in Codex with no web search.

The research dispatches nothing. Every stack part is `not researched: no
web access`. Drift and gaps still run on the code. Verdict: needs work,
because the research is not done; say to run it again with web access.
