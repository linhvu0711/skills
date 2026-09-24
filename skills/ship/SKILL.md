---
name: ship
description: "Take any target (one issue, a run of epic tickets, a set, a whole epic, or a new layer on a stack) from plan to ready-to-merge PRs in one run. /plan-up first, same arguments. Then: a single no-UI ticket is built in a worktree under ~/development/worktrees (a Devin CLI pane on SWE-2 when this session runs on Fable, else this session) and landed with /land-pr; a plan with UI walks, or any stack, is built by Devin cloud through /handoff-devin. Stops only at the plan's big forks and the build's surprises."
disable-model-invocation: true
---

A chain of skills, run as one. You read each skill's `SKILL.md` and
follow it step by step, gates and forks as written; the Skill tool
cannot fire them. Facts come from reading, per
`../../shared-skill-core/facts.md`. Big forks go to the user.
Everything else you decide, write down, and go on. Never merge.

In Claude Code every Bash call starts in the session's directory. Every
git command in a worktree is `git -C "$WT" …`, and every `gh` or test
command runs as `cd "$WT" && …` inside one call.

## Forms

The arguments are `/plan-up`'s, passed to it unchanged. Every form
plan-up takes, `/ship` takes; the form decides only where the build
runs (step 2).

- `/ship <issue-url>`: one ticket, one PR. Local when the plan has no
  UI walks; Devin cloud when it has.
- `/ship <epic-url> #12 #14`: a run of the named tickets under that
  epic, a stack of PRs. Devin cloud.
- `/ship <issue-url> #14 #15`: a set of plain tickets, the first URL
  first, a stack of PRs. Devin cloud.
- `/ship <epic-url>`: the whole epic as one run. Devin cloud.
- `/ship <issue-url> on <pr-url>`: one ticket as a new layer on an open
  stack. Devin cloud.
- `/ship <note>`, no URL: a follow-up for the pane or session this chat
  started (§ Follow-up).

## Steps

1. **Plan.** Read `../plan-up/SKILL.md` and follow its
   steps 1 to 8 whole: fresh tree, issue, gate, facts, forks, plan, done
   rule, page. Its stop points are yours: a tree that is not clean, a
   gate that fails, a `manual` ticket, a stale step, and every big fork
   (one question per message, wait). Two changes at step 8: build and
   open the page and print the summary, then go on at once, `ok` is
   given; and `Ready for /handoff-devin.` is not said. Done when the
   plan `.md` exists at the path the summary names and you hold it.

2. **Route.** Read the plan. Cloud when it has a `## Stack` block, or
   its Facts line `UI:` is anything but `none`. Local otherwise. Say it
   in one line: `Route: cloud (UI walks)`, `Route: cloud (stack of 3)`,
   or `Route: local (no UI, one ticket)`.

3. **Cloud.** Read `../handoff-devin/SKILL.md` and follow
   § First prompt whole, steps 1 to 9: prompt, send, watch, answer
   Devin's questions (small forks yourself, big forks to the user),
   finish check. The PRs stay Devin's. On `finished` with a PR, run the
   Ready step of `../land-pr/SKILL.md` on each PR, bottom
   of the stack first: `READY` on every one, go to step 8. Anything open
   goes back to the session as a follow-up per handoff-devin
   § Follow-up, naming the PR and what is open; watch again; at most
   three times, then step 8 with what is open.

4. **Local: worktree.** The branch name follows the rules block
   § Branch names: the issue's type (`feat` for a `[feat]`, `fix` for a
   `[fix]`, else the label or the title), its number, two to four words,
   as in `fix/133-uninstall-reverses-setup`. Then:

   ```bash
   bash ../../shared-skill-core/worktree.sh <main-checkout> <branch> --base <base>
   ```

   `stop:` on stderr: show it, stop. Hold `WT` from the `WORKTREE=` line.
   An open PR already on that branch (`gh pr list --head <branch>
   --state open --json url`): say so and go to step 7 with it.

5. **Local: prompt.** Follow handoff-devin § First prompt steps 2
   (facts) and 3 (labels) as written. Then assemble the file per
   `bash ../../shared-skill-core/handoff/render.sh local prompt`:
   the head lines with `Branch` and `Worktree`, the issue's `Task` and
   `Done when` verbatim, the plan's blocks, and the rules block from
   `render.sh local rules` pasted whole, unchanged, once. No `UI walks`,
   no `Videos`. Check per handoff-devin step 5 with those two dropped:
   every Proof row, every `file:line`, five label names, zero
   placeholders. Write it to
   `$HOME/.agents/artifacts/plan/prompt-<slug>.md`, the
   slug the plan used. Chat gets one line: `Prompt: <path> (<n> lines)`.

