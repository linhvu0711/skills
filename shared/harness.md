# Harness table

How each harness does a step a skill names. The rules for when to take each step are in `facts.md` § Skill agents, next to this file; this file holds only the tools.

| Step | Claude Code | Codex | Antigravity |
|---|---|---|---|
| Start a subagent by name | The Agent tool with `subagent_type: <name>`. | `spawn_agent` with `agent_type: <name>` and the brief as `message`, then `wait_agent` for its answer. | `invoke_subagent` with `TypeName: <name>`, a `Role` of two to five words, and the brief as `Prompt`. It runs in the background and its answer comes as a message, so end the turn with no tool call. |
| Start the plain subagent | `general-purpose`. | `default`. | `self`. agy's own prompt says it may hang, so start it only when no named agent fits. |
| Model and effort on the start call | `model` takes only `haiku`, `sonnet`, `opus`, or `fable`, and no effort. A named agent runs on its file's model and effort. | None by default: `spawn_agent` shows `model` and `reasoning_effort` only when `expose_spawn_agent_model_overrides` is on. A named agent runs on its file's model and effort. | `Model` takes only `inherit`, `flash_lite`, `flash`, or `pro`, and no effort. |
| Start a home in another harness | T3's `delegate_task`, § T3. | T3's `delegate_task`, § T3. | T3's `delegate_task`, § T3. |
| Wait on a long command | Bash with `run_in_background: true`; the harness wakes you when the command ends. In T3, call `t3_background_wait` with its task id before the turn ends. | `exec_command` with `yield_time_ms`. A result that says the process is still running: poll it with `write_stdin` with empty `chars` and a `yield_time_ms`, until a result carries an exit code. | `run_command` with `WaitMsBeforeAsync`, at most 10000. A longer command goes on as a background task, and a message comes when it ends, so end the turn. `manage_task` with `status` or `kill` and its `TaskId`. |

## T3

T3 Code starts a subagent in any harness it runs, and in Devin, whatever harness you run in. You are in T3 when `delegate_task` is in your tools.

- `orchestrator_capabilities` lists each place by its display name (Claude, Codex, Antigravity, Devin), with its `providerInstanceId`, its models, and each model's effort option: `effort` for Claude, `thought_level` for Antigravity and Devin.
- A place is off when its entry has `canRunChildTask: false`, or a constraint such as `Provider instance is disabled.`
- `delegate_task` takes `target` as `{providerInstanceId, model, options: {<effort option>: <effort>}}`, and the `task` as `facts.md` § Skill agents builds it. Follow the `next` it returns for the answer.
- T3 cannot limit a child's tools, so a read-only helper stays read-only only by its instructions.
- `orchestrator_capabilities` gives your own `runtimeMode`. A child gets your mode, or the nearest its place has, and never a broader one. Antigravity has no `auto`, so under an `auto` main its child gets `auto-accept-edits`, which asks the user before each command the helper runs. So a home in Antigravity runs only when your mode is `full-access`. A home in Claude or Devin runs its commands with no asks under `auto` too.
