---
name: audit-coding-standards
description: "Make or check a repo's CODING_STANDARDS.md: research the stack, read the whole repo and any scattered rules, show a report page of rules that are old or wrong, jobs with no rule, and code that breaks a rule, talk through your choices, and after your go file tickets and write the Standard, with nothing committed."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Agents copy what the code and the rules show them. A rule that names a tool the repo dropped, a job the Standard says nothing about, and code that breaks a rule all teach the next agent the wrong way. This skill finds them, and after the user's go it files tickets and writes the Standard: `CODING_STANDARDS.md` at the root, with the topic files it links to, per `../../shared/coding-standards/standard.md`. A repo with no Standard gets its first one: every check runs against an empty Standard, so every area is a job with no rule.

Read `../../shared/facts.md` first: you are the brain, helpers retrieve, short lookups are yours.

Then read `../../shared/clean-codebase/run.md` and follow it whole. It runs the five steps, and it asks this skill for four things: § Kinds, § Search, § Helper, and § Apply, below. § Search names when to read `references/checks.md` and `references/research.md`.

## Search

1. **Rules and size.** Run `checks.md` § Find the rules and § Size the repo, under its § Secrets. No `CODING_STANDARDS.md` at the root: the Standard is empty, and every rule found is scattered. Empty bucket: say what its table says and end the run; nothing is written.
2. **Research.** Start it per `research.md`, beside the judges. With a Sources table, research only the stack parts its § Re-check calls due; with none, every part.
3. **Files.** From the repo root, the files in scope are `git ls-files` minus what the run leaves out, and minus the rule files step 1 found. Tests stay in: they are code. Every file in scope has places, since any line can break a rule or show how the code does a job.

## Helper

`rule-judge`, one per batch. Its brief holds the batch's files, the span start, every rule of the Standard and every scattered rule with its `path:line`, the checker configs that have checks on, the areas of `checks.md` § Areas with what a rule in each settles, and § Kinds of this file, pasted in whole.

## Kinds

One report kind: id `standards`, title `Standard`. Before you group the judges' places, run `checks.md` § Check the rules with the research's returns. This section maps its four checks to rows; the checks themselves live there. Three kinds of row:

- **Old or wrong rule**: a rule that check calls Outdated or Behind current practice. One row per rule; its place is the rule's line.
  - Outdated, as `run flake8` when `ruff.toml` replaced it. Advice `fix`: update it to what the repo has now, or drop it; the change list gives the new text. `choice` is false.
  - Behind current practice, as secrets read at import against the Django deployment checklist. Advice `fix`: follow the source. `choice` is true, since the team may have made the rule on purpose.
- **Job with no rule**: each Gap that check finds, so in a repo with no Standard, every area. One row per area, stack part, or file of scattered rules, each with one proposed rule, the first that applies:
  - a scattered rule for the area that is not outdated: that rule, `scattered: <path>`. Advice `fix`: move it into the Standard. `choice` is false.
  - else the rule `checks.md` § Size the repo picks for the bucket, with its source or the code's count. `choice` is true when the code's way and the research differ.
  - neither: down `research.md` § No source. `model's view, no source` sets `choice` true. `no source` has no proposal: advice `fine`, `choice` true, and the user writes the rule or leaves the area out under Not covered.

  A level 1 and a level 2 source that disagree, per `research.md` § Conflicts, set `choice` true, with both links in the reason. Every other proposal is advice `fix`, add the rule, with `choice` false.

  Its places are the code lines that show the way, or the scattered rule's lines. When no line in the repo does the job, it has one place: the page of the rule's source, or, with no rule, the main page the research searched (its `none` return, or the part's Sources table row when the part was not due), labelled `Seen` with `read on this run`, `searched on this run, no rule`, or, for a Sources table row, `from the Sources table, checked <date>`.
- **Code that breaks a rule**: each Drift place the judges found. A test that breaks a rule is a place like any other. One row per rule. Advice `fix`: a ticket fixes the code, a `chore` when it is a sweep, and turns on its lint setting per `standard.md` § Lint settings. `choice` is true when most places that do the job break the rule: keep it and fix the code, or change the rule to the code's way.

A stack part the user names as planned during the talk is researched per `research.md` before its area's rows get an answer.

`changes` adds `Sources table: <n> rows` when the research read any source, so a run with no row still writes the dates it checked.

## Apply

- **Tickets.** A Code that breaks a rule row answered fix the code, and any row whose answer changes code, as following the source on secrets: a ticket row. Its body names the lint setting it turns on. No row is a seed.
- **Edits.** After the run filed the tickets:
  - a scattered rule moved in leaves its old file; the rest of that file stays;
  - an Old or wrong rule answered drop loses its line;
  - `CLAUDE.md` and `AGENTS.md`, where they exist and lack it, get one line: `Read CODING_STANDARDS.md before you write or review code.`
  - `.editorconfig` is written or updated to match the Formatting rules;
  - the Sources table, per `standard.md` § Sources table: a row for every source a rule of this run cites and every source the research read, with its version and today's date. A stack part not researched keeps its rows, so the next run checks it again.
- **Rules.** The run's Rules step writes each added, changed, or moved rule by `standard.md` § Add one rule, whose step 0 creates `CODING_STANDARDS.md` in a repo with none. A rule whose lint setting waits names the ticket filed above.

## Examples

**User:** `/audit-coding-standards` in a fresh Next.js scaffold, 4 source files, no Standard.

Small bucket. The research gives proposals from nextjs.org, react.dev, and the TypeScript handbook. Every area is a Job with no rule. Logging is `no source`, its place the main page searched, and it is the one question. The change list holds 11 rules, `Sources table: 5 rows`, and `.editorconfig`. The user says go. `CODING_STANDARDS.md` is created, the Run table gets a line, then `Ready for a pull request`.

**User:** `/audit-coding-standards` in a Django monolith, 900 files, with a Standard from last year and rules in `CLAUDE.md`.

Big bucket; Django is due. Rows: `run flake8` is an Old or wrong rule (fix). The `CLAUDE.md` rules are a Job with no rule (move in). Logging is a Job with no rule (research: `structlog`). 61 function views break "views are class-based" (choice: most views do it the other way). Secrets read at import are an Old or wrong rule against the deployment checklist (choice). The talk asks two questions. After the go: tickets for the views and the secrets, the rules written, and `CLAUDE.md` keeps its pointer line.

**User:** `/audit-coding-standards` in a repo whose Sources table is 7 months old; every rule still agrees with its source and the code keeps every rule.

No row. The page says `I found nothing to fix.`, and the change list is `Sources table: 6 rows`. The user says go: the dates are written, and the Run table gets a line.
