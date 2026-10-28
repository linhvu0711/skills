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
3. **Run.**

   ```bash
   scripts/factory.sh start <owner/repo> --name "<name>" --thread <threadId> <n>...
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
5. **Show and start.** Run § Check at once. Its issue lines are the
   resolved set.

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
`claim` is `failed`, `waits: no label` for `unlabeled`, `yours` for
`task`, or `done`. Lead with `Joined: #a #b` when `joined` is not empty, and
with `Paused.` when `status` is `paused`. `"done": true`: § Done.

## Commands

A live run takes these, said in this thread. Each runs one
`factory.sh` call, posts one line, and changes nothing else.

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
- `add #n ...`, `remove #n ...`: `change <owner/repo> add|remove <n>...`.
  A removed issue's thread runs on.
- `restart #n`: `change <owner/repo> restart <n>`, then § Check.
- `ship-full #n`, `ship-full all`, `ship-ready #n`, `ship-ready all`:
  `change <owner/repo> ship full|ready <n>|all`. Only issues whose
  ticket thread has not started take it.
- `#n with <model> <effort>`, `all with <model> <effort>`, either part
  alone: `change <owner/repo> use <n>|all --model <model> --effort <effort>`.

## Resume

`/factory resume`, in any thread of the repo's project.

1. Rename this thread to `factory: resume` and hold its `threadId`,
   as § Start step 2.
2. `scripts/factory.sh resume <owner/repo> --thread <threadId>`. It
   prints the run's `name`, `old_task`, and `every`. Rename this thread
   to `factory: <name>`.
3. `old_task` set: `delete_scheduled_task` on it, so the run has one
   timer. Then pin and timer as § Start step 4, with
   `everyMs: <every * 60000>`, and § Check.

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
