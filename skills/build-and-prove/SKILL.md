---
name: build-and-prove
description: "Build a /plan-up plan on this machine and prove it with proofbox: the Mac edits and commits, one proofbox Sandbox runs every test, the build, and the app, and a walker subagent films the UI walks. Ends at a branch with one commit per slice and a proof folder for /make-pr. /ship runs it by default."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

## Sandbox

One run has one proofbox Sandbox, and every command that runs the
project's code runs there: each slice's red and green test, typecheck,
lint, the full suite, the build, and the app. The Mac only edits files,
runs git, and calls proofbox (`docs/adr/0009` in this repo).
`scripts/box.sh` holds the Sandbox; it prints its usage with no
arguments.

- `box.sh up <proof-dir> <worktree> <linux|macos> <owner/repo>` creates
  it with `--idle 30m --max-life 6h` and no `--provider`, so proofbox's
  own config picks the Provider. It reads the setup script and env file
  from `~/.agents/proofbox/<owner>-<repo>/`.
- `box.sh run <proof-dir> -- <command>…` uploads the worktree's changed
  files, runs the command, and exits with its code. A Sandbox that is
  gone is made again once from its Snapshot.
- `box.sh down <proof-dir>` deletes it.

`stop:` on stderr is the reason to stop; a `stop: log in first: <command>`
line names the login command for the user.
