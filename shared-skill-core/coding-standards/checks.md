# Coding-standards checks

What `set-coding-standards` and `audit-coding-standards` both run to
learn how code is written in a repo: where its rules live, how big it
is, what the code does, and what is wrong with the rules. The research
they cite is `research.md`, next to this file.

The **Standard** is `CODING_STANDARDS.md` at the repo root, with the
`docs/standards/<topic>.md` files it links to. **Scattered rules** are
rules about code that live anywhere else.

## Find the rules

Search the repo for every file that carries code rules. Fixed list,
always checked:

`CODING_STANDARDS.md`, `CONVENTIONS.md`, `CONTRIBUTING.md`, `STYLE*.md`, `docs/**`, `CLAUDE.md`,
`AGENTS.md`, `.cursorrules`, `.cursor/rules/**`, `.editorconfig`, linter
and formatter configs (`.eslintrc*`, `eslint.config.*`, `.prettierrc*`,
`biome.json*`, `ruff.toml`, `pyproject.toml`, `.golangci.yml`,
`.rubocop.yml`, `rustfmt.toml`, `clippy.toml`, `.swiftlint.yml`), PR
and issue templates under `.github/`.

Read each hit. Keep the ones with real rules about code (names, layout,
patterns, tests, commits); install steps and PR how-tos are not rules.
Mark each rule kept as in the Standard or scattered. A linter or
formatter config is the tool's own rules, not a scattered rule.

Done when every path in the list has been looked for, and every hit is
sorted into rules or not, each rule marked Standard or scattered.

## Size the repo

Count source files, ignoring vendored and generated trees. Run
`git shortlog -sn` for authors. List the stack parts in use and planned,
per `research.md` § Stack parts. Bucket:

| Bucket | Test | Rules come from |
|---|---|---|
| Empty | Zero source files | Nothing. Say there are no source files, so nothing to base a standard on, and name the one thing that would change that (a manifest, a first module). Stop. |
| Small | Under about 20 source files | The research |
| Middle | Between | The code where it has a pattern, else the research. Where they differ, the code wins and the difference is a "behind current practice" finding |
| Big | Hundreds of files, or several authors | Same as middle, with the code sampled by agents |

Done when bucket, file count, authors, and the stack parts in use and
planned are written down.

## Sample the code

Middle and big repos: send Explore agents to sample the code per area,
one agent per group of areas, each returning the pattern seen, a count,
and three `file:line` examples. Small repo: read the code yourself for
the same.

Done when every area in `Areas` has a pattern with its count and
examples, or `no pattern`.

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

## Check the rules

Four checks, in this order. The caller says which rules they run on.

- **Outdated**: a rule that names a tool, path, version, or link that no
  longer exists in the repo, or a rule for a stack part no longer in
  use. `git log -1` on the rule's file against the code gives its age:
  a hint where to look, never the verdict.
- **Drift**: the code breaks a live rule. For each rule a search can
  check, get a count and three `file:line` examples. Drift is a code
  problem by default: the rule stands.
- **Behind current practice**: a rule, or the code's pattern, that a
  research result contradicts. A rule with no source is not a finding
  by itself; the team may have made it.
- **Gaps**: an area in `Areas` with no rule, and a stack part in use or
  planned with no rule. Also scattered rules, which belong in the
  Standard.

Done when every rule the caller named has been checked for outdated,
drift, and behind current practice, every area and stack part for a
gap when the caller runs that check, and each finding carries its
evidence or source.

## Report shape

Print the report in this shape. A line marked for one skill only is
left out by the other.

```
Stack: <language, framework, tooling>       Size: <bucket>, <n> files, <n> authors
Rules found in: <paths, or "none">
Outdated: <rule> — <what is gone>            (or "none")
Drift: <rule> — <count>, e.g. <file:line> ×3 (or "none")
Behind current practice: <rule or pattern> — <what the source says> (<URL>)   (or "none")
Gaps: <area, stack part, or scattered file>, ...   (or "none")      (audit only)
Proposals: <area>: <rule> (<URL> | <file:line> ×3 | scattered: <path> | model's view, no source: <reason> | no source)   (set only)
Conflicts: <area>: level 1 <rule> (<URL>) vs level 2 <rule> (<URL>)   (or "none")
Agent-ready: <name> (<URL>)                   (or "none")
Sources: <part> | <name> | <URL> | <version> | <date checked>, one per line
Not researched: <stack part> — <reason>      (or "none")
Verdict: clean | needs work                  (audit only)
```

`Sources` lists every source a rule or finding cites, and the main
page searched for each stack part that gave no rule, so the Sources
table can be written from it. A page that held an instruction is named
under `Not researched` with `page held an instruction`.

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.
