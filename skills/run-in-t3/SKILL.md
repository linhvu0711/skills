---
name: run-in-t3
description: "Start the skill each named issue needs in a new T3 Code thread: the shared Router picks /triage, /grill, /ready-pr, /complete-task, or /ship and its effort from the skill the user names, or each issue's labels and PRs. Issues are named by number, URL, or words. An unlabeled issue gets a proposal and waits for a yes, written as a label. Stops once the threads run. Use when the user asks to start issues in new T3 Code threads."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

The Router, `../../shared/route/router.sh`, reads one issue and gives the step its thread runs and the effort, or no step and the reason; its header lists its rows. `scripts/kickoff.sh` reads the issues, asks the Router for each, and builds each thread's line; you group the issues and start the threads with T3's tools. Every `kickoff.sh` call takes the repo as `<owner/repo>`. Exit 1, 2, or 64 from it: show its `stop:` lines as they are, and stop. Nothing started.

## Steps

1. **Target.** Find the repo and the issues per `../../shared/route/target.md` § Resolving the target from the session. Hold the user's words that group the issues, a skill they name for an issue ("triage it" is `triage`, "grill it" `grill`, "ready the PR" `ready-pr`), and any model, effort, ship mode ("review the plan first" is `review`, "ship it" `ready`, "ship and merge" `merge`), or thread name they give.
2. **Route.**

   ```bash
   scripts/kickoff.sh route <owner/repo> [--model M] [--effort E] [--pick <n>=<skill>]... <n>...
   ```

   `--pick` is a skill the user named for that issue: it beats the labels.

   It prints one JSON line per issue: `number`, `title`, `parent`, and the Router's `stage`, `step`, `stop`, `model`, `model_from`, `effort`, `effort_from`, `reason`, and `pr`. Hold them.
3. **Propose.** Each line at stage `unlabeled` and with no step: read the issue (`gh issue view <n> --repo <owner/repo> --json number,title,body,labels,comments`) and guess its route and size per `../../shared/route/propose.md`. Run `route` again for those issues with `--answer <n>=<route>` and, for `ship`, `--size <n>=<size>`, for the model and effort the thread would get. Post one list, and wait. Nothing starts before the answer:

   ```
   Proposals. Answer in one reply: all yes, #n <skill>, #n yes, or skip #n.
   #<n> <title> · <what> · <size line> · <model> <effort> · <reason> · "<quote>"
   #<n> <title> · not sure: /<a> (<reason a>) or /<b> (<reason b>) · <size line> · "<quote>"
   ```

   `<what>` is `/<skill>`, `yours` for `task`, `close it` for `close`, or `Cut it with /file-epic` for `xxl`. `<size line>` is the estimate line from `propose.md` § Size; no size, leave it out. `<model> <effort>` is from the `route` line; leave it out for `task`, `close`, and `xxl`. `<quote>` is at most 12 words from the issue that back the reason.

   Each yes, or a skill named for an issue: write it, and post the line it prints:

   ```bash
   scripts/kickoff.sh label <owner/repo> <n> <word> [--size <size>]
   ```

   A `#n ship` with no size: size it per `propose.md` § Size first. Then run `route` again with the same `--answer` and `--size` for the answered issues, and pass them to `thread` in step 5 as well, so an issue whose label was not written still routes. A skip, `close`, `task`, or `xxl` answer gets no thread: its report line is `skipped`, `close it`, `a task for you`, or `XXL, cut it with /file-epic`.
4. **Group.** Put the issues whose line has a step and no `stop` into threads, by the user's words. Only `/ship` threads take several issues; every other step gets one thread per issue. An epic's line has no step: the lines after it are its tickets. "The whole epic" is one `ship` thread named by the epic alone when each ticket line has step `ship` or stage `task`, `waiting`, or `done`. When any other ticket gets no thread, name the tickets with step `ship` instead: they go as a run of that epic.
   - No grouping words, and every issue routes to `ship`: one thread for all of them.
   - No grouping words, and the issues route to different steps: ask one question that lists each issue and its step, and wait. Nothing starts before the answer.
   - Words that put issues of different steps in one thread, as "12 and 15 together" for a ticket and a bug: ask the same way, and wait.
   - "The rest one thread each" and the like: each issue no group names gets its own thread.

   An issue with no step, or with `stop` true, gets no thread: its report line gives the line's `reason`.
