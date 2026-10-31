---
name: orchestrate
description: "Run a set of GitHub issues (a list, an epic, or a rule such as assigned to me) to closed from one pinned T3 Code thread: a background watcher checks every few minutes and wakes the thread only when it must act, and it starts one new thread for each free issue at a new stage, with /grill, /triage, /ship, or /ready-pr. The user handles each thread. Also takes /orchestrate check, /orchestrate resume, and the commands of a live run."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

This thread is the orchestrator. A script, `scripts/orchestrate.sh`, owns the
run's state file, decides what to start, and runs the watcher: a
background loop that checks every few minutes with no chat turn and sends
this thread `/orchestrate check` only when you must act. You start each
thread with T3's tools, snooze this thread, and report. Every `orchestrate.sh` call takes
the repo as `<owner/repo>`, from `gh repo view --json nameWithOwner`
in this thread's folder. Exit 1 from it: the last stderr line starts
with `stop:`; show it as is, and that command ends there.

## Never

The orchestrator starts threads, and a thread gets one message only:
`/ready-pr <pr-url>` when that thread's PR has conflicts, which the
script's watcher sends (ADR 0013, ADR 0015). Each thread it starts is
the user's from its first turn: leave it to them. So the orchestrator starts
a thread once, and a thread that failed or ended with no new stage
waits for the user's `restart #n`. It writes nothing to GitHub: no
comment, no label, no close, no merge.

## Start

`/orchestrate <set>`, in a T3 Code thread.

1. **Set.** Turn the user's words into issue numbers in this repo,
   once, per `../../shared/kickoff/target.md` § Resolving the target
   from the session, steps 1 and 2. A list stays a list; an epic is its
   number; a rule is a search, as `assigned to me` is
   `gh issue list --assignee @me --state open --json number`. Name the
   set in a few words: `#12 #14`, `epic #70 Order export`,
   `assigned to me`.
2. **Thread.** `t3_thread_update` with `action: rename`, no
   `threadId`, `title: orchestrate: <name>`. Then `t3_thread_list` with
   `titleContains` that title, and hold the `threadId` of the thread
   with that exact title: no environment variable names this thread.
   Then `t3_environment_read`, and hold its `environmentId`: the board's
   thread links need it, and no `t3` command prints it.
3. **Run.**

   ```bash
   scripts/orchestrate.sh start <owner/repo> --name "<name>" --thread <threadId> --env <environmentId> <n>...
   ```

   Its stops: `not inside T3 Code`, `a live run in <owner/repo>: <link>`
   (show the link: that thread is the orchestrator), `<name> has no open
   issue`, and the checkout resolver's.
4. **Pin and watcher.** `t3_thread_organize` with `action: pin`, no
   `threadId`. Then `scripts/orchestrate.sh watch <owner/repo>`. A stop
   from it: post its line; the run has no checks until `resume`.
5. **Board, show, and start.** Serve the board from the run folder,
   `run` in step 3's JSON line:

   ```bash
   ../../shared/serve.sh <run> board.html
   ```

   Post `Board: <the URL it prints>`, and open that URL in the user's
   browser: `open "<url>"` on macOS, `xdg-open "<url>"` on Linux. A stop
   from serve.sh: post its line; the run goes on without the board. Then
   run § Check at once. Its issue lines are the resolved set. Then
   snooze this thread, per § Snooze.

## Check

