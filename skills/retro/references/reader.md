# Reader

One reader per session. It reads that session's rendered files and writes one struggle list. The main agent reads only the lists.

## Dispatch

Send each reader this prompt, verbatim, with the placeholders filled. `<files>` is one line per file from step 4: the main transcript first, then each helper log, each with its size in characters. `<tool>` is `Claude Code` or `Codex CLI`.

In Claude Code the reader is an Explore agent; put this line first:
`This is a research brief. Pass it whole through the Explore bridge heredoc; do not read the file yourself.`
In Codex the reader is one `explorer`; send the prompt as it is.

```
Read these files in full, in order, each in parts if it is long. They are one past <tool> session: the main transcript, then the logs of helper agents it started.
<files>

You are looking for struggle: each moment where the agent went wrong or paid too much to get something done. Signs: a long search for one file or fact; a failed command run again with small changes; an edit undone or redone; the user correcting the agent ("no", "wrong", "I said", the same instruction twice); a tool error; a helper agent that stopped short, hit a limit, or came back empty; a large tool output that was barely used; a fact the agent could not reach; a skill or steering file whose text the agent followed into a mistake.

Write the struggle list in this shape, with no other sections:

# Struggle list
Session: <id> · <tool> · <title or first prompt, 60 characters at most> · <project folder>
Read: <characters read> of <total characters> (main and helper logs)

## Moments
1. <what went wrong, one sentence>
   Where: <file name and the turn number, or the timestamp>
   Quote: "<the exact words from the file that show it, 200 characters at most>"
   Cost: <what it took: tool calls, user turns, or time, as the file shows>
   Kind: <navigation | automated check | coding standards | steering file | tool economy | no-op | information access | skill problem | other>
   Fix guess: <the change to the environment that would have stopped it: a check, a pointer, a rule, a skill line; or "none seen">

## Repeated corrections
- "<the user's words, exact>" (<turn>)

Rules: only moments the files show; quote, never paraphrase, in Quote. A smooth session gets "none" under Moments. A correction the user gave once goes in Moments; Repeated corrections holds one the user gave more than once in this session, or "none". Number moments from 1. Keep each line under 40 words.
```

## Return

Claude Code: the Explore agent's final message is a `STATUS=OK OUT=<path>` line. Read that file with `cat`; the struggle list is in it. Codex: the `explorer` reply carries it inline, from the `# Struggle list` heading to the end.

Any other reply, or one with no `# Struggle list`, is a failure; SKILL.md step 5 says what follows. A `Read:` line under the total means the reader read only part: the report marks that session "read in part".
