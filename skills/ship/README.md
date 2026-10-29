# ship

Takes an issue, a plan you already made, or work you agreed on in the chat, to a pull request, in one run: plan it, build it, make it ready, and merge it when that is the right call. How far it goes is the ship mode, and the agent picks it from its own plan unless you type one.

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

Put `--review`, `--ready`, or `--merge` first to set the ship mode, as in `/ship --merge <issue-url>`. It only runs when you call it.

## What you get

**The ship mode.** One of three, for the whole run:

- `review`: the plan opens as a page in your browser and nothing is built until you say `ok`. To change the plan, name a ref and what to change, as in `S2: keep JSON as the default`; the page is rebuilt and the run waits again. `stop` ends the run with nothing built and keeps the plan file. After `ok` it goes on as `ready` does.
- `ready`: no stop. The run ends at a PR that is ready to merge. The merge is yours.
- `merge`: no stop. The run merges each PR once it is ready, then removes the merged worktrees.

With one of the three options, that mode is used. With none, the agent reads the plan's Review block (Blast radius, Choices, Risks) and the issue, and picks by its own judgment. There are no fixed rules, see [ADR 0014](../../docs/adr/0014-the-agent-picks-the-ship-mode.md). When it is unsure between two, it takes the safer one. With many tickets it picks one mode for the run, and `review` when any ticket needs it. Typing `/ship` with no option is your go-ahead to merge when the agent picks `merge`.

Two guards stay in every mode. The plan's big forks still stop for you. And before each merge the agent picked, it reads the PR's real diff again; if the change is riskier than the plan said, it does not merge that PR or the PRs above it, and the report says so. It can only move to a safer mode, never a riskier one. A mode you typed is not stopped by that check: the worry goes in the report.

**The plan,** from [plan-up](../plan-up/), as a `.md` file, unless the chat already has one. Your checkout can be on any branch, with edits or not; plan-up reads a copy of the base branch and leaves your tree alone. Unless the ship mode is `review`, no page opens: the chat gets a short summary with the file's path, and the run goes on.

**The run.** It keeps a todo list of its steps and of each skill it runs, so it keeps its place when the chat is compacted; a step it skips stays in the list with the reason. It never merges outside its merge step, never force-pushes a branch it did not make, and never closes a PR; the rules sit together at the top of the skill. Then the route:

- **Local**, the default, for every plan, with UI walks or without: [build-and-prove](../build-and-prove/) builds it in a git worktree under `~/development/worktrees`, writes and tests each slice on the local machine, runs the Gates and the app in one proofbox Sandbox, and has a walker film the walks. Then [make-pr](../make-pr/) opens the PR with the screenshots and videos, and [ready-pr](../ready-pr/) takes it through review. After the PR's first checks are done, it looks on that PR for a review bot from a short list in `../../shared/review/reviewers.tsv` (Devin Review, CodeRabbit, Cursor Bugbot, Greptile, Macroscope). With none there, [review-pr](../review-pr/) reviews the PR first, and its findings are judged and fixed like a bot's, with nothing posted. A bot not on the list gets a local review too: one review too many, never one too few. Each push of fixes gets a new review; after three rounds that push, one last review fixes nothing and stops the run if it still finds something. Review fixes run their tests on your machine and leave the full suite and the build to the PR's CI when a workflow runs those commands; each one no workflow runs, or all of them in a repo with no CI, runs in a Sandbox. A stack goes layer by layer, bottom first. On a `perf` plan, a review fix to the code the perf command runs measures base and head again in a Sandbox, and the PR's `before → after` row is written again.
- **Cloud**, only when the command names `devin` or `cursor`: that agent builds it through [handoff](../handoff/). A Windows plan asks first, since proofbox has no Windows.

It stops only for a ticket someone else is already on, the plan's big decisions, the build's surprises, and a review finding it cannot settle alone, such as a risky one it would not fix.

**The merge,** in ship mode `merge`:

