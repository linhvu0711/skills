# The Standard

What the Standard looks like, and the one step that adds a rule to it.
Every skill that writes `CODING_STANDARDS.md` or adds a rule follows
this file, so each rule lands in one format.

## Shape

`CODING_STANDARDS.md` starts with these three lines, `<configs>` filled
in with the repo's checker configs, as `` `.eslintrc.json`, `ruff.toml` ``:

```
This file is the Standard: the rules for how code is written in this repo. Read it before you write or review code. Rules a tool checks live in its config (<configs>), not here.
`(name)` after a rule names its source, listed in `docs/standards/sources.md`. `[tool, after #61]` means a tool will check the rule once ticket #61 turns its check on; until then, this line is the rule.
`Old way:` names a way that existing code still uses. Add no new use of it.
```

Then the areas, each a `##` heading, in this order:

| Area | What a rule here settles |
|---|---|
| One way for each job | For each job the code does in many places, the one thing to use |
| Names | Case per kind: files, types, functions, constants, DB columns, env vars |
| Structure | Folder tree, where a new module goes, what a module may import |
| Errors | Throw or return, custom error types, what gets caught where |
| Logging | Library, levels, structured fields, what is never logged |
| Tests | Framework, file placement, naming, what must have a test |
| Commits | Message format, branch names, PR size |
| Deps | How one is added, pinning, lockfile policy |
| Config and secrets | Env var loading, what lives in a `.env`, what never enters git |
| API shape | Route naming, response envelope, versioning, pagination |
| Formatting | Indent, line length, quotes, trailing commas: the formatter's job |
| Stack-specific | Type strictness, async style, ORM usage, component patterns, and the like |
| By folder | A rule for one folder, the folder first |
| Each change | A rule about a whole change |
| Not covered | The areas left out on purpose |

An area with no rule has no heading.

- **One way for each job**: one line per job: the job, the one thing to
  use, and its Old way when one exists, as in `Dates: date-fns. Old
  way: moment (#61).` The number is the ticket that removes the last
  uses of the Old way, `(no ticket)` until one is filed. The mark goes
  when the uses are gone.
- **By folder**: the folder first, as in "`billing/`: each change is
  checked against the invoice tests."
- **Each change**: as in "A migration has a way back."
- **Not covered**: last, so the next reader knows each area left out
  was a choice.

Every other area reads as rules, one per line. Each rule states the
positive form: "Files are `kebab-case`", "Errors are returned, never
thrown across a module edge". Each rule is in our own words, never the
source's text copied. A rule from a source ends with the source's name
in parentheses. A rule whose lint setting waits, per § Lint settings,
then names the tool and the ticket that turns the setting on:
`Files are kebab-case (eslint-docs) [eslint, after #61]`. That ticket
deletes the line, since the config then holds the rule. A rule from
the code or the user carries no source name. A rule with a
reason that is not obvious gets one sentence of why under it.

A topic past about 40 rules (one area, or one stack part's rules) moves
to `docs/standards/<topic>.md` in the same rule shape. Its heading stays
in `CODING_STANDARDS.md` with one line: "Rules are in
`docs/standards/<topic>.md`."

### Older shape

A Standard with no intro lines, a `Layout` heading, a `## Sources`
table at its end, or a line tagged with a tool alone, as `[eslint]`,
is in an older shape. § Sources table and § Add one rule each bring it
up to date first: add the three lines, name `Layout` `Structure`, and
move the table per § Sources table. A line tagged with a tool alone
goes when that tool's config has its check on, since the config then
holds the rule; with the check off, the line stays and loses its tag.
Every other rule stays in its area.

## Sources table

`docs/standards/sources.md` holds the one Sources table, for all rules
in all files. `CODING_STANDARDS.md` holds no table. A write to the
table runs § Older shape first: a table still at the end of
`CODING_STANDARDS.md` moves here with its rows unchanged, and leaves
the Standard.

```
# Sources

| Part | Name | Link | Version | Checked |
|---|---|---|---|---|
| react | react-docs | https://react.dev/reference/rules | 19 | 2026-09-30 |
| general | conventional-commits | https://www.conventionalcommits.org/en/v1.0.0/ | 1.0.0 | 2026-09-30 |
```

`Part` is the stack part, or `general`. `Version` is the stack part's
version the source covers, or `-` when it has none. `Checked` is the
date the research read it. A stack part that was searched and gave no
rule still gets a row, for the main page searched. The audit reads this
table to know which stack parts are due.

Each source gets a new row, or the version and date of its row already
there. A row that no rule cites any more and no stack part in use or
planned needs goes.

## Add one rule

Every rule enters the Standard by these steps, whichever skill adds it.

0. **Shape.** The Standard is in an older shape: bring it up to date
   per § Older shape.
1. **Look first.** Search `CODING_STANDARDS.md` and its topic files for
   a rule that already says the lesson, or part of it. One found:
   change that rule, and add no second one.
2. **Sort the lesson.** A lesson about one place is a fix (a ticket)
   or an ADR, and stays out of the Standard. A lesson about all later
   code is a lint setting when a tool can check it, per § Lint
   settings, and the setting is the whole rule: the Standard does not
   repeat it. Any other lesson about all later code is one line in the
   Standard.
3. **The bar.** A line gets in only when an agent can follow it while
   it writes code, and a reviewer can check it on a diff.
4. **Source.** The rule names its source, as this skills repo's ADR
   0003 decided: a source read on this run, written `(name)` with its
   row in the Sources table; the repo's own code; or the user. The
   model's memory is never a source.
5. **Area.** A job and the one thing to use goes in One way for each
   job. A rule for one folder goes in By folder, and a rule about a
   whole change in Each change. Any other rule goes in its area from
   § Shape.

Done when the lesson is one line in its area, a changed line, a lint
setting, or a ticket or ADR, and the Standard holds no two rules that
say it.

### Lint settings

A lint setting is written only when no code breaks it today, or when
the tool can limit it to new code, as a baseline file of today's
breaks does. In every other case, the setting is named in the ticket
that fixes the code, and that ticket turns it on. Until then, the rule
is a line in the Standard marked `[tool, after #<n>]`, per § Shape,
and the ticket deletes that line when it turns the setting on. An `Old way` gets a
tool ban for new code, such as a banned import, when the repo's lint
tool can do it.

### Never in the Standard

- A list of problems: those are tickets.
- A long reason: that is an ADR, and the rule links to it.
- Install steps.
- A line nobody can check.
