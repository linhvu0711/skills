# recall

Rebuilds where you left off on a topic, from the recent Claude Code and Codex sessions in this project.

## Use it when

You come back to a topic after some days and want to know what got done, what is still open, and what was decided. `/recall export feature` in Claude Code, `$recall export feature` in Codex. It only runs when you type it.

## What you get

One brief over every session on the topic, newest first:

```
# Recall: export feature
Sessions: 2 (Claude Code 1, Codex 1)
**Done:**
- export endpoint and its tests (3f2a9c1e)
**Decisions:**
- keep JSON as the default format (019e631d)
**Open:**
- the button still has no loading state (3f2a9c1e)
**PRs and branches:**
- [open PR #45] PR #45 · date fix (3f2a9c1e)
- [merged #42] PR #42 · export endpoint (3f2a9c1e)
Next: /ready-pr #45
```

Each PR and branch carries its live state from `gh` and `git`: merged, open, closed, a branch with no PR, a branch that is gone, or `[state unknown]` when `gh` cannot answer. The last line is the one next step. Each line ends with the session it came from, so `/load-cc-session 3f2a9c1e` or `/load-co-session 019e631d` pulls that session in. Recall only reads: it writes nothing and starts no work.

- No session on the topic, or a topic of only common words such as `the`: `No sessions on <topic>.`, and it stops.
- More than 10 sessions: it uses the 10 newest, and the `Sessions:` line says how many it skipped.
- No Codex on this machine: Claude Code sessions only, and the `Sessions:` line says so.

## Needs

- `python3` (standard library only). Codex keeps older chats compressed (`.jsonl.zst`); reading those needs Python 3.14+ or the `zstd` command. Without either, they are listed as not read.
- The session adapters in the shared core folder [`sessions/`](../../shared/sessions/). Each tool's `adapter.py` finds and reads that tool's sessions.
- The shared core file [`session-brief.md`](../../shared/session-brief.md), which holds the shape of each session's brief.
- A sub-agent per session to write its brief: the Explore agent in Claude Code, an `explorer` agent in Codex.
- `gh` and `git`, for the live state of each PR and branch.

## Fits with

- [find-cc-session](../find-cc-session/) finds one Claude Code session from a rough description.
- [find-co-session](../find-co-session/) does the same for Codex sessions.
- [load-cc-session](../load-cc-session/) pulls one Claude Code session in, to continue its work.
- [load-co-session](../load-co-session/) does the same for Codex sessions.

## Tests

The cases for [find.py](scripts/find.py) are in [tests/find.sh](tests/find.sh), on the helpers in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.

## Credits

The idea came from the `recall` skill and the `session-pickup` playbook in pstack, by Lauren Tan, in [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack). Idea only; none of the text.
