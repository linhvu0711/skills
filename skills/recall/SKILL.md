---
name: recall
description: "Rebuild where you left off on a topic: the recent Claude Code and Codex sessions on it, one brief of what is done, open, and decided, the live state of each PR, and one next step."
disable-model-invocation: true
---

# recall: rebuild where you left off on a topic

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

The user comes back to a topic after some days. This skill finds the
sessions of this project on that topic, in Claude Code and in Codex,
and merges what they did into one brief. It reads; it writes nothing and
starts no work.

## Steps

1. **Topic.** The words after `/recall` (`$recall` in Codex). None: ask
   for one and wait.

2. **Find.**

   ```bash
   python3 scripts/find.py "<topic>"
   ```

   One line per session, newest first: `<tool> <id> <age> · <n> prompts
   · <title>`, with `<tool>` `claude` or `codex`. At most 10; a
   `Skipped <k> older sessions.` line says how many more matched. A
   `Codex is not installed: Claude Code sessions only.` line means only
   Claude Code was searched. Both go on the brief's `Sessions:` line in
   step 5, as in `Sessions: 10 (Claude Code 10, Codex 0) · skipped 2 older
   · Codex is not installed`.

   Exit 1: no session is on the topic. Show its last line, `No sessions
   on <topic>.`, and stop.

3. **Render** each session's transcript for its brief writer, in summary
   mode. `<out>` is `<scratchpad>/recall-<id8>.md` in Claude Code and
   `/tmp/recall/<id8>.md` in Codex (`mkdir -p` the folder first).

   ```bash
   python3 ../../shared-skill-core/sessions/claude/extract_session.py <id> --summary --after-compact > <out>   # a claude line
   python3 ../../shared-skill-core/sessions/codex/extract_session.py <id> --summary > <out>                    # a codex line
   ```

4. **Brief writers.** One per session, all in one message. Build each
   prompt from `../../shared-skill-core/session-brief.md` § Dispatch,
   with its transcript path and its tool (`Claude Code` or `Codex CLI`)
   filled in. In Claude Code, send each to an Explore agent. In Codex,
   spawn one `explorer` agent per prompt (`fork_turns = "none"`) and
   `wait_agent` on all. Take each brief as `session-brief.md` § Return
   says. A writer that fails is left out, and the brief says so on a
   line `Left out: <id8> (brief writer failed)`.

5. **One brief.** Merge the briefs into this template, and nothing else:

   ```
   # Recall: <topic>
   Sessions: <n> (Claude Code <a>, Codex <b>)
   **Done:**
   **Decisions:**
   **Open:**
   **PRs and branches:**
   Next: <one step>
   ```

   Each bullet keeps its brief's words and ends with ` (<id8>)`, the
   session it came from, so the user can load that session. The same
   fact in two briefs: keep the newer session's. A `Done` bullet that a
   newer brief lists as `Open`, or the other way round: keep the newer
   one. A section with nothing: `none`. Under `**PRs and branches:**`,
   one line per PR or branch, with the newest session's `<what it is>`.

6. **Live tags.** Write the brief to `<scratchpad>/recall-brief.md`
   (`/tmp/recall/brief.md` in Codex) and tag it with
   `../../shared-skill-core/sessions/live_tags.py` as
   `../../shared-skill-core/session-brief.md` § Live tags says, with
   `--cwd` this folder. The tagged brief is the one you show.

7. **Next line.** The brief's last line is `Next: <one step>`, from the
   first of these that holds:
   - an `[open PR #n]` line: `Next: /ready-pr #<n>`, the newest session's;
   - a `[branch only]` line: `Next: /make-pr` on that branch;
   - an `**Open:**` bullet: `Next:` and that bullet's action;
   - else `Next: nothing open on <topic>.`

8. **Show** the brief and stop.
