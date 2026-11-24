---
name: audit-coding-standards
description: "Make or check a repo's CODING_STANDARDS.md: research the stack, read the whole repo, any scattered rules, and a REVIEW.md, show a report page of rules that are old or wrong, jobs with no rule, code that breaks a rule, jobs done two ways, old API use, and the folders that break most, talk through your choices, and after your go file tickets and write the Standard, with nothing committed."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Agents copy what the code and the rules show them. A rule that names a tool the repo dropped, a job the Standard says nothing about, and code that breaks a rule all teach the next agent the wrong way. This skill finds them, and after the user's go it files tickets and writes the Standard: `CODING_STANDARDS.md` at the root, with the topic files it links to, per `../../shared/coding-standards/standard.md`. A repo with no Standard gets its first one: every check runs against an empty Standard, so every area is a job with no rule.

Read `../../shared/facts.md` first: you are the brain, helpers retrieve, short lookups are yours.

Then read `../../shared/clean-codebase/run.md` and follow it whole. It runs the five steps, and it asks this skill for four things: § Kinds, § Search, § Helper, and § Apply, below. § Search names when to read `references/checks.md` and `references/research.md`.

## Search

1. **Rules and size.** Run `checks.md` § Find the rules and § Size the repo, under its § Secrets. No `CODING_STANDARDS.md` at the root: the Standard is empty, and every rule found is scattered. Empty bucket: say what its table says and end the run; nothing is written. Then run `checks.md` § Folders that break most.
2. **Research.** Start it per `research.md`, beside the judges. With a Sources table, research only the stack parts its § Re-check calls due; with none, every part.
3. **Files.** From the repo root, the files in scope are `git ls-files` minus what the run leaves out, and minus the rule files step 1 found. Tests stay in: they are code. Every file in scope has places, since any line can break a rule or show how the code does a job.
4. **Packages.** Every dependency the repo's manifests name, with its version: `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, and the like. way-judge's brief holds this list.

## Helper

- `rule-judge`, one per batch. Its brief holds the batch's files, the span start, every rule of the Standard and every scattered rule with its `path:line`, the checker configs that have checks on, the areas of `checks.md` § Areas with what a rule in each settles, and § Kinds of this file, pasted in whole but its Two ways, Old API use, and Folders that break most bullets.
- `way-judge`, one per batch of about ten files that hold code; prose such as `.md` and `.txt`, and config, stay out, and tests stay in. Its brief holds the batch's files, the span start, the package list from § Search step 4, and every One way for each job line of the Standard with its `path:line`. It gets no § Kinds text: the row, its count, and its advice are the lead's.

## Kinds

One report kind: id `standards`, title `Standard`. Before you group the judges' places, run `checks.md` § Check the rules with the research's returns, then § Two ways with the way-judges' returns, and § Old API use. This section maps the checks to rows; the checks themselves live there. Kinds of row:

- **Old or wrong rule**: a rule that check calls Outdated or Behind current practice. One row per rule; its place is the rule's line.
  - Outdated, as `run flake8` when `ruff.toml` replaced it, or an `Old way: moment (#61)` mark once no file uses moment. Advice `fix`: update it to what the repo has now, or drop it, and an `Old way:` mark loses its `Old way:` part; the change list gives the new text. `choice` is false.
  - Behind current practice, as secrets read at import against the Django deployment checklist. Advice `fix`: follow the source. `choice` is true, since the team may have made the rule on purpose.
