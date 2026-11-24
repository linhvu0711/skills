# Coding-standards checks

What `audit-coding-standards` runs to learn how code is written in a
repo: where its rules live, how big it is, and what is wrong with the
rules. The research it cites is `references/research.md`.

The **Standard** is `CODING_STANDARDS.md` at the repo root, with the
`docs/standards/<topic>.md` files it links to. **Scattered rules** are
rules about code that live anywhere else.

## Find the rules

Search the repo for every file that carries code rules. Fixed list,
always checked:

`CODING_STANDARDS.md`, `REVIEW.md`, `CONVENTIONS.md`, `CONTRIBUTING.md`, `STYLE*.md`, `docs/**`, `CLAUDE.md`,
`AGENTS.md`, `.cursorrules`, `.cursor/rules/**`, `.editorconfig`, linter
and formatter configs (`.eslintrc*`, `eslint.config.*`, `.prettierrc*`,
`biome.json*`, `ruff.toml`, `pyproject.toml`, `.golangci.yml`,
`.rubocop.yml`, `rustfmt.toml`, `clippy.toml`, `.swiftlint.yml`), PR
and issue templates under `.github/`.

Read each hit. Keep the ones with real rules about code (names, layout,
patterns, tests, commits); install steps and PR how-tos are not rules.
Mark each rule kept as in the Standard or scattered. A linter or
formatter config is the tool's own rules, not a scattered rule.
In `REVIEW.md`, the block between the `set-review-rules:general`
markers is the shared review rules, not the repo's: leave it. Each rule
below the end marker is a scattered rule, a review rule about a whole
change too; its axis headings and `None yet.` lines are not rules. A
`REVIEW.md` with no marker block is all repo rules.

Done when every path in the list has been looked for, and every hit is
sorted into rules or not, each rule marked Standard or scattered.

## Size the repo

Count source files, ignoring vendored and generated trees. Run
`git shortlog -sn` for authors. List the stack parts in use and planned,
per `references/research.md` § Stack parts. Bucket:

| Bucket | Test | Rules come from |
|---|---|---|
| Empty | Zero source files | Nothing. Say there are no source files, so nothing to base a standard on, and name the one thing that would change that (a manifest, a first module). Stop. |
| Small | Under about 20 source files | The research |
| Middle | Between | The code's way where most places do the job one way, else the research. Where they differ, the code's way is the proposal and the source goes in its reason |
| Big | Hundreds of files, or several authors | Same as middle |

Done when bucket, file count, authors, and the stack parts in use and
planned are written down.

## Areas

The checklist for gaps and proposals. Each area gets one rule, or an
on-purpose "left out".

The areas are those of `../../shared/coding-standards/standard.md` § Shape from `Names` to
`Stack-specific`, with what a rule in each settles.

## Check the rules

Four checks, in this order. They run on every rule of the Standard and every scattered rule.

- **Outdated**: a rule that names a tool, path, version, or link that no
  longer exists in the repo, or a rule for a stack part no longer in
  use. `git log -1` on the rule's file against the code gives its age:
  a hint where to look, never the verdict. An `Old way:` mark is
  outdated when the way-judges give no place for that way and `rg` for
  its name finds no use in the files in scope. Whole-repo scans only: a
  folder scan cannot see the rest of the repo.
- **Drift**: the code breaks a live rule. Its places are each line
  that breaks the rule. A check that is on in a checker config, and a
  formatter the repo runs, report their own breaks wherever the repo
  runs them, as in CI: the audit runs no checker or formatter. Drift is
  a code problem by default: the rule stands.
- **Behind current practice**: a rule that a research result
  contradicts. A rule with no source is not a finding by itself; the
  team may have made it.
- **Gaps**: an area in `Areas` with no rule, and a stack part in use or
  planned with no rule. A check that is on in a checker config, or a
  formatter the repo runs, is a rule of the area it covers, since a
  rule a tool checks lives only in its config (`standard.md` § Add one
  rule): `ruff format` in CI fills Formatting, while a `line-length`
  value with no check or formatter that uses it fills nothing. Also scattered rules, which belong in
  the Standard.

Done when every rule of the Standard and every scattered rule has
been checked for outdated, drift, and behind current practice, every
area and stack part for a gap, and each finding carries its evidence
or source.

## Two ways

Join the way-judges' returns by job across batches: two names for one
job, as `parse dates` and `date parsing`, are one job. A job is a row
when the scope does it in two or more ways and the Standard has no One
way for each job line for it. Add the counts per way. Own code whose
proof names a language feature or an installed package that already
does the job is two ways on its own: the own code, and that feature or
package with a count of 0 when nothing uses it, as `own code
(src/utils/debounce.ts) 6, lodash.debounce 0`. A job done one way in
many places, with no own code beside a package or feature, is no row.

The winner, by the bucket of § Size the repo: in a small repo, the way
a research source names, else the way most places use; in a middle or
big repo, the way most places use, with a source that names another way
in the reason. Own code loses to an installed package or a language
feature that does the same job, unless the reason names what the own
code does that they do not.

Done when every job in the returns is a row, or a job with one way and
no own code that redoes a package or feature.

## Old API use

Each `old` line of the research's returns is an API a source read on
this run marks old (ADR 0003). Only an API old from the installed
version or before counts. Search the files in scope for its name with
`rg -n -w`. A hit is a use when the line calls, imports, extends, or
sets the API; a hit in a comment, a string, or a same-named thing of
another package is not. An import that gives it another name, as
`render as renderLegacy`, adds a search for that name in its file. Each
API with a use is a row. Two cases leave
it not checked: no web access, where the research read no source, and
a stack part the research skipped as not due (`research.md`
§ Re-check).

Done when every `old` line is searched, and each case not checked is
named with why.

## Folders that break most

Pick the span from the pace of the repo, as the run picks its span:
`git log --since=<date> --oneline | wc -l` shows the pace. Take a span
that holds enough fix commits to rank folders, with no fixed number,
and hold it as a phrase, as `the last 6 months, about 30 commits a
week`. Then list each fix or revert commit once per folder it touches,
where a folder is the first two parts of a path and `.` holds the files
at the root, and hold the lines:

```bash
git log --since=<date> --no-merges -i -E --grep='^(fix|revert)' --format='@%h %ad %s' --date=short --name-only -- <scope> | awk '/^@/{c=substr($0,2);next} NF{n=split($0,p,"/"); f=(n>2?p[1]"/"p[2]:(n==2?p[1]:".")); if(!seen[c"\t"f]++) print f"\t"c}'
```

Each line is `<folder>` and a tab, then `<short SHA> <date> <subject>`.
`<scope>` is `.`, or the folder the user named, then one `':(exclude)<path>'` for each path the run leaves out (`../../shared/clean-codebase/run.md` § Scan), as `':(exclude)vendor'`, so a fix that regenerates a vendored file adds no line for its folder. Count per folder with
`cut -f1 | sort | uniq -c | sort -rn | head -5`. Each folder whose count
stands clear of the rest is a row, five at most, unless the Standard's
By folder area already has a rule for it. No line, or no count that
stands out: no row. A row's places are that folder's lines, so the
count and the places agree; read their subjects to name what breaks
there.

Done when the span phrase is held and each folder is a row or left out
with why.

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.