- A PR is merged only when its ready step says `READY` with no wait for a person's approval. A PR that is not ready, or waits for an approval, stays open, and so do the PRs above it.
- It merges only at the head commit that the ready step checked. If someone pushed after that check, GitHub refuses the merge and the run stops.
- The method is a merge commit when the repo allows it, else squash, else rebase. A merge commit keeps one commit per slice, and the next PR in a stack needs no rebase.
- In a stack, after a PR merges, the next one points at the base branch, is rebased when the method was squash or rebase, and is made ready again before its merge.
- It never uses `--admin`, auto-merge, or a merge queue, and never pushes to the base branch. The repo's branch rules stay in force.
- After the last merge, [prune-worktrees](../prune-worktrees/) removes the worktrees whose PR merged, with their branches.
- A new layer on an open stack (`on <pr-url>`) is made ready but not merged, since the PR under it is not this run's.

**The last message.** One `Ship mode:` line per PR, above its last line. The PR body has no ship mode:

```
Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
Route: local · built by: claude pane w4:p9M · walks: 3 in round 2 · review rounds: 2 · Filed: none
Worktree: ~/development/worktrees/acme/app/feat-42-login
After merge: /prune-worktrees
Ship mode: ready · small fix, no schema or API, no risk in the plan
READY https://github.com/acme/app/pull/43
```

- A PR that waits only for a person's approval ends with `READY <url> (waiting for approval)`.
- Ship mode `merge` ends with the merge line, `MERGED https://github.com/acme/app/pull/43 merge 4f2a1b0`, and the lines `prune-worktrees` printed in place of the `After merge` line. A PR it did not merge ends `NOT MERGED <url>: <why>`.
- A mode you typed reads `Ship mode: merge (set) · <worry or none>`.
- A PR the re-check held back reads `Ship mode: ready (was merge) · <why>`, and ends with its `READY` line.

Each fact it states carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- `gh` (signed in, and allowed to merge in the repo for ship mode `merge`), `git`, `jq`, and `python3`.
- The skills it chains: [plan-up](../plan-up/), [build-and-prove](../build-and-prove/), [make-pr](../make-pr/), [review-pr](../review-pr/), [ready-pr](../ready-pr/), and [handoff](../handoff/) for the cloud, and what they need. build-and-prove needs proofbox.
- [prune-worktrees](../prune-worktrees/) and [fix-conflicts](../fix-conflicts/) for ship mode `merge`.
- The shared core files `../../shared/facts.md`, `../../shared/plan-page.md`, and `../../shared/review/reviewers.sh`, with its list `reviewers.tsv`.
- For `review`: a browser on this machine for the plan page. With none, plan-up publishes the page as an artifact.
- For the cloud route: a Devin or Cursor account, as [handoff](../handoff/) describes.

## Fits with

- Calls [plan-up](../plan-up/), then [build-and-prove](../build-and-prove/) and [make-pr](../make-pr/), or [handoff](../handoff/) when you name the cloud, then [review-pr](../review-pr/) when the repo has no review tool, then [ready-pr](../ready-pr/).
- A failed readiness gate sends you to [grill](../grill/) first.
- In a stack, runs [ready-pr](../ready-pr/) again on each PR after the one below it merges, and [prune-worktrees](../prune-worktrees/) at the end.
- [kickoff-t3](../kickoff-t3/) and [kickoff-herdr](../kickoff-herdr/) start it in a new thread or pane, and [orchestrate](../orchestrate/) starts it for each ticket it runs; else you run it.

## Credits

The todo list and the order for a red check in [ready-pr](../ready-pr/) take an idea from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). The split between a run that stops at a ready PR and a run that merges takes the idea of `full-stop` and `full-send` from [tstack](https://github.com/t3dotgg/tstack) by Theo Browne (MIT). No text was copied.

## Tests

The cases for its script are in [tests/](tests/), one file per script, on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
