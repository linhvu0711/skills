# Subagent gate

The gate is one script, `subagent-gate.sh`, that each harness runs before a subagent's tool call. It reads the call and allows it or blocks it with a message that names the rule.

## The rules

- The main agent is never blocked.
- A subagent may start another one only when its agent file lists the `Agent` tool, and only a shared agent: the explorer or the runner. Today only plan-up's two checkers list it. So a checker can start the explorer, the scope reviewer cannot, and the explorer cannot start a third level.
- A subagent whose agent file lists neither `Edit` nor `Write` may not use a file edit tool. No agent file in this repo lists them today. The runner and the walker still write their own files through the shell, as their instructions allow. A plain subagent, or an agent the repo does not ship, is not checked.
- A payload the gate cannot read is let through, so a broken gate never stops the main work.

## Where it runs

- Claude Code: a `PreToolUse` hook on `Agent`, `Task`, `Edit`, `Write`, `MultiEdit`, and `NotebookEdit`, run as `subagent-gate.sh claude`.
- Codex: a `PreToolUse` hook on `spawn_agent` and `apply_patch`, run as `subagent-gate.sh codex`. Codex runs a new or changed hook only after you trust it: at the next start it shows "Hooks need review"; pick "Trust all and continue".
- Antigravity: a `PreToolUse` hook in the "skills" plugin's `hooks.json`, run as `subagent-gate.sh antigravity`. Antigravity does not tell a hook which subagent made the call, so the gate reads the subagent's start message, which Antigravity keeps in the chat's own folder. If a new Antigravity version moves that file, the gate reads every call as the main agent's and blocks nothing there.

## How it gets there

`scripts/link.sh` adds the Claude Code and Codex entries on each commit in the main checkout. It changes only an entry that runs this script, so your other hooks stay.

## Not covered

- A helper that T3 starts, in Claude Code, Codex, Antigravity, or Devin. T3 starts it as a chat of its own, with no agent name the gate can read, so the gate sees it as a main agent and lets every call through. Devin runs no hook of ours at all. Such a helper is read-only by its instructions only.
