---
status: accepted
---

# The proof runs on a Cursor agent

In `/build-and-prove`, Coding runs on the local machine, and one Cursor cloud agent per run, the Proof agent, does the rest: the before shots, the Gates, the UI walks with their videos, and the perf measure. It starts at the same time as Coding, so a missing secret shows in minutes and the before shots are ready when Coding ends. Each later round, and each re-film `/ship` asks for after review, is a follow-up message to the same agent. The skill downloads the agent's artifacts into the proof folder, so `/make-pr` works as before. This replaces the proofbox Sandbox of ADR 0011, now in `deprecated/proofbox/`.

## Considered options

- Keep proofbox: rejected. The skill had to write and fix a setup script and a Secrets file for each repo, and to remake a Sandbox that dies when idle. In three builds, gaps in that setup failed about ten test runs for reasons outside the code (ADR 0011). Cursor installs what the repo needs, and each repo's secrets live in its own Cursor environment.
- Let Cursor test and demo in its own way: rejected. The proof must answer the plan's walks line by line, as a test user (ADR 0010).

## Consequences

- `/build-and-prove` pushes the branch, with no PR, so the agent can check it out.
- Only the prompt tells the agent not to commit or push. Nothing checks it after the run.
- Cursor's own machines run Linux. A `macos-outpost` plan runs the agent on a rented Namespace Mac, which the skill gives back when the run ends.
- Secrets live in the repo's Cursor environment, which the user fills once. The skill never sees their values.
