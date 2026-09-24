# ship

Takes an issue from plan to a pull request that is ready to merge, in one run: plan it, build it, land it. It never merges.

## Use it when

You have a ready issue and want the whole path done without starting each step by hand. It takes the same arguments as [plan-up](../plan-up/):

- `/ship <issue-url>`: one ticket, one PR.
- `/ship <epic-url> #12 #14`: those tickets from the epic, as a stack of PRs.
- `/ship <issue-url> #14 #15`: a set of plain tickets, as a stack of PRs.
- `/ship <epic-url>`: every open ticket in the epic.
- `/ship <issue-url> on <pr-url>`: one ticket as a new layer on an open stack.
- `/ship <note>`: an answer or follow-up for the build this chat started.

It only runs when you call it.

## What you get

First the plan, from [plan-up](../plan-up/), open in your browser. Then the route:

- **Local**, for one ticket with no screen to check: a git worktree under `~/development/worktrees`, a build prompt, and a build. On Fable inside herdr, a Devin CLI pane builds it; on any other model, this chat builds it. Then [land-pr](../land-pr/) takes the PR through review.
- **Cloud**, for a plan with UI walks or a stack: a Devin cloud session through [handoff-devin](../handoff-devin/).

It stops only for the plan's big decisions and the build's surprises. The last message:

```
Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
Route: local · built by: devin pane w4:p9M · review rounds: 2 · Filed: none
Worktree: ~/development/worktrees/app/feat-42-login
Clean up after merge: git -C ~/development/app worktree remove ~/development/worktrees/app/feat-42-login
READY https://github.com/acme/app/pull/43
```

## Needs

- `gh` (signed in), `git`, `jq`, and `python3`.
- The skills it chains: [plan-up](../plan-up/), [handoff-devin](../handoff-devin/), and [land-pr](../land-pr/), and what they need.
- The shared core files `../../shared-skill-core/facts.md`, `../../shared-skill-core/worktree.sh`, and `../../shared-skill-core/handoff/render.sh`.
- For a Devin CLI pane (Fable only): herdr with this chat inside it (`HERDR_ENV=1`), the Devin CLI `devin`, signed in, and the helpers `herdr-wait` and `herdr-send` in `~/.claude/bin`. These two helpers are not in this repo.
- For the cloud route: a Devin account, as [handoff-devin](../handoff-devin/) describes.

## Fits with

- Calls [plan-up](../plan-up/), then [handoff-devin](../handoff-devin/) or a local build, then [land-pr](../land-pr/).
- Uses [kickoff](../kickoff/)'s `equalize_columns.py` to even out pane widths.
- A failed readiness gate sends you to [grill](../grill/) first.
- Nothing calls this skill; you run it.
