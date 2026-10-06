---
status: superseded by ADR-0011
---

# The Mac edits, the sandbox runs

In `/build-and-prove`, the Mac only edits files, runs git, and calls proofbox. Everything that runs the project's code runs in one proofbox Sandbox per run: each slice's red and green test, typecheck, lint, the full suite, the build, and the app the walker uses. Each test run takes a few seconds more for the upload and the network round trip, but the user's Mac stays free for other work, and the builder never has to guess which command counts as heavy. Do not move "just the quick test" back to the Mac.

## Considered options

- Small checks on the Mac, heavy ones in the Sandbox: rejected, because the line between small and heavy is a guess the agent makes again on each run.
- Only the app and the walks in the Sandbox: rejected, because installs, builds, and full suites are the load the user wants off the Mac.

## Consequences

- One Sandbox at a time per run. Its idle time is 30m on Linux and 10m on macOS, and its max life is proofbox's 3h default, because Namespace's Developer plan allows no more. proofbox cannot change these after `create`, so when a Sandbox dies, the skill makes a new one from its Snapshot, in about a minute, and the run goes on. The code lives on the Mac, so a Sandbox that dies loses no work. The idle time, not the max life, caps the cost of a run that stops before it deletes its Sandbox.
