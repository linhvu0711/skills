# proofbox (deprecated)

`/build-and-prove` used to prove a build with [proofbox](https://github.com/linhvu0711/proofbox): one Namespace Sandbox per run ran the Gates, the app, and the before shots, and a Claude subagent, the walker, filmed the UI walks in it. A Cursor cloud agent, the Proof agent, does that job now (ADR 0019 in `docs/adr/` at the repo root).

proofbox was replaced because the skill had to write and fix a setup script and a secrets file for each repo, and remake a Sandbox that died when idle. In three builds, gaps in that setup failed about ten test runs for reasons outside the code. Cursor installs what a repo needs, and each repo's secrets live in its own Cursor environment.

Nothing here runs. `scripts/link.sh` links nothing from this folder, `scripts/test.sh` runs none of its tests, and no skill reads it. It is kept so the old route can be read, or brought back.

- `scripts/box.sh`: held the Sandbox (`auth`, `up`, `run`, `down`). Its cases are in `tests/box.sh`.
- `agents/walker.md`: the walker subagent.
- `references/walks.md`: the walk rounds on the Sandbox, with the start and stop of the app and the video check of proofbox's cut labels.
- `local-rules.md`: the lines of the local builder rules that sent a slice test to the Sandbox.
- `docs/adr/`: ADR 0009 (every command in the Sandbox) and ADR 0011 (Coding local, the Gates in the Sandbox), superseded by ADR 0019.
- `CONTEXT.md`: the `Walker` and `Sandbox fault` terms.
