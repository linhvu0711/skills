# An orchestrate run knows its own PRs by their createdAt

When the orchestrator routes an issue, an open PR on it can be one the run's own thread opened, or one from before the run. `run_prs` in `orchestrate.sh` tells them apart by the PR's `createdAt` and the run's `started_at` (#453).

With no open PR from before the run, a PR made after the run started is that thread's work, and it does not make the issue wait. Once a PR from before the run is open, every open PR counts, so two of them still make the issue wait. A `ready-pr` answer counts every PR, because the user named that PR's step. GitHub links no PR to the thread that opened it, so the time is the one fact both sides hold.