- **Job with no rule**: each Gap that check finds, so in a repo with no Standard, every area. One row per area or stack part with no rule, and one per scattered rule that is not outdated and no such row proposes, so every rule of a scattered file moves in. Each row has one proposed rule, the first that applies:
  - a scattered rule for the area that is not outdated: that rule, `scattered: <path>`. Advice `fix`: move it into the Standard. `choice` is false, unless it says something different from a rule of the Standard or another scattered rule for the same job: then `choice` is true, and the reason names both rules, as `.test.ts` in `CONTRIBUTING.md` against `.spec.ts` in the Standard. A rule from `REVIEW.md` lands in its area by `standard.md` § Add one rule step 5: a rule about a whole change in Each change, a rule for one folder in By folder.
  - else the rule `checks.md` § Size the repo picks for the bucket, with its source or the code's count. `choice` is true when the code's way and the research differ.
  - neither: down `research.md` § No source. `model's view, no source` sets `choice` true. `no source` has no proposal: advice `fine`, `choice` true, and the user writes the rule or leaves the area out under Not covered.

  A level 1 and a level 2 source that disagree, per `research.md` § Conflicts, set `choice` true, with both links in the reason. Every other proposal is advice `fix`, add the rule, with `choice` false.

  Its places are the code lines that show the way, or the scattered rule's lines. When no line in the repo does the job, it has one place: the page of the rule's source, or, with no rule, the main page the research searched (its `none` return, or the part's Sources table row when the part was not due), labelled `Seen` with `read on this run`, `searched on this run, no rule`, or, for a Sources table row, `from the Sources table, checked <date>`.
- **Code that breaks a rule**: each Drift place the judges found. A test that breaks a rule is a place like any other. One row per rule. Advice `fix`: a ticket fixes the code, a `chore` when it is a sweep, and turns on its lint setting per `standard.md` § Lint settings. `choice` is true when most places that do the job break the rule: keep it and fix the code, or change the rule to the code's way. In a folder scan, the reason says the count covers that folder only.
- **Two ways**: each job of `checks.md` § Two ways. One row per job. Its places are the way-judges' places for every way; its reason names each way with its count, as `date-fns 40, moment 12, own code 3 (src/utils/date.ts)`, and in a folder scan says the counts cover that folder only. Advice `fix`, naming the winner of `checks.md` § Two ways and why, as `use date-fns: 40 of 55 places, and the repo installs it`. `choice` is true: the user picks the one way, and every other way becomes its Old way.
- **Old API use**: each API of `checks.md` § Old API use. One row per API. Its places are the lines that use it; its reason names the source that marks it old, the version, and what replaces it, as `componentWillMount: old since React 16.3 (react-docs), use componentDidMount`. Advice `fix`: a ticket moves the uses to the replacement, a `chore` when it is a sweep. `choice` is false.
- **Folders that break most**: each folder of `checks.md` § Folders that break most. One row per folder. Each place is one commit: `at` is `<folder> <short SHA>`, `text` its subject, `new` when the commit is after the span start. The reason gives the count and the span, as `9 fix or revert commits in the last 6 months, about 30 commits a week`. Advice `fix`: one rule for the folder from what its commits fixed, as "`billing/`: each change is checked against the invoice tests.", its source the repo's own history. `choice` is true: the user keeps, changes, or drops the rule.

A stack part the user names as planned during the talk is researched per `research.md` before its area's rows get an answer.

`changes` adds `Sources table: <n> rows` when the research read any source, so a run with no row still writes the dates it checked.

`not_checked` names each case `checks.md` § Old API use did not check: `Old API use, no web access`, or `Old API use for <part>, not due for research`, one line per part.

## Apply

- **Tickets.** A Code that breaks a rule row answered fix the code, and any row whose answer changes code, as following the source on secrets, or a Two ways row, whose ticket moves every other way's uses to the way picked, or an Old API use row: a ticket row. Its body names the lint setting it turns on. A Code that breaks a rule row whose rule lost a clash in the talk files no ticket, since that rule leaves the repo. No row is a seed.
- **Edits.** After the run filed the tickets:
  - a scattered rule moved in leaves its old file, and so does one whose clash the user settled for the other rule; the rest of that file stays;
  - an Old or wrong rule answered drop loses its line;
  - `REVIEW.md`, when every repo rule in it moved in: the change list has the line `REVIEW.md: delete, its rules are in the Standard`. On the go the file goes, with each line that points at it, which `rg -n 'REVIEW\.md'` finds: the line in `CLAUDE.md` and `AGENTS.md`, a review bot's pointer, a `Review rules are in REVIEW.md` line. The user keeps the file by taking the line out of the change list.
  - `CLAUDE.md` and `AGENTS.md`, where they exist and lack it, get one line: `Read CODING_STANDARDS.md before you write or review code.`
  - `.editorconfig` is written or updated to match the Formatting rules;
  - the Sources table, per `standard.md` § Sources table: a row for every source a rule of this run cites and every source the research read, with its version and today's date. A stack part not researched keeps its rows, so the next run checks it again.
- **Rules.** The run's Rules step writes each added, changed, or moved rule by `standard.md` § Add one rule, whose step 0 creates `CODING_STANDARDS.md` in a repo with none. A rule whose lint setting waits names the ticket filed above. A Two ways row's rule is a One way for each job line, `<job>: <way picked>. Old way: <every other way> (#<n>).`, as `Dates: date-fns. Old way: moment (#61).`, `<n>` the ticket filed above. An Outdated `Old way:` mark loses its `Old way:` part, and the line keeps the job and its way. A Folders that break most rule goes in By folder.

## Examples

**User:** `/audit-coding-standards` in a fresh Next.js scaffold, 4 source files, no Standard.

Small bucket. The research gives proposals from nextjs.org, react.dev, and the TypeScript handbook. Every area is a Job with no rule. Logging is `no source`, its place the main page searched, and it is the one question. The change list holds 11 rules, `Sources table: 5 rows`, and `.editorconfig`. The user says go. `CODING_STANDARDS.md` is created, the Run table gets a line, then `Ready for a pull request`.

**User:** `/audit-coding-standards` in a Django monolith, 900 files, with a Standard from last year and rules in `CLAUDE.md`.

Big bucket; Django is due. Rows: `run flake8` is an Old or wrong rule (fix). The `CLAUDE.md` rules are a Job with no rule (move in). Logging is a Job with no rule (research: `structlog`). 61 function views break "views are class-based" (choice: most views do it the other way). Secrets read at import are an Old or wrong rule against the deployment checklist (choice). The talk asks two questions. After the go: tickets for the views and the secrets, the rules written, and `CLAUDE.md` keeps its pointer line.

**User:** `/audit-coding-standards` in a repo whose Sources table is 7 months old; every rule still agrees with its source and the code keeps every rule.

No row. The page says `I found nothing to fix.`, and the change list is `Sources table: 6 rows`. The user says go: the dates are written, and the Run table gets a line.
