# Examples

**User:** `/ship https://github.com/acme/shop/issues/57` on Opus; #57
is a `[fix]`, size S, `ready-to-build`, no screen. The plan's
Review block has no risk.

Plan-up runs its short path and writes the plan. Step 2 picks `ready`:
`small fix, no schema or API, no risk in the plan`. Summary printed, no
page, no wait. `Route: local (no UI)`. build-and-prove: worktree
`~/development/worktrees/acme/shop/fix-57-export-date-iso` from `main`,
no Sandbox, this session builds, every
slice test on the local machine. CI runs `pnpm test`, so it is left to
CI; `box.sh gates --local` runs `pnpm lint`. `BUILT
fix/57-export-date-iso`, `Walks: none (no UI)`. make-pr opens PR 61 with the proof folder's `Proof` part.
ready-pr: `READY https://github.com/acme/shop/pull/61`. Report, with
`Ship mode: ready · small fix, no schema or API, no risk in the plan`
above the `READY` line.

**User:** `/ship --ready https://github.com/acme/shop/issues/42` on
Sonnet; the plan has three UI walks and two videos.

The user typed the mode: `ready`. The plan's Blast radius lists a new
column; you would have picked `review`. The worry is held. `Route: local
(3 walks)`. build-and-prove builds in this session, the walker films two
videos, round 2 passes. make-pr attaches the screenshots and videos.
ready-pr readies PR 44. Report: `Ship mode: ready (set) · plan adds a
column; I would have asked for a review`.

**User:** `/ship https://github.com/acme/shop/issues/70 #71 #73`; the
plan's Blast radius flags a new auth check on #73.

Step 2: one mode for the run, and #73 needs a look, so `review`. The page
opens; the summary has `Ship mode: review · #73 adds an auth check` above
the `Say ok` line. Nothing is built. The user says `ok`. `Route: local
(stack of 2)`. Layer 1: build-and-prove `--layer 1 --base main`,
make-pr opens PR 72 on `main`. Layer 2: `--layer 2 --base
feat/71-team-entity`, make-pr opens PR 74 on that branch. ready-pr on
PR 72, then PR 74. Two report blocks, no merge, each with
`Ship mode: review · #73 adds an auth check`.

**User:** `/ship --review https://github.com/acme/shop/issues/57`.

The user typed the mode. The page opens; the summary has `Ship mode:
review (set)` above the `Say ok` line, and the run waits. The user says
`S2: keep the JSON export as the default`. The `.md` changes, the page is
rebuilt with `v=2`, the summary shows again. The user says `ok`: the
base copy is removed, `Route: local (3 walks)`, and the run goes on as
`ready` does. The report ends `READY https://github.com/acme/shop/pull/43`,
and its `Ship mode:` line is `Ship mode: review (set) · none`. The merge
is the user's.

**User:** `/ship https://github.com/acme/shop/issues/57`; at the wait
(the agent picked `review`) the user says `stop`.

The base copy is removed. `Stopped: nothing built. Plan:
~/.agents/artifacts/plan/plan-acme-shop-57.md`. No worktree, no PR.

**User:** `/ship --merge https://github.com/acme/shop/issues/57`; #57 is a
`[fix]`, size S, no screen.

The user typed the mode: `merge`, the go-ahead. Plan, `Route: local (no
UI)`, build, PR 61, ready. `READY https://github.com/acme/shop/pull/61`
at `9e18c16`. `merge.sh acme/shop 61 --sha 9e18c16…` prints `MERGED
https://github.com/acme/shop/pull/61 merge 4f2a1b0`. `prune-worktrees.sh`
prints `removed ~/development/worktrees/acme/shop/fix-57-export-date-iso
(96M), branch fix/57-export-date-iso deleted (-D)`. Report, with
`Ship mode: merge (set) · none` above the `MERGED` line.

**User:** `/ship https://github.com/acme/shop/issues/80`; the plan names
a small text change and no risk.

Step 2 picks `merge`: `copy change in one file, no risk in the plan`.
Typing `/ship` is the go-ahead. Build, PR 81, `READY`. Before the merge
the agent reads `gh pr diff 81`: the build also changed a shared helper
that six screens call. That is riskier than the plan said, and a pick
can only move to the safer mode. No merge. Report:
`Ship mode: ready (was merge) · the build changed a shared helper six
screens call`, then `READY https://github.com/acme/shop/pull/81`. The
merge is the user's.

**User:** `/ship https://github.com/acme/shop/issues/70 #71 #73`; the
plan has no risk; the repo allows only squash. The agent picks `merge`.

`Route: local (stack of 2)`. PR 72 on `main`, PR 74 on
`feat/71-team-entity`, both `READY`. The diff of 72 matches the plan.
`merge.sh` on 72 prints `MERGED … squash 7c1d2e3`. PR 74 goes to `main`
by `gh pr edit 74 --base main`, is rebased with `--onto origin/main
<OLD>`, pushed, and readied again; `READY`, its diff matches, then
`MERGED … squash 8d2e3f4`. Prune. Two report blocks.

**User:** `/ship --merge https://github.com/acme/shop/issues/42`;
ready-pr ends `READY https://github.com/acme/shop/pull/43 (waiting for
approval)`.

No merge: a person's approval is the user's. The report ends `NOT MERGED
https://github.com/acme/shop/pull/43: waits for approval`. No prune.

**User:** `/ship https://github.com/acme/shop/issues/42 devin`.

`Route: cloud (devin, named)`. Handoff § First prompt whole with Devin,
Monitor on the watch. Later `finished` with PR 44; finish check passes;
Ready step says `READY`. Report with `session: <url>`.

**User:** `/ship https://github.com/acme/shop/issues/88`; the plan says
`Platform: windows`.

`proofbox has no Windows. Build it on Devin?` A yes, B stop. The user
says A: `Route: cloud (devin, asked)`, as above.

**User:** `/plan-up https://github.com/acme/shop/issues/42`, then, once
the page is open, `/ship`.

No issue named, no build yet, and the plan of #42 is in this chat: § No issue
case 2. `Plan: ~/.agents/artifacts/plan/plan-acme-shop-42.md`, step 1 is
skipped. Step 2 picks `ready`: the base copy is removed, and `Route:
local (3 walks)`, then on as for any ticket.

**User:** after a long chat that settled a CSV export for orders, with
no issue: `/ship the CSV export`.

No build, no plan: § No issue case 3. Plan-up's chat form prints
`Brief: [feat] Export orders as CSV · size/M` with its Done-when lines,
the gate passes, the plan is
`plan-acme-shop-chat-export-orders-csv.md`, and step 2 picks `ready`
with no wait. `Route: local (2 walks)`. Branch `feat/export-orders-csv`;
the PR has no `Closes` line. Report.

**User:** `/ship devin` after the same chat.

Case 3 again, then Route: `A chat plan has no issue, so it cannot
build in the cloud. Run /to-issue first.` Stop.

**User:** `/ship https://github.com/acme/shop/issues/61` where the issue
has no Done-when list.

Plan-up's gate fails: the question that closes it, `/grill` named.
Stop. Nothing is built.

**User:** `/ship --ready https://github.com/acme/shop/issues/90`; after
the first wait on PR 91, `reviewers.sh` prints nothing.

No review bot. Review-pr reviews PR 91 and
finds one `🟠 should`; validate-pr-review on its report judges it
`fix here`, the fix is committed and pushed, nothing is posted. Then
ready-pr: `READY https://github.com/acme/shop/pull/91`. The report's
`Route:` line ends ` · review-pr: comment`.
