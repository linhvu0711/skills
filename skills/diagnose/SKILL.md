---
name: diagnose
description: "Find the root cause of a bug, or the hot spot behind a slow thing, and stop there. No fix. When a real decision is open it runs the grill skill itself, then ends ready for /to-issue. Use for 'diagnose', 'debug this', 'why is X broken', 'why is X slow'."
disable-model-invocation: true
---

Read `references/method.md` and `references/categories.md` first. This file
is the order of operations.

You find what is true. You do not fix it. The output is a cause with a
`file:line`, or a hot spot with a number, written so a worker can pick it up
cold. The repo is left exactly as you found it.

## Brain and hands

You are the brain. Delegate work whose output is long and whose judgment is
small. Keep work whose output is short, or whose next step depends on reading
this one closely.

| Delegate | Keep |
|---|---|
| Read many files, callers, tests | Pick what to check next |
| Run the repro loop and report pass or fail | Read the evidence, decide the cause |
| Run `git bisect` with a script | Judge whether grill fits |
| Read a long log and pull the matching lines | Write expected, actual, repro, cause |
| Diff two envs, versions, or configs | |

In Claude Code, reading goes to Explore agents and running goes to Runner
agents. Both are cheap models behind a bridge; they carry out a brief, they
do not think for you. In Codex there are no sub-agents: use the read tools,
run the loop yourself, send long output to a file and read its tail.

A Runner brief holds four things, always:

1. The working directory.
2. The exact command, or the steps in order.
3. The verdict rule: an exit code, a string that must or must not appear,
   a number under a limit, or a bisect script. Runner judges by this rule
   and nothing else. When you cannot write the rule down, the work is not
   ready to delegate; run it yourself.
4. What to clean up: processes to kill, `git bisect reset`, temp files.

Runner answers with `VERDICT`, `EVIDENCE`, `REPRO`, `CLEANUP`, plus any extra
field you asked for (first bad commit, a measured number). It never edits
files and never touches git state beyond the bisect you asked for.

One short command with ten lines of output is yours; do not spawn an agent
for it. A loop that runs many times, a bisect, or a measurement repeated for
a stable number goes to Runner.

## Gate

One thing must be stated: the symptom, what the user sees. "The CSV dates
look wrong" passes. "Something is broken" does not. Ask for the symptom and
stop. Nothing else is required to start.

## Must know

Everything else you find first and ask second. One question per message,
with your best guess as the default, and only when the sources below said
nothing.

| Must know | Who finds it |
|---|---|
| The symptom | The user. The gate. |
| Expected instead | Code, spec, or test. The user only if those disagree or are silent. |
| A repro | You build one. Ask for a log, screenshot, or steps only if you cannot. |
| Where it works and where it does not | CI, git log, deploy log. The user if those do not say. |
| Since when | Git log, deploy log. The user if unknown. |
| Perf only: metric, baseline, target | You measure metric and baseline. The target is the user's. |

## Steps

1. **Gate.** Symptom stated: continue. Not stated: ask, stop.

2. **Place it.** Answer "where does it work, where does it not" from the
   sources in the table. That gives the category in `categories.md`. The
   category sets what you look at and what the exit is.

3. **Cheap path first.** Fetch the code on the symptom's path: the handler,
   the helper, the callers, the test. Read it. If the cause is visible,
   confirm it with one probe (a command, a test, a log line) and go to
   step 6. Most bugs end here.

4. **Hard path.** Build a repro that runs in seconds and fails on the exact
   symptom. Shrink it until nothing left is optional. Then halve, per
   `method.md`: in time, in the data path, or across environments. Cut until
   one line, one value, or one setting flips the symptom.

5. **Stuck.** Halving cannot cut further: write at most two hypotheses,
   each with the one check that kills it. Run the checks. A must-know row
   still empty after you looked and asked once: stop. The exit is a `spike`.

6. **Confirm.** One probe that flips the symptom: change the one thing,
   symptom gone; change it back, symptom returns. For perf, the number moves.

7. **Clean up.** Remove every debug line, every throwaway file, every
   changed setting. `git status` is what it was. Shared systems, live
   environments, and databases were read-only the whole time.

8. **Report.** In chat, in this shape:

   ```
   Expected: <one line>
   Actual: <one line>
   Repro: <command or numbered steps>
   Cause: <file:line, one sentence why>          (perf: Hot spot: <where>, <n> of <total> ms)
   Category: <from categories.md>
   Evidence: <the probe, and what it showed>
   ```

   When the category is local env, show the fix command in a code block and
   put it on the clipboard when `pbcopy` exists. The user runs it. You do
   not change their machine.

9. **Grill.** Test the report against § When grill fits. It fits: write
   the seed block in the same message, right after the report, and invoke
   the grill skill with the Skill tool. The seed is the report; the open
   decisions are the choices you found. After `Grill done.`, go to step 10.
   It does not fit: go to step 10.

10. **Hand off.** One last line:

   - `Ready for /to-issue.` After a grill, precede it with the settled
     decisions, one line each.
   - `Cause not found. Ready for /to-issue as a spike: <the open question>.`

## When grill fits

Run the grill skill when any one of these holds. Otherwise the report is
ready for /to-issue as it stands.

- More than one fix, and they differ in blast radius. Fix the helper and
  touch three callers, or patch one line.
- Expected is not settled. The user and the code disagree on what "right" is.
- The fix needs a new term or a new decision, something for `CONTEXT.md` or
  an ADR.

For perf: grill when the fix is a trade-off, like cache it or drop the
join.

The seed block, verbatim, filled in: `Invoke the grill skill with the Skill
tool. Seed: <the report>. Open decisions: <the list>. Then continue at
step 10.` The grill owns the interview and its docs. You wait for
`Grill done.`

## Secrets

Logs, env dumps, and configs carry secrets. Redact before they enter the
chat or an agent brief. Never paste a token, a key, or a signed URL.

## Examples

**User:** `/diagnose the CSV export shows dates as big numbers`

Gate passes. Explore fetches `src/orders/export.ts`, the date helper, its
callers, the export test. Reading shows `export.ts:57` writes the raw
`createdAt` and never calls `formatDate`, unlike line 49. One probe: the
existing test with an ISO assertion fails on that field. Report with
Category `Our code`, last line `Ready for /to-issue.`

**User:** `/diagnose orders page is slow`

Gate passes. Metric and baseline are not stated: measure the page, p95 is
1.2 s. Target is the user's: one question, default "under 300 ms". Then a
timer around the handler shows the orders query runs 41 times per page,
900 of the 1200 ms. Hot spot found. The fix is a trade-off, batch the query
or cache it. Report, then the seed block with open decision "batch or
cache", and invoke the grill skill. After `Grill done.`, list the settled
decision and end with `Ready for /to-issue.`

**User:** `/diagnose login fails on my machine`

Where does it work: CI is green, a teammate is fine. Category `Local env`.
Diff the env: `.env` lacks `AUTH_SECRET` that `.env.example` names. No code
issue. Fix command on the clipboard. Last line: `Ready for /to-issue` only
if the setup docs never mentioned the variable, as a `docs` ticket; else
nothing to file.

**User:** `/diagnose something is off`

Gate fails. Ask: "What do you see, and where?" Stop.
