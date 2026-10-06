---
name: ship
description: "Take any target (one issue, a run of epic tickets, a set, a whole epic, or a new layer on a stack) from plan to ready-to-merge PRs in one run. /plan-up first, same arguments. With no URL, it starts from the plan /plan-up already made in this chat, or plans the work this chat agreed on with no issue. Then, by default, /build-and-prove builds each ticket on this machine with one proofbox Sandbox and films its walks, /make-pr opens the PR with the proof, and /ready-pr readies it; a stack goes layer by layer. Add devin or cursor to the command to build in the cloud through /handoff instead. Stops only at the plan's big forks and the build's surprises."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

A chain of skills, run as one. You read each skill's `SKILL.md` and
follow it step by step, gates and forks as written; the Skill tool
cannot fire them. Facts come from reading, per
`../../shared-skill-core/facts.md`. Big forks go to the user.
Everything else you decide, write down, and go on. Never merge.

In Claude Code every Bash call starts in the session's directory. Every
git command in a worktree is `git -C "$WT" …`, and every `gh` command
runs as `cd "$WT" && …` inside one call.

## Forms

The arguments are `/plan-up`'s, every form of them, passed to it
unchanged. The word `devin` or `cursor`, first or last, names a cloud
executor; take it off before the rest goes to plan-up. It decides only
where the build runs (step 2).

- `/ship <issue-url>`: one ticket, one PR.
- `/ship <epic-url> #12 #14`: a run of the named tickets under that
  epic, a stack of PRs.
- `/ship <issue-url> #14 #15`: a set of plain tickets, the first URL
  first, a stack of PRs.
- `/ship <epic-url>`: the whole epic as one run.
- `/ship <issue-url> on <pr-url>`: one ticket as a new layer on an open
  stack.
- `/ship <any of the above> devin` or `… cursor`: the same, built in the
  cloud.
- `/ship`, no URL, words after it or none: what this chat holds picks
  the start (§ No URL): a follow-up for the build this chat started, the
  plan this chat made, or a chat plan of the work this chat agreed on.

## Steps

1. **Plan.** A plan this chat made (§ No URL): skip this step. Else
   read `../plan-up/SKILL.md` and follow its
   steps 1 to 8 whole: base copy, issue, gate, facts, forks, plan, done
   rule, page. Its stop points are yours: a base that cannot be fetched,
   a gate that fails, a `manual` ticket, a claimed ticket you do not
   build anyway, a stale step, and every big fork
   (one question per message, wait). Two changes at step 8: build and
   open the page, print the summary, and go on at once as if `ok` were
   given: the base copy is removed, `Ready for /handoff.` is left
   out. Done when the plan
   `.md` exists at the path the summary names and you hold it.

2. **Route.** Cloud when the command named `devin` or `cursor`. Local
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

3. **Cloud.** Read `../handoff/SKILL.md` and follow
   § First prompt whole, steps 1 to 9, with the named executor: prompt,
   send, watch, answer its questions (small forks yourself, big forks
   to the user), finish check. The PRs stay the executor's. On
   `finished` with a PR, run the Ready step of `../ready-pr/SKILL.md` on
   each PR, bottom of the stack first: `READY` on every one, go to step
   7. Anything open goes back to the session as a follow-up per handoff
   § Follow-up, naming the PR and what is open; watch again; at most
   three times, then step 7 with what is open.

4. **Local: build.** Read `../build-and-prove/SKILL.md` and follow it
   whole on the plan: worktree, setup files, Sandbox, builder, walks,
   proof folder. Its stop points are yours. It ends with `BUILT
   <branch>`; hold `WT`, the branch, the proof folder `PROOF`, and the
   surprises it reported.

   A run or a set: one layer at a time, in `Stack` order, bottom first:
   `--layer <n> --base <base>`, where layer 1's base is the plan's
   `Base` and each later layer's base is the branch of the layer below.
   Each layer goes through steps 4 and 5 before the next one starts, so
   its PR exists for the layer above to stack on.

5. **Local: PR.** Read `../make-pr/SKILL.md` and follow it in `$WT`,
   with its five caller settings: the branch `BUILT` named; the files
   are the branch's commits, nothing new; the issue line `Closes #<n>`,
   or none for a chat plan;
   under `Summary`, the plan's Review `Change` and `Approach` in plain
   words, plus each surprise that changed what the code does; and the
   proof folder `PROOF`. The base is the layer's base from step 4. Its
   checks already ran in the Sandbox, so it runs none here.

