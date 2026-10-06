# Coding runs on the local machine, the Gates run in the Sandbox

In `/build-and-prove`, each slice's red and green test, typecheck, and lint run on the local machine. The Gates, the app, the before shots, and the walks run in one proofbox Sandbox, which starts after Coding. This replaces ADR 0009, which sent every command to the Sandbox. Measured on proofbox at one commit (2026-10-06): one test file took 18.5 s on the local machine and 17.1 s in a 4x8 Sandbox, but each Sandbox call added 1 s for the exec and 4 to 10 s for the upload. In three builds, gaps in the Sandbox setup made about ten test runs fail for reasons outside the code. The full suite stays off the local machine, because two suites at once overload it (proofbox's `vitest.config.ts`).

The builder never guesses where a command runs. The plan names each slice's test, and the Gates are a fixed list.

## Considered options

- Everything in the Sandbox (ADR 0009): rejected. Each test pays the upload, and the Sandbox runs idle through Coding.
- Everything on the local machine, the Sandbox only for the app and the walks: rejected. Parallel sessions overload the local machine, and nothing runs in a clean Linux like CI.

## Consequences

- A slice test that cannot run on the local machine (a tool is missing) runs in the Sandbox, which then starts early and stays on.
- A Gate that cannot run in the Sandbox, such as one that needs Docker, runs on the local machine, and its `checks.txt` line says so. When it can run in neither place, the line is `not run: <why>`.
- Review fixes after the PR is open run their tests on the local machine and leave the full suite and the Build command to the PR's CI. A repo with no CI runs the Gates in a Sandbox.
- The proofbox login is checked before Coding, so a missing login does not stop a run after Coding.
