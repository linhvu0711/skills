---
name: sync-harnesses
description: "Check that Claude Code, Codex, and Antigravity on this Mac have the repo's skills and subagents and the owner's rules and gates, and that Devin in T3 answers on SWE-2; remake missing links with the repo's link.sh and report the rest. Use when the user types /sync-harnesses in Claude Code or $sync-harnesses in Codex, or says 'sync harnesses', 'check my harnesses'."
disable-model-invocation: true
---

# sync-harnesses

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

The script fixes what a link can fix and reports the rest. Its lines are
the reply.

## Steps

1. Run it from any folder:

   ```bash
   bash scripts/sync-harnesses.sh
   ```

2. Reply with its stdout, verbatim, and nothing more, on exit 0 and on
   exit 1. Exit 1 means it printed a `problem:` line.