6. **Make ready.** Read `../ready-pr/SKILL.md` and follow it whole on
   each PR, bottom of the stack first, in its worktree. Its fixes run
   their tests in a Sandbox too, never on this machine: the build ended
   with `box.sh down`, so the first fix runs `box.sh up` again with the
   build's arguments (`../build-and-prove/SKILL.md` step 5), each test
   goes through `box.sh run`, and `box.sh down` follows ready-pr's last
   round. It ends with `READY` or a stop point.

7. **Report.** Chat gets this and nothing more:

   ```
   Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
   Route: local · built by: claude pane w4:p9M · walks: 3 in round 2 · review rounds: 2 · Filed: none
   Worktree: ~/development/worktrees/acme/app/feat-42-login
   After merge: /prune-worktrees
   READY https://github.com/acme/app/pull/43
   ```

   A chat plan: no `#<n>`, as in
   `Shipped: [feat] Export orders as CSV · feat/export-orders-csv · …`.
   A stack: one such block per layer, bottom first. A cloud route:
   `Route: cloud (devin, named) · session: <url>` and no worktree lines.
   The `READY` line is the one ready-pr printed, word for word: a PR
   that waits only for a person's approval ends
   `READY <url> (waiting for approval)`. Not ready: the last line is
   `NOT READY <url>: <what is open>`. The merge is the user's.

## No URL

`/ship` with no URL, words after it or none. The first case that holds
picks the start; `devin` or `cursor` is taken off first, as in § Forms.

1. **A build this chat started.** The words are a follow-up. A local
   build: build-and-prove § Follow-up. A cloud session: handoff
   § Follow-up. No words: say `A build from this chat is open; say what
   to change.` and stop.
2. **A plan this chat made**, by `/plan-up` or by this skill's step 1,
   with no build yet. Hold its `.md`, the path its summary names, and
   say `Plan: <path>`. Its base copy still there (no `ok` was given):
   remove it, per plan-up step 1. Words with it are an edit to the plan:
   make it per plan-up step 8 (change the `.md`, rebuild, bump `v`),
   with no wait. Then step 2.
3. **Work this chat agreed on, with no issue and no plan.** Step 1
   runs plan-up's chat form, `/plan-up <words>`: the brief comes from
   the chat, and its gate stops the run when the chat left a gap. Then
   step 2, on the local route.

## Examples

**User:** `/ship https://github.com/acme/shop/issues/57` on Fable inside
herdr; #57 is a `[fix]`, size S, `handoff-ready`, no screen.

Plan-up runs its short path, page opens, summary printed, no wait.
`Route: local (no UI)`. build-and-prove: worktree
`~/development/worktrees/acme/shop/fix-57-export-date-iso` from `main`,
Sandbox up, a Claude Code pane on Sonnet at high effort builds, every test
through `box.sh run`. `BUILT fix/57-export-date-iso`, `Walks: none (no
UI)`. make-pr opens PR 61 with the proof folder's `Proof` part.
ready-pr: `READY https://github.com/acme/shop/pull/61`. Report.

**User:** `/ship https://github.com/acme/shop/issues/42` on Sonnet; the
plan has three UI walks and two videos.

`Route: local (3 walks)`. build-and-prove builds in this session, the
walker films two videos, round 2 passes. make-pr attaches the
screenshots and videos. ready-pr readies PR 44. Report.

**User:** `/ship https://github.com/acme/shop/issues/70 #71 #73`.

`Route: local (stack of 2)`. Layer 1: build-and-prove `--layer 1 --base
main`, make-pr opens PR 72 on `main`. Layer 2: `--layer 2 --base
feat/71-team-entity`, make-pr opens PR 74 on that branch. ready-pr on
PR 72, then PR 74. Two report blocks.

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
case 2. `Plan: ~/.agents/artifacts/plan/plan-acme-shop-42.md`, the base
copy is removed, step 1 is skipped. `Route: local (3 walks)`, then on
as for any ticket.

**User:** after a long chat that settled a CSV export for orders, with
no issue: `/ship the CSV export`.

No build, no plan: § No URL case 3. Plan-up's chat form prints
`Brief: [feat] Export orders as CSV · size/M` with its Done-when lines,
the gate passes, the plan is
`plan-acme-shop-chat-export-orders-csv.md`, and the run goes on with no
wait. `Route: local (2 walks)`. Branch `feat/export-orders-csv`; the PR
has no `Closes` line. Report.

**User:** `/ship devin` after the same chat.

Case 3 again, then Route: `A chat plan has no issue, so it cannot
build in the cloud. Run /to-issue first.` Stop.

**User:** `/ship https://github.com/acme/shop/issues/61` where the issue
has no Done-when list.

Plan-up's gate fails: the question that closes it, `/grill` named.
Stop. Nothing is built.
