---
status: amends ADR-0011
---

# A plan with walks leaves CI's checks to CI

In `/build-and-prove`, the Sandbox of a plan with UI walks runs the walks and only the Gates that the PR's CI does not run. `shared/ci-covers.sh` decides which Gates CI runs, as it does for a plan with no UI (ADR 0019). In the 14 days to 2026-11-25, one `gates` call in the Sandbox took 3 to 10 minutes, and a job made about two. That cost about 7 minutes of each job's proof part, and dressup's CI then ran the same four Gates again on every PR. This amends ADR 0011 for a plan with walks.

## Considered options

- Every Gate in the Sandbox (ADR 0011): rejected. Each Gate runs twice, once in the Sandbox and once in CI.
- The Gates in the Sandbox while the walks run: rejected. dressup's e2e suite starts its own app on the walker's port and would change the walker's data in the middle of a walk.

## Consequences

- A Gate that CI covers turns red only after the PR opens, and ready-pr fixes it, as it does for a plan with no UI.
- A repo with no CI, or a Gate its CI does not run, still runs that Gate in the Sandbox.
- `checks.txt` says `not run: CI runs it` for each Gate left to CI.
