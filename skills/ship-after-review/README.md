# ship-after-review

Does the same run as [ship-ready](../ship-ready/), with one stop: the plan opens as a page in your browser, and nothing is built until you say `ok`. Plan it, you review it, then build it and make it ready. It never merges.

## Use it when

You want to read and approve the plan before any code is written, and still have the rest done in one run. It takes the same arguments as [ship-ready](../ship-ready/):

- `/ship-after-review <issue-url>`: one ticket, one PR.
- `/ship-after-review <epic-url> #12 #14`, `/ship-after-review <issue-url> #14 #15`, `/ship-after-review <epic-url>`: a stack of PRs, one plan page for the whole stack.
- `/ship-after-review <issue-url> on <pr-url>`: a new layer on an open stack.
- Any of the above with `devin` or `cursor` at the end: built in the cloud after your `ok`.
- `/ship-after-review` with no URL: the plan or the work this chat holds, as for ship-ready. A plan from `/plan-up` that has no `ok` yet shows its page again and waits. Words with a plan you already approved are an edit: the page shows again and waits for a new `ok`.

Use [ship-ready](../ship-ready/) when you trust the plan without a look, and [ship-full](../ship-full/) when you also want the merge done. It only runs when you call it.

## What you get

- The plan page from [plan-up](../plan-up/), open in your browser, and its short summary in chat. The run waits there.
- To change the plan, name a ref and what to change, as in `S2: keep JSON as the default`. The page is rebuilt and the run waits again.
- `ok` starts the build. From there it is the same as [ship-ready](../ship-ready/): build, PR, review, ready, and the same last message, ending with `READY <url>`.
- `stop` ends the run with nothing built. The plan file stays, so you can run again later.
- It never merges, never force-pushes a branch it did not make, and never closes a PR.

## Needs

- Everything [ship-ready](../ship-ready/) needs.
- A browser on this machine for the plan page. With none, plan-up publishes the page as an artifact.

## Fits with

- Follows [ship-ready](../ship-ready/) whole and adds only the plan review.
- Runs [plan-up](../plan-up/) with its page and its wait, as plan-up does alone.
- After the merge, [prune-worktrees](../prune-worktrees/) removes the worktree and its branch.
