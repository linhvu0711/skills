# Categories

The first question is "where does it work, and where does it not". The
answer places the bug. Each category has a tell, a thing to look at, and an
exit. Name the category in the report.

| Category | Tell | Look at | Exit |
|---|---|---|---|
| Our code | Works on main, not on the branch. Or never worked. | Halve to a `file:line`. | `fix` issue. |
| Local env | Works on CI or for a teammate, not here. | Diff env: lockfile, runtime version, `.env` against `.env.example`, stale build. | Fix command on the clipboard, user runs it. `chore` or `docs` issue only when a check or the setup doc was missing. |
| Live env | Works locally, not deployed. | Diff deploy config, secrets names (not values), infra. Read only. | Ops fix by the user. `chore` issue for a guard when one was missing. |
| Data | Works with fixtures, not with real data. | The bad row, the missing migration, the state that should not exist. | Data fix by the user, plus a `fix` issue for the check that let it in. |
| Dependency | Started failing after an upgrade, no code change. | Bisect versions. The changelog. | `chore` issue to pin or upgrade, or `fix` for a workaround. |
| External service | Started failing, nothing changed on our side. | Status page, our logs, their changelog. | Cannot fix. `fix` or `feat` issue for the unhappy path we never handled. |
| Flaky | Fails sometimes. | Raise the repro rate first. Races, timing, order. | `fix` when the cause is found, else `spike`. |
| Not a bug | The code does what it was told. | The spec, the test, the ADR. | `docs` issue, or nothing. Say why. |

When two categories fit, take the cheaper one to test first. Local env is
cheaper to rule out than our code. Dependency is cheaper than data.

The external row is the one people miss. Many "bugs" are a state the code
never had a line for: the vendor timed out, the list came back empty. The
issue that follows is the unhappy-path line that `to-issue` asks for.
