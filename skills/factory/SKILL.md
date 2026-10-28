---
name: factory
description: "Run a set of GitHub issues (a list, an epic, or a rule such as assigned to me) to closed from one pinned T3 Code thread: a timer checks every few minutes and starts one new thread for each free issue at a new stage, with /grill, /triage, /ship-ready, /ship-full, or /ready-pr. The user handles each thread. Also takes /factory check, /factory resume, and the commands of a live run."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

This thread is the factory. A script, `scripts/factory.sh`, owns the
run's state file and decides what to start; you start each thread with
T3's tools, keep the timer, and report. Every `factory.sh` call takes
the repo as `<owner/repo>`, from `gh repo view --json nameWithOwner`
in this thread's folder. Exit 1 from it: the last stderr line starts
with `stop:`; show it as is, and that command ends there.

## Never

The factory only starts threads (ADR 0013). Each thread it starts is
the user's from its first turn: leave it to them. So the factory starts
a thread once, and a thread that failed or ended with no new stage
waits for the user's `restart #n`. It writes nothing to GitHub: no
comment, no label, no close, no merge.

## Start

`/factory <set>`, in a T3 Code thread.

1. **Set.** Turn the user's words into issue numbers in this repo,
   once, per `../../shared/kickoff/target.md` § Resolving the target
   from the session, steps 1 and 2. A list stays a list; an epic is its
   number; a rule is a search, as `assigned to me` is
   `gh issue list --assignee @me --state open --json number`. Name the
   set in a few words: `#12 #14`, `epic #70 Order export`,
   `assigned to me`.
2. **Thread.** `t3_thread_update` with `action: rename`, no
   `threadId`, `title: factory: <name>`. Then `t3_thread_list` with
   `titleContains` that title, and hold the `threadId` of the thread
   with that exact title: no environment variable names this thread.
   Then `t3_environment_read`, and hold its `environmentId`: the board's
   thread links need it, and no `t3` command prints it.
3. **Run.**

   ```bash
   scripts/factory.sh start <owner/repo> --name "<name>" --thread <threadId> --env <environmentId> <n>...
   ```

   Its stops: `not inside T3 Code`, `a live run in <owner/repo>: <link>`
   (show the link: that thread is the factory), `<name> has no open
   issue`, and the checkout resolver's.
4. **Pin and timer.** `t3_thread_organize` with `action: pin`, no
   `threadId`. Then `schedule_task` with `prompt: /factory check`,
   `schedule: {type: interval, everyMs: 300000}`,
   `bindToCurrentThread: true`, `title: factory: <name>`. Hold its
   `scheduledTaskId`, and
   `scripts/factory.sh timer <owner/repo> --task <scheduledTaskId>`.
5. **Board, show, and start.** Serve the board from the run folder,
   `run` in step 3's JSON line:

   ```bash
   ../../shared/serve.sh <run> board.html
   ```

   Post `Board: <the URL it prints>`. A stop from it: post its line;
   the run goes on without the board. Then run § Check at once. Its
   issue lines are the resolved set.

## Check

