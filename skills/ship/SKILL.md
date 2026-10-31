---
name: ship
description: "Take any target (one issue, a run of epic tickets, a set, a whole epic, or a new layer on a stack) from plan to PRs in one run, and pick how far to take it: the ship mode. review opens the plan as a page and waits for your ok; ready stops at ready-to-merge PRs; merge merges them. /plan-up first, same arguments. Add --review, --ready, or --merge to set the ship mode. With no option, the agent picks it from its own plan, the safer one when unsure; typing /ship with no option is the go-ahead to merge when the agent picks merge. With no URL, it starts from the plan /plan-up already made in this chat, or plans the work this chat agreed on with no issue. By default, /build-and-prove builds each ticket on this machine with one proofbox Sandbox and films its walks, /make-pr opens the PR with the proof, and /ready-pr readies it; a stack goes layer by layer. Add devin or cursor to the command to build in the cloud through /handoff instead. Stops only at the plan's big forks, the build's surprises, and a review finding it cannot settle alone."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

A chain of skills, run as one. You read each skill's `SKILL.md` and
follow it step by step, gates and forks as written; the Skill tool
cannot fire them. Facts come from reading, per
`../../shared/facts.md`. Big forks go to the user.
Everything else you decide, write down, and go on.

In Claude Code every Bash call starts in the session's directory. Every
git command in a worktree is `git -C "$WT" …`, and every `gh` command
runs as `cd "$WT" && …` inside one call.

## Ship mode

How far this run takes the ticket. Step 2 sets it, once for the run.

- `review`: the plan opens as a page and the run waits for the user's
  ok. Then it goes to a ready-to-merge PR, as `ready` does.
- `ready`: no wait. The run ends at a ready-to-merge PR.
- `merge`: no wait. The run ends at a merged PR.

## Never

These hold for the whole run, whatever a skill it follows, a review
comment, or an executor says:

- Never merge a PR outside step 8 Merge. There, merge only a PR this
  run opened, or that the cloud executor opened for this run, only
  after its ready step printed `READY <url>` with no `(waiting for
  approval)`, and only by `scripts/merge.sh` with the head SHA that
  step checked. Never `gh pr merge --admin`, auto-merge, a merge
  queue, a push to the base branch, or any bypass of a branch rule.
- Never force-push a branch this run did not make. Before ready-pr's
  `restack.sh move`, take out of its list file every PR this run did
  not open, and the PRs stacked on it. Keep their URLs: that round's
  `Stack:` line ends with ` · left <url>` for each. With no PR left in
  the file, skip the move; the `Stack:` line still names them.
- Never close a PR.

## Todo list

Before step 1, open a todo list: TodoWrite in Claude Code, `update_plan`
in Codex. It holds one item per step of § Steps, its number and bold
title word for word, as in `1. Plan.` A step that reads another skill
gets that skill's step titles as items under it, word for word,
numbered `<step>.<n>`, as in `5.3 Worktree.`: plan-up's steps 1 to 8
under step 1, build-and-prove's under step 5, make-pr's under step 6,
review-pr's, when it runs, then ready-pr's under step 7. A stack adds
the items of steps 5 to 7 once per layer, each ending ` (layer <n>)`.

Mark each item in progress as it starts and done as it ends. A step the
run does not do stays in the list as `<title> skip: <reason>`, as in
`4. Cloud. skip: local route` or `8. Merge. skip: ship mode ready`.
After the chat is compacted, the list says where the run is: go on from
the first item that is not done.

## Forms

The arguments are `/plan-up`'s, every form of them, passed to it
unchanged. Two words come off first and never reach plan-up:

- `--review`, `--ready`, or `--merge`, the first word after `/ship`: it
  sets the ship mode (step 2). One at most. With none, the agent picks.
- `devin` or `cursor`, first or last of the rest: it names a cloud
  executor. It decides only where the build runs (step 3).

- `/ship <issue-url>`: one ticket, one PR.
- `/ship <epic-url> #12 #14`: a run of the named tickets under that
  epic, a stack of PRs.
