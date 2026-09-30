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
