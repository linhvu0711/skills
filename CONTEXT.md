# Skills

Agent skills for Claude Code and Codex.

## Skills

**Shared core**:
The `shared-skill-core/` folder: files that two or more skills read. A file read by more than one skill lives here, not inside one of the skills.
_Avoid_: common, utils, lib

**PR shape**:
The title and body that every pull request opened by these skills follows. It is kept once, in `shared-skill-core/pr-shape.md`.
_Avoid_: PR template (that is a repo's own `.github/pull_request_template.md`)

## Plans

**Review view**:
The first view of the plan page, made for a person who approves the plan: the change, the approach, the blast radius, the choices, the risks, how we know it works, and the scope. The slices, tests, and walks under it are for the executor.
_Avoid_: summary, overview

**Change map**:
The one diagram kind in the Review view. A box is a part with a job, named in the project's own words; an arrow is what moves between parts, or who asks whom; a gray area is the app or package the parts live in. A store box lists the tables, columns, or keys that change. Files are details of a box, never boxes.
_Avoid_: architecture diagram, component diagram, dependency graph

## Credit

**Upstream**:
The repo a copied or adapted skill came from, such as `mattpocock/skills`.
_Avoid_: source, origin

**Copy**:
A skill or file whose text is mostly the upstream's, word for word.
_Avoid_: fork, port

**Heavy adaptation**:
A skill that keeps the upstream's structure and some of its sentences, rewritten around this repo's skills.

**Idea only**:
A skill that takes the upstream's idea and none of its text.
_Avoid_: inspired by

## Checks

**Repo check**:
The GitHub Action that checks every push and pull request: each skill has its README and license files, and every relative path points to a file that exists.
_Avoid_: CI lint

## Coding standards

**Level 1 source**:
The owner of a stack part: its official docs, official style guide, or the maintainers' repo. A coding-standards rule cites a level 1 source first.
_Avoid_: official source, primary source

**Level 2 source**:
A group that maintains a core part of the stack, or a source that the owner's docs link to, such as Vercel for Next.js and React patterns. When it disagrees with a level 1 source, level 1 wins unless the user picks otherwise.
_Avoid_: reputable source, trusted source

**Behind current practice**:
An audit finding that the code, or a rule, differs from what a level 1 or level 2 source says now. In middle and big repos the code still wins by default, and the user decides.
_Avoid_: outdated (that is a rule that names a tool, path, or version the repo no longer has)

**Sources table**:
The table at the end of `CODING_STANDARDS.md` that lists each source a rule cites, and the main page searched for a stack part that gave no rule: stack part, name, link, version, and the date it was checked. The audit uses it to know which stack parts to check again.

**Standard**:
`CODING_STANDARDS.md` at the repo root, with the `docs/standards/<topic>.md` files it links to. `set-coding-standards` writes it the first time; `audit-coding-standards` checks it and changes it after.
_Avoid_: style guide, conventions file

**Scattered rules**:
Rules about code that live outside the Standard, in files such as `CONTRIBUTING.md`, `CLAUDE.md`, or `.cursor/rules/`. `set-coding-standards` checks them and moves them into the Standard.
_Avoid_: legacy rules, old conventions
