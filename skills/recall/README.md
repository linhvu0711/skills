# recall

Rebuilds where you left off on a topic, from the recent Claude Code, Codex, and Antigravity sessions in this project.

## Use it when

You come back to a topic after some days and want to know what got done, what is still open, and what was decided. `/recall export feature` in Claude Code, `$recall export feature` in Codex. It only runs when you type it.

## What you get

One brief over every session on the topic, newest first:

```
# Recall: export feature
Sessions: 2 (Claude Code 1, Codex 1, Antigravity 0)
**Done:**
- export endpoint and its tests
**Decisions:**
- keep JSON as the default format
**Open:**
- the button still has no loading state
**PRs and branches:**
- [open PR #45] PR #45 · date fix
- [merged #42] PR #42 · export endpoint
Next: /ready-pr #45
```

Each PR and branch carries its live state from `gh` and `git`: merged, open, closed, a branch with no PR, a branch that is gone, or `[state unknown]` when `gh` cannot answer. The last line is the one next step. Recall only reads: it writes nothing and starts no work.

- No session on the topic, or a topic of only common words such as `the`: `No sessions on <topic>.`, and it stops.
- More than 10 sessions: it uses the 10 newest, and the `Sessions:` line says how many it skipped.
- No Codex on this machine: the other tools' sessions only, and the `Sessions:` line says so.
- A session file it cannot open, or a tool whose search fails: a line names the tool and the first such file, and the `Sessions:` line says so.

## Needs

- `python3` (standard library only). Codex keeps older chats compressed (`.jsonl.zst`); reading those needs Python 3.14+ or the `zstd` command. Without either, they are listed as not read.
- The session scripts in the shared core folder [`sessions/`](../../shared/sessions/): `find_all.py` finds every tool's sessions in one call, and each tool's `adapter.py` reads that tool's sessions.
- The shared core file [`session-brief.md`](../../shared/session-brief.md), which holds the shape of each session's brief.
- A sub-agent per session to write its brief: the explorer, from the shared core's agents.
- `gh` and `git`, for the live state of each PR and branch.

## Fits with

- [retrospect](../retrospect/) reads many sessions through the same adapters, to learn from how a build went.

## Credits

The idea came from the `recall` skill and the `session-pickup` playbook in pstack, by Lauren Tan, in [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack). Idea only; none of the text.
