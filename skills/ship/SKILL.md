---
name: ship
description: "Take one issue, a run or set of tickets, a whole epic, a new stack layer, or work this chat agreed on, from plan to PRs in one run. The ship mode sets how far: review waits for your ok on the plan page, ready stops at ready-to-merge PRs, merge merges them. Add --review, --ready, or --merge to set it; with none, the agent picks. Add devin or cursor to build in the cloud."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

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

Before step 1, open a todo list with the todo tool your host gives:
TaskCreate and TaskUpdate, or TodoWrite, in Claude Code; `update_plan`
in Codex. No such tool: print the list in chat once, then one line as
each item starts, as `5.3 Worktree.` It holds one item per step of
§ Steps, its number and bold title word for word, as in `1. Plan.` A
step that reads another skill
gets that skill's step titles as items under it, word for word,
numbered `<step>.<n>`, as in `5.3 Worktree.`: plan-up's steps 1 to 9
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
unchanged. An issue or PR is named any way plan-up takes: a URL, a
number, or words that point at one. Two words come off first and never reach plan-up:

- `--review`, `--ready`, or `--merge`, the first word after `/ship`: it
  sets the ship mode (step 2). One at most. With none, the agent picks.
- `devin` or `cursor`, first or last of the rest: it names a cloud
  executor. It decides only where the build runs (step 3).

- `/ship <issue>`: one ticket, one PR.
- `/ship <epic> #12 #14`: a run of the named tickets under that
  epic, a stack of PRs.
- `/ship <issue> #14 #15`: a set of plain tickets, the first one
  first, a stack of PRs.
- `/ship <epic>`: the whole epic as one run.
- `/ship <issue> on <pr>`: one ticket as a new layer on an open
  stack.
- `/ship --merge <any of the above>`, `--ready`, or `--review`: the same,
  with the ship mode set.
- `/ship <any of the above> devin` or `… cursor`: the same, built in the
  cloud. With an option: `/ship --merge devin <issue>`.
- `/ship`, no issue named, words after it or none: what this chat holds picks
  the start (§ No issue): a follow-up for the build this chat started, the
  plan this chat made, or a chat plan of the work this chat agreed on.

## Steps

1. **Plan.** A plan this chat made (§ No issue): skip this step. Else
   read `../plan-up/SKILL.md` and follow its
   steps 1 to 9 whole: base copy, issue, gate, facts, forks, plan, done
   rule, check, page. Its stop points are yours: a base that cannot be fetched,
   a gate that fails, a `manual` ticket, a claimed ticket you do not
   build anyway, a stale step, and every big fork
   (one question per message, wait), the plan check's questions
   included. Step 9 changes: run `build-page.py` on the `.md` and fix
   its problem lines, as plan-up says, but serve, open, publish, print,
   and wait for nothing yet; step 2 does that.

   A worktree or branch an earlier ticket left goes only through
   `bash ../prune-worktrees/scripts/prune-worktrees.sh`, run from the
   session's folder. It removes a clean worktree whose PR merged at its
   last commit, and also one with no PR whose tip is in the default
   branch, as a worktree another ticket just made is. So run it only
   when no other ticket is building in this repo; when you cannot tell,
   leave the old worktree for step 8 or the end of the run. One it keeps
   stays, with its reason in the report. Never remove one by hand, with
   `git worktree remove` or `git branch -D`.

   Done when the plan `.md` exists, `build-page.py` printed no problem
   line, and you hold its path.

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
     is the user's go-ahead to merge when you pick `merge`. A plan whose
     `Plan check:` line starts `Plan check: failed`: `review`, since no
     second model read it.
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
   checks are in `checks.txt`, run in the Sandbox, on the local
   machine, or left to CI, so it runs none here. The PR body
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
   ready-pr says, and start no Sandbox. Before each push of ready-pr
   step 5, of fixes or of a rebase alone, and after its rebase when it
   rebased, follow `../build-and-prove/SKILL.md` § Follow-up in `$WT`
   with the change `review fixes are committed`, or `rebased on <BASE>`
   for a rebase alone, and the layer's `--layer` and `--base`
   from step 5 for a layer of a stack; its stop points are yours. After the
   push, follow `../make-pr/SKILL.md` in `$WT` with step 6's caller
   settings: it updates the PR from `PROOF`. make-pr comes after the
   push, since its own push stops on a rebased head.

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
   - Its base is a PR this run did not open (the `on <pr>` form):
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
   Route: local · built by: session · walks: 3 in round 2 · review rounds: 2 · Filed: none
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

## No issue

`/ship` with no issue named, words after it or none. You judge
whether the words name an issue or point at work in this chat. The first case that holds
picks the start; the option and `devin` or `cursor` are taken off first,
as in § Forms.

1. **A build this chat started.** The words are a follow-up. A local
   build: follow `../build-and-prove/SKILL.md` § Follow-up in its
   worktree with the words as the change, and `--layer` and `--base`
   for a layer of a stack; its stop points are yours. Then go on from
   step 6: make-pr opens the PR, or updates the open one from `PROOF`.
   A cloud session: handoff § Follow-up. No words: say `A build from
   this chat is open; say what to change.` and stop.
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

Sample runs of each form and ship mode: `references/examples.md`.
Read it when a step here is unclear.
