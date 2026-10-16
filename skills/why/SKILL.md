---
name: why
description: "Answer why code is the way it is from the record: git history, the PR and its reviews, the issue, the ADRs and CONTEXT.md, and past Claude Code and Codex sessions. Each reason carries an evidence label and its source."
disable-model-invocation: true
---

# why

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

The answer comes from the record, never from what the code looks like it
might be for. Each reason carries one of the four evidence labels of
`../../shared-skill-core/facts.md` (Seen, Inferred, Guess, Unknown), and
a Guess or an Unknown names what was searched. You only read: nothing is
written to the repo or to GitHub.

## Steps

1. **Code.** The words after `/why` (`$why` in Codex) name the code:
   - `<file>:<line>` or `<file>:<start>-<end>`: that range.
   - A file named alone, or a question about a whole file: the whole file,
     and step 2 runs `python3 scripts/trail.py <file>`.
   - A symbol, or a line of code: `git grep -n -F '<it>'`. One hit: the
     range is the function or block around it, read from the file.
     Several: the one the question names, else the first, and say which.
   - A question in words: read the code it names and pick the range the
     same way.

   No hit, or step 2 prints `No such code`: say `Which code do you mean?
   <what you looked for> is not in this repo.` and stop.

2. **Trail.** From the repo's top folder, with `<file>` from there:

   ```bash
   python3 scripts/trail.py <file>:<start>-<end>
   ```

   It prints each commit that changed the lines, newest first, with its
   body, its PR, the PR's reviews and comments on this file, and the
   issue the PR closes. More than 10 commits: the 9 newest and the
   oldest, which made the lines.

   - `No commits: ...`: the lines have no history yet. Go on with steps 3
     and 4.
   - A first line `Not committed yet: <file>:<lines>`: those lines differ
     from HEAD and have no history yet; the commits below are for the rest.
   - A last line `GitHub: not reached: <error>. ...`: go on with git, the
     docs, and the sessions only. The answer's `Searched:` line says
     `GitHub (not reached: <error>)` in place of the PR and issue counts.

3. **Docs.** Search the ADRs and the glossary for the file name without
   its extension, the symbol, and each `#<n>` of a PR or issue from step
   2:

   ```bash
   git grep -n -i -e '<word>' -e '<word>' -- docs/adr CONTEXT.md
   ```

   Read the paragraph around each hit.

4. **Sessions.** `<top>` is the main checkout: the folder that holds the
   path `git rev-parse --path-format=absolute --git-common-dir` prints.
   `<wt>` is `${WORKTREES_ROOT:-$HOME/development/worktrees}/<owner>/<repo>`,
   with owner and repo from `git remote get-url origin`: the build of a
   merged PR often ran in a worktree there that is gone now. `<words>`
   are the file name without its extension and the symbol.

   ```bash
   python3 ../../shared-skill-core/sessions/claude/find_sessions.py "<words>" --json --limit 3 --include-subdirs --project-dir <top> --project-dir <wt>
   python3 ../../shared-skill-core/sessions/codex/find_session.py "<words>" --json --limit 3 --include-subdirs --cwd <top> --cwd <wt>
   ```

   Drop a session whose `is_current` is true, or whose `first_prompt`
   starts with `/why` or `$why`. Render each one left, Claude Code with
   `python3 ../../shared-skill-core/sessions/claude/extract_session.py <id> --summary > <out>`
   and Codex with
   `python3 ../../shared-skill-core/sessions/codex/extract_session.py <id> --summary > <out>`.
   `<out>` is `<scratchpad>/why-<id8>.md` in Claude Code and
   `/tmp/why/<id8>.md` in Codex (`mkdir -p` the folder first). Run
   `grep -n -i` on each `<out>` for the words and read the lines around
   each hit.

5. **Answer.** This template, and nothing else:

   ```
   Why: <the question, or "why <file>:<start>-<end> is this way">
   Code: <file>:<start>-<end>
   - Seen: <reason>. Source: <commit sha7 | PR url | issue url | ADR path | CONTEXT.md:line | session id>
   - Inferred: <reason>. From: <the Seen lines it follows from>. Source: <as above>
   - Guess: <reason>. Searched: <each place looked>
   - Unknown: <what is not known>. Searched: <each place looked>
   Searched: git (<n> commits), GitHub (<n> PRs, <n> issues), docs/adr and CONTEXT.md, sessions (Claude Code <n>, Codex <n>)
   ```

   - **Seen**: a source states the reason in words: a commit message, a
     PR body, a review, an issue, an ADR, a glossary entry, or a session.
   - **Inferred**: no source states it, but it follows from Seen lines.
   - **Guess** and **Unknown**: as `facts.md` says, each after the tries
     above, which its `Searched:` names.

   One line per reason, the most direct first. Keep only the line types
   that have a reason.

   - No source gives a reason: one `Unknown` line, and its `Searched:`
     names each place looked.
   - Two sources give reasons that do not agree: list both, each with its
     own label and source, and after them one line
     `Disagree: <source> and <source>.` Keep both; the reader picks.
