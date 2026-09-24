# State brief

Shared by `load-cc` and `load-co`. A research agent writes the brief; the
main agent shows it and waits.

## Dispatch

Send the research agent this prompt, verbatim, with the two placeholders
filled. `<transcript>` is the file the extractor wrote in summary mode.
`<tool>` is `Claude Code` or `Codex CLI`.

In Claude Code the agent is Explore; put this line first:
`This is a research brief. Pass it whole through the Explore bridge heredoc; do not read the file yourself.`
In Codex the agent is one `explorer`; send the prompt as it is.

```
Read the file <transcript> in full. It is the transcript of a past <tool> session (user prompts and assistant replies only; tool calls omitted). If it starts with a compaction summary, that summary recaps the earlier part of the chat; treat it as part of the history.

Write a state brief for someone who must continue that work in a new session. Fill this template exactly, with no other sections:

# State brief
**Goal:** one sentence: what the user was trying to get done.
**Done:** bullet list, one observable outcome per line, only things the transcript shows were finished.
**Decisions:** bullet list of choices the user made or agreed to, each with the reason if one was given.
**Open:** bullet list of things asked for but not finished, questions left unanswered, or work the assistant said it would do next.
**Files:** bullet list of file paths the transcript says were created or edited (not files merely read or cited).
**Last exchange:** two lines: the user's last real prompt, then the gist of the assistant's last reply.
**Next step:** one sentence: what the continuing session should do first.

Rules: only facts from the transcript; if a section has nothing, write "none". Quote file paths exactly. Keep every bullet under 25 words. At the very end add one line: "Read: <N> of <total> characters" stating how much of the file you actually read.
```

## Return

Claude Code: the Explore agent's final message is a `STATUS=OK OUT=<path>`
line. Read that file with `cat`; the brief is in it. Any other reply (an
error, or the agent saying it cannot read the file) is a failure.

Codex: the `explorer` reply carries the brief inline. Take it from the
`# State brief` heading to the `Read:` line. A reply with no `# State brief`
heading is a failure.

On failure fall back to the skeleton; do not retry.

## Measured

Tested 2026-09-12 on four real transcripts, 16K to 117K characters, plain,
compacted, and Codex, through the Claude Code Explore bridge. Every brief was
accurate on spot-check against its transcript. Wall time 45 to 130 seconds.
The bridge reads a long file in 50KB passes and reports the count on its last
line; a count short of the total means the brief is partial, say so.