5. **Lines.** For each thread, before any launch:

   ```bash
   scripts/kickoff.sh thread <owner/repo> [--heading H] [--mode M] [--model M] [--effort E] [--pick <n>=<skill>]... [--answer <n>=<word>]... [--size <n>=<size>]... [--on <pr-n>] <step> <n>...
   ```

   A `ship` thread names all its tickets, or one epic alone; `--on` names the PR a ticket stacks on. Pass the `--pick`, `--answer`, and `--size` of the issues the thread counts: its own, or the epic's tickets. Pass `--mode` only to a `ship` thread. Hold each JSON line: `step`, `model`, `model_from`, `effort`, `effort_from`, `reason`, `path`, `slash_command`, `message`, `thread_title`, and `project`. A stop on any line starts no thread at all.
6. **Launch.** Follow `../../shared/launch/launch-t3.md` steps 1 and 2 for every line first, then step 3 for each line. A stop in steps 1 or 2 starts no thread at all. Hold each thread's `link`.
7. **Report.** One line per thread, then one line per issue with no thread, and stop:

   ```
   <thread_title> → <link> · <slash_command> · effort <effort> (<effort_from>) · <reason>
   #<n> <title> · no thread, <why>
   ```

   `<link>` is the thread's `link` from step 6, as it is. Each command now talks to the user in its own thread. Do not watch it, read its plan, or run `/dispatch` from here.

## Examples

**User:** `/run-in-t3 https://github.com/acme/shop/issues/42`, in a T3 chat; #42 is `size/S`.

`kickoff.sh route acme/shop 42` gives step `ship`, effort `medium`. `kickoff.sh thread acme/shop ship 42` gives `message` `/ship #42`. `opus` maps to `claude-opus-5-5`, and the project with that `workspaceRoot` is found. One thread launch. Say `#42 Export orders as CSV → [#42 Export orders as CSV](t3-thread://v1/…) · /ship · effort medium (default) · size S`. Stop.

**User:** `/run-in-t3 12 14 15, the rest one thread each`; #12 is `size/S`, #14 `size/M`, #15 `bug`.

`route` gives #12 and #14 `ship`, #15 `triage`. The words group the two tickets and give #15 its own thread: `thread acme/shop ship 12 14` gives `message` `/ship #12 #14`, effort `high`, reason `size M of 2 tickets`; `thread acme/shop triage 15` gives `/triage #15` at `high`. With no words after `12 14 15`, ask first: two steps.

**User:** `/run-in-t3 44, triage it`; #44 is `size/S`.

`route acme/shop --pick 44=triage 44` gives step `triage`, effort `high`, reason `you picked /triage`. `thread acme/shop --pick 44=triage triage 44` gives `/triage #44`. With no pick, the size label gives `/ship`.

**User:** `/run-in-t3 16`; #16 has no label, and its body says the export button does nothing.

`route` gives stage `unlabeled`. The body names something broken today, so the guess is `triage`. `route acme/shop --answer 16=triage 16` gives effort `high`. Post `Proposals. …` and `#16 Export button · /triage · opus high · broken today · "clicking Export does nothing"`, and wait. The user says `all yes`: `kickoff.sh label acme/shop 16 triage` prints `labeled #16 bug`, and `route` now gives step `triage` from the label.

**User:** `/run-in-t3 42 with sonnet xhigh`, in a session about acme/shop.

Pass `--model sonnet --effort xhigh` to `route` and to `thread`. The step still comes from the Router. `sonnet` maps to the first `claude-sonnet-` id.

**User:** `/run-in-t3 42`, in a terminal outside T3 Code.

The script says `stop: not inside T3 Code`. Show it. Stop. Nothing started.

**User:** `/run-in-t3 42` for a repo whose checkout is not a T3 project yet.

`thread` adds it and says `project` `added`. Step 6 finds the new project.

**User:** `what would /run-in-t3 do for issue 70?`

Run only `kickoff.sh route`, which writes nothing, and answer from its line: the step, the effort, and the reason. Run no `thread` and start nothing.
