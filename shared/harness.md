# Harness table

How each harness does a step a skill names. The rule for when to take a step is in the skill that names it, and for the subagent start rows in `facts.md` § Skill agents, next to this file; this file holds only the tools.

| Step | Claude Code | Codex | Antigravity |
|---|---|---|---|
| Start a subagent by name | The Agent tool with `subagent_type: <name>`. | `spawn_agent` with `agent_type: <name>` and the brief as `message`, then `wait_agent` for its answer. | `invoke_subagent` with `TypeName: <name>`, a `Role` of two to five words, and the brief as `Prompt`. It runs in the background and its answer comes as a message, so end the turn with no tool call. |
| Start the plain subagent | `general-purpose`. | `default`. | `self`. agy's own prompt says it may hang, so start it only when no named agent fits. |
| Model and effort on the start call | `model` takes only `haiku`, `sonnet`, `opus`, or `fable`, and no effort. A named agent runs on its file's model and effort. | None by default: `spawn_agent` shows `model` and `reasoning_effort` only when `expose_spawn_agent_model_overrides` is on. A named agent runs on its file's model and effort. | `Model` takes only `inherit`, `flash_lite`, `flash`, or `pro`, and no effort. |
| Start a home in another harness | T3's `delegate_task`, § T3. | T3's `delegate_task`, § T3. | T3's `delegate_task`, § T3. |
| Wait on a long command | Bash with `run_in_background: true`; the harness wakes you when the command ends. In T3, call `t3_background_wait` with its task id before the turn ends. | `exec_command` with `yield_time_ms`. A result that says the process is still running: poll it with `write_stdin` with empty `chars` and a `yield_time_ms`, until a result carries an exit code. | `run_command` with `WaitMsBeforeAsync`, at most 10000. A longer command goes on as a background task, and a message comes when it ends, so end the turn. `manage_task` with `status` or `kill` and its `TaskId`. |
| Start a subagent in the background | The start by name with `run_in_background: true`; the harness tells you when it ends. | `spawn_agent` returns at once; `wait_agent` only when you need the answer. | `invoke_subagent` always runs so. |
| Watch a command line by line | Monitor with the command and `timeout_ms` at most 1800000, 30 minutes; `persistent: true` for a watch with no end of its own. Each line it prints wakes you. In a `-p` run a Monitor ends at 10 minutes. | `exec_command` with `yield_time_ms`, then `write_stdin` with empty `chars` and a `yield_time_ms`; each result holds the lines printed since the last. Poll until a result carries an exit code. Only while your turn stays open: nothing wakes you after it ends. | None: `run_command` runs it as a background task, and its lines come together when it ends. |
| Send a helper more work | SendMessage to the agent its start named. | `followup_task` to the agent, then `wait_agent`. | `send_message` to the conversation id `invoke_subagent` returned. The answer comes as a message, so end the turn with no tool call. |
| Keep a todo list | TaskCreate and TaskUpdate, or TodoWrite. | `update_plan`. | None. |
| Pick a scratch folder | The scratchpad folder the system prompt names. | A folder from `mktemp -d`, once per run. | A folder from `mktemp -d`, once per run. |
| Check a page in a hidden browser | playwright-cli, § Hidden browser. | The in-app browser. | playwright-cli, § Hidden browser, by `run_command`. |

## T3

T3 Code starts a subagent in any harness it runs, and in Devin, whatever harness you run in. You are in T3 when T3's `delegate_task` is in your tools, under any name that ends in `delegate_task`: a harness puts its server's name in front, as Antigravity lists `mcp_t3-code_delegate_task`. A tool your harness loads late counts too: look it up by that name once before you decide it is not there.

- `orchestrator_capabilities` lists each place by its display name (Claude, Codex, Antigravity, Devin), with its `providerInstanceId`, its models, and each model's effort option: `effort` for Claude, `thought_level` for Antigravity and Devin.
- A place is off when its entry has `canRunChildTask: false`, or a constraint such as `Provider instance is disabled.`
- `delegate_task` takes `target` as `{providerInstanceId, model, options: {<effort option>: <effort>}}`, and the `task` as `facts.md` § Skill agents builds it. Follow the `next` it returns for the answer.
- A helper started through T3 takes no follow-up message. A step that sends a helper more work, such as a walk again or a look again, starts a new `delegate_task` with the same brief and the new part.
- T3 cannot limit a child's tools, so a read-only helper stays read-only only by its instructions.
- `orchestrator_capabilities` gives your own `runtimeMode`. A child gets your mode, or the nearest its place has, and never a broader one. Antigravity has no `auto`, so under an `auto` main its child gets `auto-accept-edits`, which asks the user before each command the helper runs. So a home in Antigravity runs only when your mode is `full-access`. A home in Claude or Devin runs its commands with no asks under `auto` too.

## Hidden browser

playwright-cli drives a browser the user does not see. Run each command from the folder that holds the page, so its `.playwright-cli/` output stays there: `cd <folder> && npx -y @playwright/cli@latest -s=<session> <command>`. `open "<url>"` starts the browser, and `close` ends the session when the check is done. `snapshot` gives element refs; `click <ref>`, `console`, `resize <w> <h>`, and `screenshot --filename <path>` act on the page. The user asks to watch the check: `open --headed "<url>"`, for that run only.
