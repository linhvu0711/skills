# fix-conflicts

Resolves a merge or rebase that stopped on conflicts, keeping what each side meant to do.

## Use it when

A `git merge` or `git rebase` is stuck on conflicts and you want them resolved, not aborted. Ask the agent to fix the conflicts, or type `/fix-conflicts`. The agent can also pick it up on its own.

## What you get

For each conflict it reads the history, the commits, and the linked PRs and issues to learn why each side changed, then resolves every hunk. Where both intents fit, it keeps both. Where they clash, it takes the one that matches the merge's goal and tells you the trade-off. It never invents new behaviour and never runs `--abort`. Then it runs the repo's checks (typecheck, tests, format), fixes what the merge broke, and finishes the merge or the whole rebase.

## Needs

- `git`, with a merge or rebase in progress.
- The repo's own checks, which it finds and runs.

## Fits with

Called by [land-pr](../land-pr/) when a rebase onto the base branch conflicts.

## Credits

A copy of the `resolving-merge-conflicts` skill from [mattpocock/skills](https://github.com/mattpocock/skills) (`engineering/resolving-merge-conflicts`), MIT license. The skill text is upstream's; this repo does not reword it.