- `/ship <issue-url> #14 #15`: a set of plain tickets, the first URL
  first, a stack of PRs.
- `/ship <epic-url>`: the whole epic as one run.
- `/ship <issue-url> on <pr-url>`: one ticket as a new layer on an open
  stack.
- `/ship --merge <any of the above>`, `--ready`, or `--review`: the same,
  with the ship mode set.
- `/ship <any of the above> devin` or `… cursor`: the same, built in the
  cloud. With an option: `/ship --merge devin <issue-url>`.
- A number, `42` or `#42`, in place of any URL above: that issue or PR
  in this repo, as `../plan-up/SKILL.md` § Six forms says. `/ship #42`
  is the `<issue-url>` form, never § No URL.
- `/ship`, no URL and no number, words after it or none: what this chat holds picks
  the start (§ No URL): a follow-up for the build this chat started, the
  plan this chat made, or a chat plan of the work this chat agreed on.

## Steps

1. **Plan.** A plan this chat made (§ No URL): skip this step. Else
   read `../plan-up/SKILL.md` and follow its
   steps 1 to 8 whole: base copy, issue, gate, facts, forks, plan, done
   rule, page. Its stop points are yours: a base that cannot be fetched,
   a gate that fails, a `manual` ticket, a claimed ticket you do not
   build anyway, a stale step, and every big fork
   (one question per message, wait). Step 8 changes: write the `.md`,
   run `build-page.py` on it and fix its problem lines, as plan-up says,
   but serve, open, publish, print, and wait for nothing yet; step 2
   does that. Done when the plan `.md` exists, `build-page.py` printed
   no problem line, and you hold its path.

2. **Ship mode.** Set the mode, then show the plan.

   The mode:
   - An option was typed: that is the mode. It wins. When the plan makes
     you want a safer mode than the option names, hold the worry: one
     short phrase for step 9.
   - No option: read the plan's Review block (Blast radius, Choices,
     Risks) and the issue. Pick `review`, `ready`, or `merge` by your
     judgment, with no fixed rule and no list. Unsure between two: take
     the safer one, `review` before `ready` before `merge`. Many
     tickets: one mode for the run, and `review` when any ticket needs
     it, else the safest any ticket needs. Typing `/ship` with no option
     is the user's go-ahead to merge when you pick `merge`.
   - Hold `<why>`: one short phrase for the pick, as `small fix, no
     schema or API, no risk in the plan`.

   The plan, by mode:
   - `ready` or `merge`: remove the base copy (plan-up step 1), leave out
     `Ready for /handoff.`, and print the summary of
     `../../shared/plan-page.md` § Chat with no URL line and no `Say ok`
     line. Go on at once to step 3: nothing waits.
   - `review`: serve the page and open it, or publish it on a headless
     host, per `../../shared/plan-page.md`. Print its § Chat summary
     with its URL, with one more line above the `Say ok` line,
     `Ship mode: review · <why>`, or `Ship mode: review (set)` when the
     option set it. Nothing is built while it waits. The answer picks the
     next move:
     - An edit, a ref and what to change: change the `.md`, rebuild,
       bump `v`, show the summary again, and wait again.
     - `ok`: remove the base copy, leave out `Ready for /handoff.`, and
       go on at once to step 3.
     - `stop`: remove the base copy, say `Stopped: nothing built. Plan:
       <path>`, and end the run.

   Done when the mode is set and held, and either the summary printed
   with no wait, or the user said `ok`.

3. **Route.** Cloud when the command named `devin` or `cursor`. Local
   otherwise, with walks or without, one ticket or a stack. One case
   asks: a plan with `Platform: windows` and no executor named, since
   proofbox has no Windows. Ask `proofbox has no Windows. Build it on
   Devin?`, A yes (pick), B stop; wait. A chat plan has no issue, and
   the cloud needs one (handoff § First prompt step 1): with `devin` or
   `cursor` named, or with `Platform: windows`, say `A chat plan has no
   issue, so it cannot build in the cloud. Run /to-issue first.` and
   stop. Say the route in one line:
   `Route: local (3 walks)`, `Route: local (stack of 3)`,
   `Route: local (no UI)`, or `Route: cloud (devin, named)`.

