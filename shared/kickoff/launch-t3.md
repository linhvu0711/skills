# Launch a T3 thread

Shared by every skill that starts a command in a new T3 Code thread. The
caller holds a JSON line with `model`, `effort`, `path`, `thread_title`,
`message`, and `runtime_mode`, as kickoff-t3's kickoff script prints
it. This file starts the thread from that line with T3's tools.
A `stop:` line below ends the caller's run: nothing started.

## Steps

1. **Model.** T3 keeps an alias as given and does not map it to a model,
   so you map it. A full model name, such as `claude-opus-5-5`, passes
   as is. An alias (`opus`, `sonnet`, `haiku`): call
   `orchestrator_capabilities` with `search` set to the alias, and take
   the first model of the `claudeAgent` provider whose id starts with
   `claude-<alias>-`. None: say `stop: T3 has no <alias> model` and
   stop.
2. **Project.** Call `t3_project_list`, and page with `nextCursor`
   until a project's `workspaceRoot` equals `path`. Hold its `id`. None:
   say `stop: no T3 project for <path>` and stop.
3. **Thread.** One `t3_thread_launch`:
   - `projectId`: the id from step 2
   - `title`: `thread_title`
   - `message`: `message`
   - `modelSelection`: `{instanceId: "claudeAgent", model: <the id from step 1>, options: {effort: <effort>}}`
   - `runtimeMode`: `runtime_mode`
   - no `workspaceStrategy`: the command makes its own worktree.

   An error or no reply: call `t3_thread_list` on that project before
   you try again, so you do not start the thread twice. Its title is
   there: it started.

Done when the thread runs and you hold its `link` from the reply.
