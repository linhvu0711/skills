---
name: audit-coding-standards
description: "Read-only audit of a repo's coding conventions: outdated rules, drift (code that breaks a live rule, with file:line evidence), gaps per area, or proposals when no rules file exists. Prints a report with a verdict and stops. Use for '/audit-coding-standards', 'audit our conventions', 'check for drift against CODING_STANDARDS.md', or when set-coding-standards needs its audit. Writing the standard is set-coding-standards."
---

You find what is true about how code is written in this repo, and report
it. Nothing is changed. `set-coding-standards` calls you for its audit and
takes the report from there; on your own, the report is the whole job.

## Facts

Read `~/.agents/skills/grill/references/facts.md` first: you are the brain,
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
   patterns, tests, commits). A file that only says how to install or how
   to open a PR is not a rules file. Done when every path in the list has
   been looked for and every hit is sorted into rules or not.

2. **Size the repo.** Count source files, ignoring vendored and generated
   trees. Run `git shortlog -sn` for authors. Detect the stack from the
   manifest and the file extensions. Bucket:

   | Bucket | Test | Rules come from |
   |---|---|---|
   | Empty | Zero source files | Stop. See step 3. |
   | Small | Under about 20 source files | The stack's well-known defaults |
   | Middle | Between | Both; the code wins where they differ |
   | Big | Hundreds of files, or several authors | The code. No rule without evidence in it |

   Done when bucket, stack, and file count are written down.

3. **Empty repo.** Say: no source files, so nothing to base a standard on.
   Name the one thing that would change that (a manifest, a first module).
   Stop.

4. **Audit.** Two branches, by what step 1 found.

   **No rules file.** Build the proposal per area in `Areas` below.
   Small: the stack's default, with its source named (PEP 8, Effective Go,
   the framework's own style guide, the formatter's defaults). Big: send
   Explore agents to sample the code per area, one agent per group of
   areas, each returning the pattern seen, a count, and three `file:line`
   examples. The majority pattern is the proposal. Middle: both, and the
   code's pattern wins where they disagree. Done when every area has a
   proposal, a source, and, for big and middle, evidence.

   **Rules file exists.** Three checks on the rules found, in this order:

   - **Outdated**: a rule that names a tool, path, version, or link that no
     longer exists in the repo. Age is a hint, from `git log -1` on the
     rules file against the code: it points where to look, it is never the
     verdict.
   - **Drift**: the code breaks a live rule. For each rule a search can
     check, get a count and three `file:line` examples. Drift is a code
     problem by default: the rule stands.
   - **Gaps**: an area in `Areas` with no rule. Also rules scattered across
     more than one file.

   Done when every rule has been checked for outdated and drift, every
   area for a gap, and each finding carries its evidence.

5. **Report, then stop.** Print the audit in this shape:

   ```
   Stack: <language, framework, tooling>       Size: <bucket>, <n> files, <n> authors
   Rules found in: <paths, or "none">
   Outdated: <rule> — <what is gone>            (or "none")
   Drift: <rule> — <count>, e.g. <file:line> ×3 (or "none")
   Gaps: <area>, <area>                         (or "none")
   Proposals: <area>: <rule> (<source or evidence>)   (no-rules branch only)
   Verdict: clean | needs work
   ```

   `clean` means a rules file exists and outdated, drift, and gaps are all
   "none". Then list the areas checked. Otherwise `needs work`. Either
   way, stop here. The report is the whole output; the caller decides what
   happens next.

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
`CLAUDE.md`. Big bucket. Outdated: `CONTRIBUTING.md` names `flake8`, but
`ruff.toml` replaced it. Drift: "views are class-based", 61 function
views, three examples. Gaps: Logging, API shape. Verdict: needs work.
Stop.

**User:** `/audit-coding-standards` in a repo with a good
`CODING_STANDARDS.md`, touched last month, no drift, no gaps.

Report shows "none" three times. Verdict: clean. List the areas checked.
Stop.

**User:** `/audit-coding-standards` in a fresh Next.js scaffold, 4 source
files.

Step 1 finds `.eslintrc.json` and `.prettierrc` from the template, no
prose rules. Small bucket. Proposals from the Next.js and TypeScript
defaults, one per area, each with its source. Verdict: needs work. Stop.

**User:** `/audit-coding-standards` in a repo with only a README.

Empty bucket. Say there are no source files, that a manifest or a first
module is what would start the standard. Stop.
