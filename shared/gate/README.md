# Subagent gate

The gate is one script, `subagent-gate.sh`, that Claude Code and Codex run before a subagent's tool call. It reads the call and allows it or blocks it with a message that names the rule.

## The rules

- The main agent is blocked in one case only. In T3, its first start by name of a helper whose first try is not its own harness is refused, and the message names the try and says to start it through T3. A second start by name of the same helper in the same chat goes through and runs on the last try, the harness's own model, for when no try can run.
- A subagent may start another one only when its agent file lists the `Agent` tool, and only a shared agent: the explorer or the runner. Today only plan-up's two checkers list it. So a checker can start the explorer, the scope reviewer cannot, and the explorer cannot start a third level.
- A subagent whose agent file lists neither `Edit` nor `Write` may not use a file edit tool. No agent file in this repo lists them today. The runner and the walker still write their own files through the shell, as their instructions allow. A plain subagent, or an agent the repo does not ship, is not checked.
- A payload the gate cannot read is let through, so a broken gate never stops the main work.

## Where it runs

- Claude Code: a `PreToolUse` hook on `Agent`, `Task`, `Edit`, `Write`, `MultiEdit`, and `NotebookEdit`, run as `subagent-gate.sh claude`.
- Codex: a `PreToolUse` hook on `spawn_agent` and `apply_patch`, run as `subagent-gate.sh codex`. Codex runs a new or changed hook only after you trust it: at the next start it shows "Hooks need review"; pick "Trust all and continue". In T3, Codex runs through one shared app server that does not carry T3's thread id, so for the main agent's check the gate reads the chat's log, whose first line names `T3 Code` as the app that opened it.

## How it gets there

`scripts/link.sh` adds the Claude Code and Codex entries on each commit, checkout, merge, and rebase in the main checkout. It changes only an entry that runs this script, so your other hooks stay. Antigravity runs no copy of the gate: you run it only inside T3.

## Not covered

- A helper that T3 starts, whatever its harness: Claude Code, Codex, Antigravity, or Devin. T3 starts it as a chat of its own, with no agent name the gate can read, so the gate sees it as a main agent and lets every call through. Devin runs no hook of ours at all. Such a helper is read-only by its instructions only.
