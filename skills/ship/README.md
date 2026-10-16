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

First the plan, from [plan-up](../plan-up/), as a `.md` file, unless the chat already has one. No page opens in your browser: the chat gets a short summary with the file's path, and the run goes on. To read and approve the plan as a page first, run [plan-up](../plan-up/) alone. Your checkout can be on any branch, with edits or not; plan-up reads a copy of the base branch and leaves your tree alone. It keeps a todo list of its steps and of each skill it runs, so it keeps its place when the chat is compacted; a step it skips stays in the list with the reason. It never merges, never force-pushes a branch it did not make, and never closes a PR; the three rules sit together at the top of the skill. Then the route:

- **Local**, the default, for every plan, with UI walks or without: [build-and-prove](../build-and-prove/) builds it in a git worktree under `~/development/worktrees`, writes and tests each slice on the local machine, runs the Gates and the app in one proofbox Sandbox, and has a walker film the walks. Then [make-pr](../make-pr/) opens the PR with the screenshots and videos, and [ready-pr](../ready-pr/) takes it through review. In a repo with no review tool on its recent PRs, [review-pr](../review-pr/) reviews the PR first, and its findings are judged and fixed like a review tool's, with nothing posted. Each push of fixes gets a new review; after three rounds that push, one last review fixes nothing and stops the run if it still finds something. Review fixes run their tests on your machine and leave the full suite and the build to the PR's CI when a workflow runs those commands; each one no workflow runs, or all of them in a repo with no CI, runs in a Sandbox. A stack goes layer by layer, bottom first. On a `perf` plan, a review fix to the code the perf command runs measures base and head again in a Sandbox, and the PR's `before → after` row is written again.
- **Cloud**, only when the command names `devin` or `cursor`: that agent builds it through [handoff](../handoff/). A Windows plan asks first, since proofbox has no Windows.

It stops only for a ticket someone else is already on, the plan's big decisions, the build's surprises, and a review finding it cannot settle alone, such as a risky one it would not fix. The last message:

```
Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
Route: local · built by: claude pane w4:p9M · walks: 3 in round 2 · review rounds: 2 · Filed: none
Worktree: ~/development/worktrees/acme/app/feat-42-login
After merge: /prune-worktrees
READY https://github.com/acme/app/pull/43
```

A PR that waits only for a person's approval ends with `READY <url> (waiting for approval)`.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- `gh` (signed in), `git`, `jq`, and `python3`.
- The skills it chains: [plan-up](../plan-up/), [build-and-prove](../build-and-prove/), [make-pr](../make-pr/), [review-pr](../review-pr/), [ready-pr](../ready-pr/), and [handoff](../handoff/) for the cloud, and what they need. build-and-prove needs proofbox.
- The shared core files `../../shared-skill-core/facts.md` and `../../shared-skill-core/review-tools/detect.sh`.
- For the cloud route: a Devin or Cursor account, as [handoff](../handoff/) describes.

## Fits with

- Calls [plan-up](../plan-up/), then [build-and-prove](../build-and-prove/) and [make-pr](../make-pr/), or [handoff](../handoff/) when you name the cloud, then [review-pr](../review-pr/) when the repo has no review tool, then [ready-pr](../ready-pr/).
- A failed readiness gate sends you to [grill](../grill/) first.
- After the merge, [prune-worktrees](../prune-worktrees/) removes the worktree and its branch.
- [kickoff](../kickoff/) starts it in a new pane; else you run it.

## Credits

The todo list and the order for a red check in [ready-pr](../ready-pr/) take an idea from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