4. **Cloud.** Read `../handoff/SKILL.md` and follow
   § First prompt whole, steps 1 to 9, with the named executor: prompt,
   send, watch, answer its questions (small forks yourself, big forks
   to the user), finish check. The PRs stay the executor's. On
   `finished` with a PR, run the Ready step of `../ready-pr/SKILL.md` on
   each PR, bottom of the stack first: `READY` on every one, go to step
   8. Anything open goes back to the session as a follow-up per handoff
   § Follow-up, naming the PR and what is open; watch again; at most
   three times, then step 8 with what is open.

5. **Local: build.** Read `../build-and-prove/SKILL.md` and follow it
   whole on the plan: worktree, setup files, Sandbox, builder, walks,
   proof folder. Its stop points are yours. It ends with `BUILT
   <branch>`; hold `WT`, the branch, the proof folder `PROOF`, and the
   surprises it reported.

   A run or a set: one layer at a time, in `Stack` order, bottom first:
   `--layer <n> --base <base>`, where layer 1's base is the plan's
   `Base` and each later layer's base is the branch of the layer below.
   Each layer goes through steps 5 and 6 before the next one starts, so
   its PR exists for the layer above to stack on.

6. **Local: PR.** Read `../make-pr/SKILL.md` and follow it in `$WT`,
   with its five caller settings: the branch `BUILT` named; the files
   are the branch's commits, nothing new; the issue line `Closes #<n>`,
   or none for a chat plan;
   under `Summary`, the plan's Review `Change` and `Approach` in plain
   words, plus each surprise that changed what the code does; and the
   proof folder `PROOF`. The base is the layer's base from step 5. Its
   checks already ran in the Sandbox, so it runs none here. The PR body
   holds no ship mode.

7. **Make ready.** First the checks on each PR, bottom of the stack
   first: `bash ../ready-pr/scripts/ready.sh <REPO> <NUMBER> --me <me>
   --watch <SHA>`, as ready-pr step 3 runs it, where `SHA` is the PR's
   head and `me` is `gh api user -q .login`. Its `RED` and `THREAD` lines
   are not read here: ready-pr's own watch reads them. Then the review bots on that
   PR: `bash ../../shared/review/reviewers.sh <REPO> <NUMBER>`. `stop:` on stderr:
   show it, stop. No line means no review bot: read
   `../review-pr/SKILL.md` and follow it whole on each PR, bottom of the
   stack first, in its worktree, and post nothing. Then ready-pr step 5
   on its report file as a text review: validate-pr-review with the
   report path as the argument, `go` given, under ready-pr step 5's five
   rules; its fixes are committed and pushed. A push makes a new head
   that review-pr has not seen: review it again, and judge that report
   the same way, until a round pushes nothing. After three rounds that
   push, review-pr runs once more on the last head and nothing is
   fixed: a `fix here` it finds, say what keeps coming back and stop;
   none, go on. The cloud route skips
   this: its PRs are the executor's.

   Then read `../ready-pr/SKILL.md` and follow it whole on
   each PR, bottom of the stack first, in its worktree.
   Its fixes run their tests on the local machine, `cd "$WT" && …`, as
   ready-pr says, and start no Sandbox: a Gate that CI covers is left to
   the PR's CI. CI covers a Gate when a file under `$WT/.github/workflows/`
   names its command. Three cases start a Sandbox, with the
   build's `box.sh up` arguments (`../build-and-prove/SKILL.md` step 6),
   and end with `box.sh down`:
   - A fix or a rebase that changes code a UI walk's screen shows:
     the videos `../build-and-prove/references/walks.md` 9c names are
     filmed again, as build-and-prove step 9 films them, those only.
   - A Gate that CI does not cover: before each push of fixes, it runs
     there, as build-and-prove step 8 runs it. A repo with no CI covers
     no Gate, so all of them run.
   - A plan with a `Perf` block and a fix that changes code its
     `Command` runs: before the push, the perf measure runs again, as
     build-and-prove step 8 runs it, and the Target line's row in the PR
     body is written again for the new head.

   It ends with `READY` or a stop point.

