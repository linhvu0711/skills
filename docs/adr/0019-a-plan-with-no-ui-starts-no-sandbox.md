# A plan with no UI starts no Sandbox

In `/build-and-prove`, only a plan with UI walks starts a proofbox Sandbox. A plan with `UI: none` has no screen to film, so it needs no Sandbox and no proofbox. Its Gates split: each one the PR's CI runs is left to CI, and the local machine runs the rest, one at a time, through `box.sh gates --local`, which writes the same `checks.txt` lines. Its perf measure runs on the local machine, base and head in turns. On 2026-10-28 a run on this repo waited over 30 minutes for a Sandbox to pull its image, to run two bash scripts that had already passed on the local machine and that CI runs on every push. This amends ADR 0011 for a plan with no UI; a plan with walks keeps it.

## Considered options

- Every Gate in the Sandbox, for every plan (ADR 0011): kept for a plan with walks, which starts the Sandbox for the app anyway. Rejected for a plan with no UI: a Sandbox, its setup script, and its login, to run what CI runs again.
- Every Gate on the local machine: rejected. A full suite there overloads it when sessions run side by side (ADR 0011), and CI runs it again on the PR.

## Consequences

- A red Gate that CI covers shows only after the PR opens. ready-pr already fixes red CI checks, so the PR waits and nothing ships red.
- A slice test or a Gate whose tool the local machine lacks stops and asks the user to install it; no Sandbox starts for it.
- In a repo with e2e tests, a plan with no UI leaves the e2e spec files to the PR's CI.
- `/ship`'s review fixes on a plan with no UI start no Sandbox either.
