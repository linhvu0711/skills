---
name: kickoff-t3
description: "Start /ship-ready, /ship-full, or /plan-up in a new T3 Code thread on issues named by number, URL, or words: one ticket, a run of epic tickets, a set, or a whole epic. A script picks the model, effort, and command from the labels unless the user names them, and makes the repo a T3 project; the agent starts the thread. Stops once the thread runs."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

A script decides what to start; you start it with T3's tools. Read
`../../shared/kickoff/target.md` first: the target forms, the flags,
the table, and how to turn the user's words into a target.

## Steps

1. **Target.** Resolve the target and the flags from the user's words,
   per `target.md` § Resolving the target from the session.
2. **Script.**

   ```bash
   scripts/kickoff.sh [flags] <target>
   ```

   Exit 1: the last stderr line starts with `stop:`. Show it as is and
   stop. Nothing started. Exit 0: hold the one JSON line it prints. Its
   keys: `number`, `title`, `command`, `command_from`, `model`,
   `model_from`, `effort`, `effort_from`, `reason`, `base`, `path`,
   `thread_title`, `message`, `runtime_mode`, `project`.
3. **Model.** T3 keeps an alias as given and does not map it to a model,
   so you map it. A full model name, such as `claude-opus-5-5`, passes
   as is. An alias (`opus`, `sonnet`, `haiku`): call
   `orchestrator_capabilities` with `search` set to the alias, and take
   the first model of the `claudeAgent` provider whose id starts with
   `claude-<alias>-`. None: say `stop: T3 has no <alias> model` and
   stop.
4. **Project.** Call `t3_project_list`, and page with `nextCursor`
   until a project's `workspaceRoot` equals `path`. Hold its `id`. None:
   say `stop: no T3 project for <path>` and stop.
5. **Thread.** One `t3_thread_launch`:
   - `projectId`: the id from step 4
   - `title`: `thread_title`
   - `message`: `message`
   - `modelSelection`: `{instanceId: "claudeAgent", model: <the id from step 3>, options: {effort: <effort>}}`
   - `runtimeMode`: `runtime_mode`
   - no `workspaceStrategy`: the command makes its own worktree.

   An error or no reply: call `t3_thread_list` on that project before
   you try again, so you do not start the thread twice. Its title is
   there: it started.
6. **Report.** Print one line and stop:

   ```
   #<number> <title> → <link> · /<command> (<command_from>) · model <model id> (<model_from>) · effort <effort> (<effort_from>) · <reason> · base <base> · project <project>
   ```

   `<link>` is the thread's `link` from step 5, as it is. The command
   now talks to the user in the new thread. Do not watch it, read its
   plan, or run `/handoff` from here.

One thread for all the issues, unless the user asks for one each. One
each: steps 2 to 6 once per issue, one after the other.

## Examples

**User:** `/kickoff-t3 https://github.com/acme/shop/issues/42`, in a T3
chat; #42 is `size/M`, and the checkout is a T3 project.

The script prints the line with `command` `plan-up`, `model` `opus`,
`effort` `medium`, `project` `found`. `opus` maps to
`claude-opus-5-5`. The project with that `workspaceRoot` is found. One
`t3_thread_launch`. Say
`#42 Export orders as CSV → [i42 Export orders as CSV](t3-thread://v1/…) · /plan-up (default) · model claude-opus-5-5 (default) · effort medium (default) · size M · base main · project found`.
Stop.

**User:** `/kickoff-t3 42 with sonnet xhigh`, in a session about
acme/shop.

Run `kickoff.sh --model sonnet --effort xhigh
https://github.com/acme/shop/issues/42`. The command still comes from
the table. `sonnet` maps to the first `claude-sonnet-` id.

**User:** `/kickoff-t3 42`, in a herdr pane, not in T3 Code.

The script says `stop: not inside T3 Code`. Show it. Stop. Nothing
started.

**User:** `/kickoff-t3 42` for a repo whose checkout is not a T3
project yet.

The script adds it and says `project` `added`. Step 4 finds the new
project. The report ends `· project added`.

**User:** `what would /kickoff-t3 do for issue 70?`

Do not run the script. Read #70's labels and answer from the table in
`target.md`: the model, effort, and command it would pick, and why.
