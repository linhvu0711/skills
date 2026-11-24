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
  a hint where to look, never the verdict.
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

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.
