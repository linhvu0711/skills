# Skills

Agent skills for Claude Code and Codex. This repo is the one real copy of the public skills; the machine that uses them links to it.

## Skills

**Public skill**:
A skill whose folder lives in `skills/<name>/` in this repo and is published with it.
_Avoid_: shared skill, open skill

**Private skill**:
A skill that lives only in `~/.agents/skills/` on the owner's machine and never enters this repo.
_Avoid_: hidden skill, excluded skill

**Shared core**:
The `shared-skill-core/` folder: files that two or more skills read. A file read by more than one skill lives here, not inside one of the skills.
_Avoid_: common, utils, lib

**Adopt**:
Move a private skill into this repo and link it back, which makes it a public skill.
_Avoid_: promote, publish (publishing is the repo going public)

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

**Private-word check**:
The local git hook that blocks a commit containing a word from the private word list.
_Avoid_: robot, linter

**Private word list**:
The owner's list of words that must never be public, kept in `.git/info/private-words` and never committed.
_Avoid_: denylist, blocklist

**Repo check**:
The GitHub Action that checks every push and pull request: each public skill has its README and license files, and every relative path points to a file that exists.
_Avoid_: robot, CI lint