6. **Local: executor.** Your system prompt names the model you run on.

   **Fable** (`Fable`, `claude-fable-*`): the pane builds.
   - `HERDR_ENV` is not `1`: say `Not inside herdr. Open a herdr pane
     and run /ship there, or say "here" to build in this session.` and
     stop. `here` means the "Any other model" branch below.
   - Otherwise:

     ```bash
     bash scripts/pane.sh "$WT" <label> <prompt-path>
     ```

     The label is the first four words of the issue title in kebab
     case. `stop:` on stderr: show it, stop; a pane it left behind is
     named there. Exit 0: print its report line and hold `PANE` and
     `AGENT`. Then wait:

     ```bash
     ~/.claude/bin/herdr-wait <PANE> --timeout-sec 21600
     ```

     In Claude Code run it in the background; the tool wakes you when
     it ends. In Codex run it in the foreground with a long timeout.
     It returns on `idle`, `blocked`, or `done`. Read the tail,
     `herdr agent read <AGENT> --source visible --lines 80`, and sort:
     - The last message starts with `QUESTION`: sort it by the two
       tests in `../plan-up/SKILL.md` step 5, as
       handoff-devin step 8 does. **Small fork**: the plan, the issue,
       or the repo holds the answer; fetch the `file:line` with
       Explore, shape it per `render.sh local prompt` § Answer, write
       it to a file, and `~/.claude/bin/herdr-send <PANE> --file <file>
       --no-wait`; tell the user in one line what was asked and
       answered; wait again. **Big fork** (the list in plan-up step 5,
       plus a force push, a delete, another branch): quote the question
       in a fenced block, then one question to the user, two options at
       most, your pick first. The user answers `/ship <note>`. Stop.
     - The last line is `READY <url>` or `NOT READY <url>: …`: step 7.
     - A PR exists (`gh pr list --head <branch> --state open`) and the
       pane is idle with neither line: step 7.
     - No PR and no question: the pane stopped short. Show the last 20
       lines and stop.
     - `STATUS=timeout`: say how long it ran, the pane's last lines,
       and stop.

   **Any other model**: you build. Read the prompt file and follow it
   whole as its executor, in `$WT`: slices in order, tests first, one
   commit per slice, gates, the PR per its § The pull request, the size
   label. Its § Surprises are yours: stop and ask the user where it says
   stop and ask. It ends at § After the PR opens, which is step 7.

7. **Land.** Read `../land-pr/SKILL.md`.
   - The pane built: it already ran land-pr (rules § After the PR
     opens). Run only its Ready step on the PR. `READY`: step 8.
     `NOT READY`: shape a follow-up per `render.sh local prompt`
     § Follow-up, `# Changed` naming what is open and `# Check` naming
     the land-pr steps to run again, `herdr-send <PANE> --file <file>`
     (it waits), then Ready again. Three times, then step 8 with what
     is open.
   - You built, or step 4 found an open PR: follow land-pr whole from
     its first step, in `$WT`. It ends with `READY` or a stop point.

8. **Report.** Chat gets this and nothing more:

   ```
   Shipped: #42 login · feat/42-login · S: 4 files, 1 package, 96 lines
   Route: local · built by: devin pane w4:p9M · review rounds: 2 · Filed: none
   Worktree: ~/code/worktrees/app/feat-42-login
   Clean up after merge: git -C ~/code/app worktree remove ~/code/worktrees/app/feat-42-login
   READY https://github.com/acme/app/pull/43
   ```

   A cloud route: `Route: cloud (UI walks) · session: <url>` and no
   worktree lines. Not ready: the last line is
   `NOT READY <url>: <what is open>`. The merge is the user's.

## Follow-up

`/ship <note>` with no URL. A pane this chat started: sort the note by
plan-up step 5 (a big fork it leaves open goes to the user first), shape
it per `render.sh local prompt` § Answer when it answers a `QUESTION`,
else § Follow-up, `herdr-send <PANE> --file <file>`, then back to step 6's
sort. A Devin session this chat started: handoff-devin § Follow-up. This
chat started neither: say so and stop.

## Examples

**User:** `/ship https://github.com/acme/shop/issues/57` on Fable inside
herdr; #57 is a `[fix]`, size S, `handoff-ready`, no screen.

Plan-up runs its short path, page opens, summary printed, no wait.
`Route: local (no UI, one ticket)`. Worktree
`~/development/worktrees/shop/fix-57-export-date-iso` from `main`.
Prompt assembled, 240 lines, labels all present. `pane.sh` splits the
tab, Devin CLI on `swe-2-medium` reads the prompt. `herdr-wait` runs in
the background. Two hours later it returns `idle`; the tail ends with
`READY https://github.com/acme/shop/pull/61`. Ready step agrees.
Report printed. Stop.

**User:** `/ship https://github.com/acme/shop/issues/42` on Fable; the
plan has three UI walks and two videos.

`Route: cloud (UI walks)`. Handoff-devin § First prompt whole, Monitor on
the watch. Later `finished` with PR 44; finish check passes; Ready step
says `READY`. Report with `Route: cloud (UI walks) · session: <url>`.

**User:** `/ship https://github.com/acme/shop/issues/70 #71 #73` on
Sonnet.

A run is a stack: `Route: cloud (stack of 2)` whatever the UI. Same as
above, Ready step on PR 72 then PR 74.

**Watch tail** ends with `QUESTION` / `The plan names lib/format.ts:12
for the date helper, but that file only has formatCurrency…`

Explore finds `utils/time.ts:4` exports `toIsoDate`. Small fork.
`# Answer` written, `herdr-send … --no-wait`, one line to the user,
`herdr-wait` again.

**Watch tail** ends with `QUESTION` / `The users table has no team_id
column. Add a migration, or…`

Stored data: big fork. Question quoted, one question to the user, `A`
add the migration in this PR (pick, `migrations/0042.sql` shows the
shape), `B` stop and file it as its own ticket. Stop. The user says
`/ship A, add the migration`; it goes as § Answer.

**User:** `/ship https://github.com/acme/shop/issues/57` on Fable in a
plain terminal, no herdr.

Plan, route local, worktree, prompt. Then `Not inside herdr. Open a
herdr pane and run /ship there, or say "here" to build in this
session.` Stop. `here`: this session builds from the prompt file.

**User:** `/ship https://github.com/acme/shop/issues/61` where the issue
has no Done-when list.

Plan-up's gate fails: the question that closes it, `/grill` named.
Stop. Nothing is built.