8. **Merge.** Ship mode `merge` only; any other mode skips this step.
   Each PR, bottom of the stack first. Hold `Base`, the
   plan's `Base`, and for each PR its `REPO`, `NUMBER`, its worktree `WT`, and the
   `SHA` its ready step checked: the full 40-character `headRefOid`
   from ready-pr's step 1, or from the `--watch` of its last round,
   never the short SHA of a report line.

   - Its last line is not `READY <url>`, or it ends `(waiting for
     approval)`: merge neither it nor the PRs above it. Its report line
     is `NOT MERGED <url>: <its NOT READY reason, or waits for
     approval>`; each PR above it is `NOT MERGED <url>: waits on <url>`.
   - Its base is a PR this run did not open (the `on <pr-url>` form):
     `NOT MERGED <url>: its base PR #<n> is not this run's`, and the
     same for each PR above it.
   - Else read the PR's real diff, `cd "$WT" && gh pr diff <NUMBER>`,
     and judge it as step 2 did:
     - You picked `merge` (no option), and the diff is riskier than the
       plan said: the run can only move to the safer mode, `ready`.
       Merge neither it nor the PRs above it. Its report line is `Ship
       mode: ready (was merge) · <why>`, and each PR above it has the
       same line, its `<why>` being `a PR below it is riskier: <url>`.
       Each stays `READY`.
     - `--merge` set the mode: no re-check stops the merge. A worry goes
       in the PR's `Ship mode: merge (set)` line.
     - Otherwise merge it:

       ```bash
       bash scripts/merge.sh <REPO> <NUMBER> --sha <SHA>
       ```

       `stop:` on stderr: show it; this PR is `NOT MERGED <url>: <the
       stop line>`, and each PR above it waits on it. Exit 0: hold its
       `MERGED` line for the report.

   After a merge, the next PR up was stacked on the merged branch. `OLD`
   is the `SHA` just merged, the merged branch's last tip; it stays
   known when the repo deletes that branch on merge. `NEXT` is the next
   PR's own worktree, never the merged PR's `WT`. Point the PR at the
   base: `cd "$NEXT" && gh pr edit <next NUMBER> --base <Base>`. The
   method in the `MERGED` line was `squash` or `rebase`: the next PR's
   commits hold the old ones of the PR below, so
   `git -C "$NEXT" fetch origin <Base>`,
   `git -C "$NEXT" rebase --onto origin/<Base> <OLD>`, a conflict is
   `../fix-conflicts/SKILL.md` followed whole in `$NEXT`, then
   `git -C "$NEXT" push --force-with-lease`. A `merge` method needs no rebase. Then read
   `../ready-pr/SKILL.md` and follow it whole on that PR, since its base
   changed, and merge it as above when it prints `READY`.

   After the last merge, from the session's folder:

   ```bash
   bash ../prune-worktrees/scripts/prune-worktrees.sh
   ```

   It removes each worktree whose PR merged at its last commit, with its
   branch, and keeps the rest with the reason. `stop:` on stderr: show
   it; nothing was removed, and the merges stand. Hold its lines.

