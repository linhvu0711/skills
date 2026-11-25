---
name: recall
description: "Rebuild where you left off on a topic: the recent Claude Code, Codex, and Antigravity sessions on it, one brief of what is done, open, and decided, the live state of each PR, and one next step. Use when the user asks where they left off on a topic."
disable-model-invocation: true
---

# recall: rebuild where you left off on a topic

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

The user comes back to a topic after some days. This skill finds the
sessions of this project on that topic, from Claude Code, Codex, and
Antigravity, and merges what they did into one brief. It reads; it writes nothing and
starts no work.

## Steps

1. **Topic.** The words after the skill's command. None: ask for one
   and wait.

2. **Find.**

   ```bash
   python3 scripts/find.py "<topic>"
   ```

   One line per session, newest first: `<tool> <id> <age> · <n> prompts
   · <title>`, with `<tool>` `claude`, `codex`, or `antigravity`. At most
   10; a `Skipped <k> older sessions.` line says how many more matched. A
   `<Tool> is not installed: <the others> sessions only.` line, as in
   `Codex is not installed: Antigravity and Claude Code sessions only.`,
   means that tool was not searched. Both go on the brief's `Sessions:`
   line in step 5, as in `Sessions: 10 (Claude Code 10, Codex 0,
   Antigravity 0) · skipped 2 older · Codex is not installed`.

   Exit 1: no session is on the topic. Show its last line, `No sessions
   on <topic>.`, and stop.

3. **Render** each session's transcript for its brief writer, in summary
   mode, through its tool's adapter. `<tool>` is the line's first word.
   `<out>` is `<scratch>/recall-<id8>.md`, where `<scratch>` is the scratch
   folder that `../../shared/harness.md` names for your harness.

   ```bash
   python3 ../../shared/sessions/<tool>/adapter.py extract <id> --summary --after-compact > <out>
   ```

   A tool with no compaction view renders the whole summary.

4. **Brief writers.** One per session, all in one message. Build each
   prompt from `../../shared/session-brief.md` § Dispatch,
   with its transcript path and its tool (`Claude Code`, `Codex CLI`, or `Antigravity`)
   filled in. Start one explorer per prompt, all in one message, per
   `../../shared/facts.md` § Skill agents, and wait for every brief.
   Take each brief as `session-brief.md` § Return
   says. A writer that fails is left out, and the brief says so on a
   line `Left out: <id8> (brief writer failed)`.

5. **One brief.** Merge the briefs into this template, and nothing else:

   ```
   # Recall: <topic>
   Sessions: <n> (Claude Code <a>, Codex <b>, Antigravity <c>)
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

6. **Live tags.** Write the brief to `<scratch>/recall-brief.md` and
   tag it with
   `../../shared/sessions/live_tags.py` as
   `../../shared/session-brief.md` § Live tags says, with
   `--cwd` the project folder that step 2 ran in, never this skill's
   folder. The tagged brief is the one you show.

7. **Next line.** The brief's last line is `Next: <one step>`, from the
   first of these that holds:
   - an `[open PR #n]` line: `Next: /ready-pr #<n>`, the newest session's;
   - a `[branch only]` line: `Next: /make-pr` on that branch;
   - an `**Open:**` bullet: `Next:` and that bullet's action;
   - else `Next: nothing open on <topic>.`

8. **Show** the brief and stop.
