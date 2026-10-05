# ship

Takes an issue, a plan you already made, or work you agreed on in the chat, to a pull request that is ready to merge, in one run: plan it, build it, make it ready. It never merges.

## Use it when

You have a ready issue and want the whole path done without starting each step by hand. It takes the same arguments as [plan-up](../plan-up/):

- `/ship <issue-url>`: one ticket, one PR.
- `/ship <epic-url> #12 #14`: those tickets from the epic, as a stack of PRs.
- `/ship <issue-url> #14 #15`: a set of plain tickets, as a stack of PRs.
- `/ship <epic-url>`: every open ticket in the epic.
- `/ship <issue-url> on <pr-url>`: one ticket as a new layer on an open stack.
- Any of the above with `devin` or `cursor` at the end: built in the cloud instead.
- `/ship` with no URL, and words after it or none. What the chat holds picks the start:
  - a build this chat started: the words are an answer or a follow-up for it;
  - a plan that `/plan-up` made in this chat: it skips the planning and starts at the build, and words with it are an edit to the plan;
  - neither: it plans the work this chat agreed on, with no issue. It prints a short brief (title, size, Done-when lines) and goes on. If the chat left a gap, it stops and names [grill](../grill/). The PR has no `Closes #<n>` line. A plan with no issue builds only on your machine: the cloud needs an issue, so make one with [to-issue](../to-issue/) first.

It only runs when you call it.

## What you get

First the plan, from [plan-up](../plan-up/), open in your browser, unless the chat already has one. Your checkout can be on any branch, with edits or not; plan-up reads a copy of the base branch and leaves your tree alone. Then the route:

- **Local**, the default, for every plan, with UI walks or without: [build-and-prove](../build-and-prove/) builds it in a git worktree under `~/development/worktrees`, runs every test and the app in one proofbox Sandbox, and has a walker film the walks. Then [make-pr](../make-pr/) opens the PR with the screenshots and videos, and [ready-pr](../ready-pr/) takes it through review. A stack goes layer by layer, bottom first.
- **Cloud**, only when the command names `devin` or `cursor`: that agent builds it through [handoff](../handoff/). A Windows plan asks first, since proofbox has no Windows.

It stops only for a ticket someone else is already on, the plan's big decisions, and the build's surprises. The last message:

```
Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
Route: local · built by: devin pane w4:p9M · walks: 3 in round 2 · review rounds: 2 · Filed: none
Worktree: ~/development/worktrees/acme/app/feat-42-login
After merge: /prune-worktrees
READY https://github.com/acme/app/pull/43
```

A PR that waits only for a person's approval ends with `READY <url> (waiting for approval)`.

## Needs

- `gh` (signed in), `git`, `jq`, and `python3`.
- The skills it chains: [plan-up](../plan-up/), [build-and-prove](../build-and-prove/), [make-pr](../make-pr/), [ready-pr](../ready-pr/), and [handoff](../handoff/) for the cloud, and what they need. build-and-prove needs proofbox.
- The shared core file `../../shared-skill-core/facts.md`.
- For the cloud route: a Devin or Cursor account, as [handoff](../handoff/) describes.

## Fits with

- Calls [plan-up](../plan-up/), then [build-and-prove](../build-and-prove/) and [make-pr](../make-pr/), or [handoff](../handoff/) when you name the cloud, then [ready-pr](../ready-pr/).
- A failed readiness gate sends you to [grill](../grill/) first.
- After the merge, [prune-worktrees](../prune-worktrees/) removes the worktree and its branch.
- Nothing calls this skill; you run it.