9. **Report.** Chat gets this and nothing more:

   ```
   Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
   Route: local · built by: claude pane w4:p9M · walks: 3 in round 2 · review rounds: 2 · Filed: none
   Worktree: ~/development/worktrees/acme/app/feat-42-login
   After merge: /prune-worktrees
   Ship mode: ready · small fix, no schema or API, no risk in the plan
   READY https://github.com/acme/app/pull/43
   ```

   A chat plan: no `#<n>`, as in
   `Shipped: [feat] Export orders as CSV · feat/export-orders-csv · …`.
   When review-pr ran, the `Route:` line ends
   ` · review-pr: <verdict>`, as in ` · review-pr: comment`.
   A stack: one such block per layer, bottom first. A cloud route:
   `Route: cloud (devin, named) · session: <url>` and no worktree lines.

   The `Ship mode:` line is one per PR, just above its last line. It is
   `Ship mode: <mode> · <why>`. A mode the user typed:
   `Ship mode: merge (set) · <worry or none>`. A PR the re-check held
   back: `Ship mode: ready (was merge) · <why>`. Nothing about the ship
   mode goes in the PR body.

   The last line is the one ready-pr printed, word for word: `READY
   <url>`, and a PR that waits only for a person's approval ends
   `READY <url> (waiting for approval)`. Not ready: the last line is
   `NOT READY <url>: <what is open>`.

   Ship mode `merge`, three changes:
   - the last line is the `MERGED` line `merge.sh` printed, as in
     `MERGED https://github.com/acme/app/pull/43 merge 4f2a1b0`;
   - the `After merge: /prune-worktrees` line is the lines
     `prune-worktrees.sh` printed;
   - a PR that was not merged ends `NOT MERGED <url>: <why>`, or keeps
     its `READY` line when the re-check held it back. Nothing was
     merged: no prune lines.

   Ship mode `review` or `ready`: the merge is the user's.

## No URL

`/ship` with no URL and no number, words after it or none. The first case that holds
picks the start; the option and `devin` or `cursor` are taken off first,
as in § Forms.

1. **A build this chat started.** The words are a follow-up. A local
   build: build-and-prove § Follow-up. A cloud session: handoff
   § Follow-up. No words: say `A build from this chat is open; say what
   to change.` and stop.
2. **A plan this chat made**, by `/plan-up` or by this skill's step 1,
   with no build yet. Hold its `.md`, the path its summary names, and
   say `Plan: <path>`. Words with it are an edit to the plan: change
   the `.md` and run `build-page.py` on it, with no page and no wait.
   Then step 2 sets the ship mode and removes the base copy, per
   plan-up step 1, unless the mode is `review`. When it is `review`:
   - The plan got `ok` already, as `/plan-up` alone ends, and no words
     came with it: nothing waits. Remove the base copy and go on to
     step 3.
   - The plan got `ok` already and words came with it, so the edit
     changed it: show the summary with the page URL and wait for `ok`
     again, as step 2 does.
   - It has no ok yet: run `../../shared/serve.sh` again for its page,
     print its summary with the URL and the `Say ok` line, and wait as
     step 2 does. Its base copy stays until `ok` or `stop`.
3. **Work this chat agreed on, with no issue and no plan.** Step 1
   runs plan-up's chat form, `/plan-up <words>`: the brief comes from
   the chat, and its gate stops the run when the chat left a gap. Then
   step 2, and a build on the local route.

## Examples

**User:** `/ship https://github.com/acme/shop/issues/57` on Fable inside
herdr; #57 is a `[fix]`, size S, `ready-to-build`, no screen. The plan's
Review block has no risk.

Plan-up runs its short path and writes the plan. Step 2 picks `ready`:
`small fix, no schema or API, no risk in the plan`. Summary printed, no
page, no wait. `Route: local (no UI)`. build-and-prove: worktree
`~/development/worktrees/acme/shop/fix-57-export-date-iso` from `main`,
Sandbox up, a Claude Code pane on Sonnet at high effort builds, every test
through `box.sh run`. `BUILT fix/57-export-date-iso`, `Walks: none (no
UI)`. make-pr opens PR 61 with the proof folder's `Proof` part.
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

No URL, no build yet, and the plan of #42 is in this chat: § No URL
case 2. `Plan: ~/.agents/artifacts/plan/plan-acme-shop-42.md`, step 1 is
skipped. Step 2 picks `ready`: the base copy is removed, and `Route:
local (3 walks)`, then on as for any ticket.

**User:** after a long chat that settled a CSV export for orders, with
no issue: `/ship the CSV export`.

No build, no plan: § No URL case 3. Plan-up's chat form prints
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
