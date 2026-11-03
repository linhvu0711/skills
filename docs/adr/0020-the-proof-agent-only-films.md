---
status: accepted
---

# The Proof agent only films

In `/build-and-prove`, the Cursor Proof agent of ADR 0019 starts only for a plan with UI walks, and it only takes the before shots and films the walks. The Gates run once: the PR's CI runs each one a file under `.github/workflows/` names, and the local machine runs the rest, one at a time, after the push. The perf measure runs on the local machine too, base and head in turns. A plan with `UI: none` starts no agent and needs no Cursor key or credit. This amends ADR 0019, whose agent also ran the Gates and the perf measure.

## Considered options

- Every Gate on the Proof agent (ADR 0019): rejected. Coding had already run each slice's test on the local machine, and CI runs the full suite again on the PR, so the agent was the third run of the same checks. A plan with no screen still paid for an agent and waited for it to start.
- Every Gate on the local machine: rejected. A full suite there overloads it when two builds run at once (ADR 0011), and CI runs it again anyway.

## Consequences

- A red Gate that CI covers shows only after the PR opens. `/ready-pr` already fixes red CI checks, so the PR waits and nothing ships red.
- A perf number from the local machine is noisier than one from a clean machine. Base and head run in turns on the same machine, so the noise hits both sides.
- After a review fix, `/ship` runs the Gates CI does not cover and the perf measure on the local machine. Only a re-film goes to the agent.
