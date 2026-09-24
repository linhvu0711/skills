# Skills

Agent skills for Claude Code and Codex.

## Skills

**Shared core**:
The `shared-skill-core/` folder: files that two or more skills read. A file read by more than one skill lives here, not inside one of the skills.
_Avoid_: common, utils, lib

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