`/factory check` (the timer's prompt), and `check now`.

```bash
scripts/factory.sh check <owner/repo>
```

Exit 1: post the `stop:` line in this thread as it is. One that says
`You must act` gets one more line: what the user can do, from its
reason (`gh auth login`, wait out the rate limit, check the network,
or open T3 Code). Nothing started.

Exit 0: one JSON line. For each item of `starts`, in order:

1. Follow `../../shared/kickoff/launch-t3.md` with the item as its
   line. Its stop lines end this item only.
2. Started: `scripts/factory.sh started <owner/repo> <number> <stage> <threadId> "<link>"`.
   Not started: `scripts/factory.sh started <owner/repo> <number> <stage> --failed "<the stop line>"`.

Then post one line per issue of `issues`, set order:

```
#<number> <title> · <stage> · <what happens>
```

`<what happens>` is the started thread's link and `/<skill>`, the
issue's `wait`, `blocked by #a #b`, its thread's link and
`thread_status`, `launch failed: <why>; say restart #<number>` when
`claim` is `failed`, `yours` for `task`, or `done`. An `unlabeled`
issue goes by its `answer`: none, `waits: your answer`, plus
` (proposed /<skill>)` when `proposal` names a skill; `skip`, `skipped`;
`task`, `yours`; `close`, `yours to close`; a skill, as any other stage.
The `ship` skill reads `/ship-ready`, or `/ship-full` when the user said
so for that issue or for all. Lead with `Joined: #a #b` when `joined` is
not empty, and with `Paused.` when `status` is `paused`. `"done": true`:
§ Done. `propose` not empty: § Propose, after these lines.

## Propose

The issues in `propose` are unlabeled and have no proposal yet. For each,
in order:

1. **Read.** `gh issue view <n> --json number,title,body,labels,comments`.
   It fails: the route is `unsure`, and the line is
   `#<n> · not sure: could not read #<n>: <gh's last stderr line>`.
2. **Route.** The first case that holds:
   1. A person must do it outside the repo, per
      `../../shared/issue-rules.md` § Task body: `task`.
   2. Something is broken or slow today, by the bug words in
      `../capture/SKILL.md` § Hard rules: `triage`.
   3. It passes `## Readiness gate` in `../../shared/issue-rules.md`,
      at any size by `../../shared/size.md`, XL too: `ship`.
   4. It has sub-issues: the check makes it an epic first, so it never
      comes here.
   5. Its row's `prs` holds an open PR, or its text links one:
      `ready-pr`.
   6. It is done, a duplicate, or out of date: `close`, with the proof:
      the PR, the issue, or the line that shows it.
   7. An idea that is not decided yet: `grill`.
   8. No case holds for sure: `unsure`, with the two best guesses and a
      reason for each.
3. **Record.** `scripts/factory.sh proposed <owner/repo> <n> <route>`.

Then post one list:

```
Proposals. Answer in one reply: all yes, #<n> <skill>, #<n> yes, or skip #<n>.
#<n> <title> · <what> · <reason> · "<quote>"
#<n> <title> · not sure: /<a> (<reason a>) or /<b> (<reason b>) · "<quote>"
```

`<what>` is `/<skill>`, `yours` for `task`, or `close it` for `close`.
`<quote>` is at most 12 words from the issue that back the reason.

## Commands

A live run takes these, said in this thread. Each runs one
`factory.sh` call, posts one line, and changes nothing else; `add` and
the answers then run § Check.

- `check now`: § Check.
- `check every <n> min`: `timer <owner/repo> --every <n>`, then
  `schedule_task` with the held `scheduledTaskId` (`task` in the
  timer line) and `schedule: {type: interval, everyMs: <n * 60000>}`.
- `pause`: `timer <owner/repo> pause`, then `schedule_task` with the
  task id and `enabled: false`. Running threads go on.
- `resume`: `timer <owner/repo> resume`, `schedule_task` with the task
  id and `enabled: true`, then § Check.
- `stop`: `timer <owner/repo> stop`, then `delete_scheduled_task` on
  the task id. The state file stays for `/factory resume`.
- `add #n ...`: `change <owner/repo> add <n>...`, then § Check, so a
  new unlabeled issue gets its proposal.
- `remove #n ...`: `change <owner/repo> remove <n>...`. A removed
  issue's thread runs on.
- `restart #n`: `change <owner/repo> restart <n>`, then § Check.
- Answers to § Propose: `all yes`, `all skip`, `#n yes`, `#n <skill>`,
  `skip #n`, many in one reply. One `change <owner/repo> answer <n>|all
  <word>` per part, the per-issue parts first, so `all` fills only the
  rest; then § Check. The words are `yes`, `skip`, `grill`, `triage`,
  `ready-pr`, `task`, and `close`; `ship-ready` or `ship-full` is
  `ship`, and each also runs `change <owner/repo> ship ready|full <n>`,
  so the issue ships the way the user said, whatever the run's default.
  A new answer reaches an issue whose thread started only after
  `restart #n`.
- `ship-full #n`, `ship-full all`, `ship-ready #n`, `ship-ready all`:
  `change <owner/repo> ship full|ready <n>|all`. Only issues whose
  ticket thread has not started take it.
- `#n with <model> <effort>`, `all with <model> <effort>`, either part
  alone: `change <owner/repo> use <n>|all --model <model> --effort <effort>`.

## Resume

`/factory resume`, in any thread of the repo's project.

1. Rename this thread to `factory: resume` and hold its `threadId`
   and the `environmentId`, as § Start step 2.
2. `scripts/factory.sh resume <owner/repo> --thread <threadId> --env <environmentId>`.
   It prints the run's `run`, `name`, `old_task`, and `every`, and puts
   the newest board page in the run folder. Rename this thread to
   `factory: <name>`.
3. `old_task` set: `delete_scheduled_task` on it, so the run has one
   timer. Then pin and timer as § Start step 4, with
   `everyMs: <every * 60000>`, then serve and post the board as § Start
   step 5, and § Check.

## Done

A check printed `"done": true`.

1. `delete_scheduled_task` on the timer's task.
2. Post one summary, one line per item of `summary`:

   ```
   #<number> <title> · <stages joined by →> · PR #<n> <state> · threads <links>
   ```

3. From the run's `path` (the main checkout), run
   `bash ../prune-worktrees/scripts/prune-worktrees.sh` and post its
   lines as they are, as ship-full does after its merges.
