# State brief

Shared by `load-cc-session`, `load-co-session`, and `recall`. A research agent writes the brief; the
main agent tags its PRs and branches with their live state, shows it, and waits.

## Dispatch

Send the research agent this prompt, verbatim, with the two placeholders
filled. `<transcript>` is the file the extractor wrote in summary mode.
`<tool>` is `Claude Code` or `Codex CLI`.

In Claude Code the agent is Explore; in Codex it is one `explorer`. Send the
prompt as it is.

```
Read the file <transcript> in full. It is the transcript of a past <tool> session (user prompts and assistant replies only; tool calls omitted). If it starts with a compaction summary, that summary recaps the earlier part of the chat; treat it as part of the history.

Write a state brief for someone who must continue that work in a new session. Fill this template exactly, with no other sections:

# State brief
**Goal:** one sentence: what the user was trying to get done.
**Done:** bullet list, one observable outcome per line, only things the transcript shows were finished.
**Decisions:** bullet list of choices the user made or agreed to, each with the reason if one was given.
**Open:** bullet list of things asked for but not finished, questions left unanswered, or work the assistant said it would do next.
**Files:** bullet list of file paths the transcript says were created or edited (not files merely read or cited).
**PRs and branches:** bullet list, one per PR or branch the transcript names: "PR #<n> · <what it is>", "PR <url> · <what it is>" for another repo, or "branch <name> · <what it is>".
**Last exchange:** two lines: the user's last real prompt, then the gist of the assistant's last reply.
**Next step:** one sentence: what the continuing session should do first.

Rules: only facts from the transcript; if a section has nothing, write "none". Quote file paths exactly. Keep every bullet under 25 words. At the very end add one line: "Read: <N> of <total> characters" stating how much of the file you actually read.
```

## Return

Claude Code: the Explore agent returns the brief in its final message. If
that message is a `STATUS=OK OUT=<path>` line, the brief is in that file:
read it. A status that is not OK, a missing brief, or the agent saying it
cannot read the transcript is a failure.

Codex: the `explorer` reply carries the brief inline. Take it from the
`# State brief` heading to the `Read:` line. A reply with no `# State brief`
heading is a failure.

On failure fall back to the skeleton; do not retry.

## Live tags

Before the brief is shown, write it to a file and run, from this folder:

```bash
python3 sessions/live_tags.py <file> --cwd <folder>
```

`<folder>` is the folder the session ran in, so `gh` and `git` ask its
repo. Show what the script prints. Each line under `**PRs and branches:**`
now starts with its live state:

| Tag | Means |
|---|---|
| `[merged #n]` | the PR, or the branch's newest PR, is merged |
| `[open PR #n]` | it is open |
| `[closed #n]` | it was closed without a merge |
| `[branch only]` | a branch with no PR, here or on GitHub |
| `[branch gone]` | a branch with no PR, not here, and GitHub says it does not exist |
| `[state unknown]` | `gh` cannot find the PR or see the branch, cannot be reached, or is not logged in |

The tags never stop the brief. A PR `gh` cannot find is
`[state unknown]`, and the next lines are still asked. When `gh` itself
fails, the script prints one `live tags: gh failed: <reason>` line on
stderr, that line and every later one is `[state unknown]`, and the
brief shows. The skeleton fallback is not
tagged.

## Measured

Tested 2026-09-12 on four real transcripts, 16K to 117K characters, plain,
compacted, and Codex, through the Claude Code Explore bridge. Every brief was
accurate on spot-check against its transcript. Wall time 45 to 130 seconds.
The bridge reads a long file in 50KB passes and reports the count on its last
line; a count short of the total means the brief is partial, say so.