`/orchestrate check` (the watcher's prompt), and `check now`.

```bash
scripts/orchestrate.sh check <owner/repo>
```

Exit 1: post the `stop:` line in this thread as it is. One that says
`You must act` gets one more line: what the user can do, from its
reason (`gh auth login`, wait out the rate limit, check the network,
or open T3 Code). Nothing started.

Exit 0: one JSON line. For each item of `starts`, in order:

1. Follow `../../shared/kickoff/launch-t3.md` with the item as its
   line. Its stop lines end this item only.
2. Started: `scripts/orchestrate.sh started <owner/repo> <number> <stage> <threadId> "<link>"`.
   Not started: `scripts/orchestrate.sh started <owner/repo> <number> <stage> --failed "<the stop line>"`.

Then post, by what ran the check:

- The watcher's prompt, `/orchestrate check`, and the line's `changed`
  is `false`: post nothing at all, not even a line that says nothing
  changed. Snooze, per § Snooze, and the turn ends there.
- The watcher's prompt, and `changed` is `true`: post the lines below
  only for the issues whose `changed` is `true`.
- Any other way in (start, resume, `check now`, `add`, `restart`, the
  answers): post the lines below for every issue.

One line per issue, set order:

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
The `ship` skill reads `/ship`, plus `--review`, `--ready`, or `--merge`
when the user set that ship mode for the issue or for all; with none,
the `/ship` thread picks the ship mode from its own plan. Lead with `Joined: #a #b` when `joined` is
not empty, and with `Paused.` when `status` is `paused`. `"done": true`:
§ Done. `propose` not empty: § Propose, after these lines.

## Snooze

A snoozed thread leaves the user's thread list until it wakes, so the
user sees the board, not this thread. At the end of each
`/orchestrate check` turn, before you post:

- The turn needs the user: a `stop:` line, a `propose` that is not
  empty, a start recorded `--failed`, or `"done": true`.
  `t3_thread_organize` with `action: unsnooze`, no `threadId`.
- Any other turn: `t3_thread_organize` with `action: snooze`, no
  `threadId`, and `snoozedUntil` 24 hours from now, in UTC ISO form.

§ Start and § Resume snooze the same way. The other commands leave the
snooze as it is. T3 still alerts on a turn in a snoozed thread today;
once it stops, the quiet turns are silent too.

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
3. **Size.** Route `ship`, or `unsure` with `ship` as a guess: size the
   work from the code, never from the title. Find the code the issue
   touches, with an Explore agent per `../../shared/facts.md` when it
   is more than a few files, and pick the row of `../../shared/size.md`
   whose every fact holds. Hold the size and its facts line, as
   `size.md` writes it: `S: one path, about 4 files`. Any other route
   takes no size.
4. **Record.** `scripts/orchestrate.sh proposed <owner/repo> <n> <route>`,
   plus `--size <size>` when step 3 gave one. It prints one JSON line:
   the `model` and `effort` the thread would get, from the same table
   the launch reads, or both `null` with a `why`.

Then post one list:

```
Proposals. Answer in one reply: all yes, #<n> <skill>, #<n> yes, or skip #<n>.
#<n> <title> · <what> · <size facts> · <model> <effort> · <reason> · "<quote>"
#<n> <title> · not sure: /<a> (<reason a>) or /<b> (<reason b>) · <size facts> · "<quote>"
```

`<what>` is `/<skill>`, `yours` for `task`, or `close it` for `close`.
`<size facts>` is step 3's facts line; no size, leave it out.
`<model> <effort>` is from step 4's line, as `opus medium`; `null`:
`no model: <why>`; `task` or `close`: leave it out. `<quote>` is at most
12 words from the issue that back the reason.

## Commands

A live run takes these, said in this thread. Each runs one
`orchestrate.sh` call, posts one line, and changes nothing else; `add` and
the answers then run § Check.

- `check now`: § Check.
- `check every <n> min`: `timer <owner/repo> --every <n>`. The watcher
  reads it before its next wait.
- `pause`: `timer <owner/repo> pause`, which ends the watcher. Running
  threads go on.
- `resume`: `timer <owner/repo> resume`, `watch <owner/repo>`, then
  § Check.
- `stop`: `timer <owner/repo> stop`, which ends the watcher. The state
  file stays for `/orchestrate resume`.
- `add #n ...`: `change <owner/repo> add <n>...`, then § Check, so a
  new unlabeled issue gets its proposal.
- `remove #n ...`: `change <owner/repo> remove <n>...`. A removed
  issue's thread runs on.
- `restart #n`: `change <owner/repo> restart <n>`, then § Check.
- Answers to § Propose: `all yes`, `all skip`, `#n yes`, `#n <skill>`,
  `skip #n`, many in one reply. One `change <owner/repo> answer <n>|all
  <word>` per part, the per-issue parts first, so `all` fills only the
  rest; then § Check. The words are `yes`, `skip`, `grill`, `triage`,
  `ready-pr`, `task`, and `close`; `ship`, `ship review`, `ship ready`,
  or `ship merge` is `ship`, and a ship mode also runs `change
  <owner/repo> ship review|ready|merge <n>`, so the issue ships the way
  the user said, whatever the run's default.
  A new answer reaches an issue whose thread started only after
  `restart #n`.
- `ship review #n`, `ship ready #n`, `ship merge #n`, or the same with
  `all` (also `ship --merge #n`): `change <owner/repo> ship
  review|ready|merge <n>|all`. Only issues whose ticket thread has not
  started take it. With no ship mode set, the `/ship` thread picks it.
- `#n with <model> <effort>`, `all with <model> <effort>`, either part
  alone: `change <owner/repo> use <n>|all --model <model> --effort <effort>`.
  It wins over the model and effort a proposal named.

## Resume

`/orchestrate resume`, in any thread of the repo's project.

1. Rename this thread to `orchestrate: resume` and hold its `threadId`
   and the `environmentId`, as § Start step 2.
2. `scripts/orchestrate.sh resume <owner/repo> --thread <threadId> --env <environmentId>`.
   It prints the run's `run`, `name`, `old_task`, and `every`, and puts
   the newest board page in the run folder. Rename this thread to
   `orchestrate: <name>`.
3. `old_task` set: the run is from before the watcher, and has a T3
   scheduled task; `delete_scheduled_task` on it. Then pin and watcher
   as § Start step 4, then serve, post, and open the board, § Check, and
   § Snooze, as § Start step 5.

## Done

A check printed `"done": true`.

1. Unsnooze this thread, per § Snooze. The watcher ends by itself, since
   the run is done.
2. Post one summary, one line per item of `summary`:

   ```
   #<number> <title> · <stages joined by →> · PR #<n> <state> · threads <links>
   ```

3. From the run's `path` (the main checkout), run
   `bash ../prune-worktrees/scripts/prune-worktrees.sh` and post its
   lines as they are, as `/ship` does after its merges.
4. Start the retro: follow `../../shared/kickoff/launch-t3.md` with the
   check's `retro` line, so one thread runs `/retro run <run>` on
   everything the run did. Post its link. A `stop:` line or an error
   there: post `Start it yourself: /retro run <run>`, with `run` from the
   check's line. The run is done either way.
