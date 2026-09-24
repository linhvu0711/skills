# explain-again

Rewrites the agent's last answer in plain words, about a 5th-grade reading level, with the same meaning.

## Use it when

The last answer was too dense and you want it again, simpler. `/explain-again` in Claude Code, `$explain-again` in Codex, or just ask: "say that again, simpler", "less jargon please", "explain it like I'm new to this".

## What you get

The same answer, shorter and in everyday words. Facts, caveats, commands, and paths stay as they were, and nothing new is added.

> Before: "The worktree's HEAD is detached because the rebase stopped on a conflict in `api.ts`; resolve it and run `git rebase --continue`."
>
> After: "Git paused halfway because two changes clash in `api.ts`. Fix that file, then run `git rebase --continue`."

## Needs

Nothing beyond Claude Code or Codex. No tools, no other skills.

## Fits with

Works alone. No other skill in this repo calls it.
