# Method

Two paths. Take the cheap one first. Take the hard one only when reading
did not settle it.

## Cheap path

Read the code on the symptom's path: handler, helper, callers, the test that
covers the place. Most bugs are visible from there: a missing call, a wrong
field, a branch that never runs. One probe confirms it. Build a loop only on
the hard path.

## Hard path

### Build a loop

A repro that runs in seconds, fails on the exact symptom, and runs without
a person watching. Any shape works: a failing test, a `curl`, a CLI call
with a fixture, a headless browser script, a replayed request, a throwaway
script. The loop is the product of this phase. Tighten it before you use it.

A bug that fails sometimes: raise the rate first. Loop it, load it, shrink
the timing window. Do not halve on a loop that passes half the time.

No loop can be built without something only the user has (a log, a
screenshot, a HAR, the steps they took): ask for it, one thing per message.
Still no loop: stop looking, exit as a `spike` (`SKILL.md` step 5).

### Shrink

Remove one thing at a time from the repro. Keep it out when the symptom
stays; put it back when the symptom goes. What is left is load-bearing, and
a small repro makes the next step cheap.

### Halve

Do not guess causes. Find the line between "works" and "broken" and cut
the space in half each step. Three axes:

- **Time.** Last good commit to now: `git bisect run <loop>`. Give it to
  Runner with the loop script as the verdict rule and `git bisect reset` as
  the cleanup; the output is long and the judgment is small.
- **Data path.** The value is right at the start and wrong at the end.
  Probe the middle. Then the middle of the bad half. Until one line flips it.
- **Environment.** Works in A, not in B. Diff A and B: lockfile, runtime
  version, env vars, config, build output, data. Change one difference at a
  time toward B until B breaks A.

Probe one variable per step. A debugger or a REPL before log lines. Log
lines carry a unique prefix so cleanup is one grep.

### Hypotheses, last

Only when halving cannot cut further. At most two. Each one states the
cause and the one check that would kill it. Run the checks. A hypothesis
without a killing check is a guess; do not write it.

## Perf

Measure with a profiler or timers, not log lines. Three numbers before anything else: the metric, the
baseline, the target. The metric and the baseline are yours to measure. The
target is the user's; ask once with a default.

The baseline is measured per `../../shared/benchmark.md`,
and passes every check in it that holds for one side before it is a
baseline. `Alternate` and `Both sides tuned` come in when Confirm
compares the number with the hot spot stubbed. A check it fails
goes in the report, with the number.

Then halve on the numbers. A profiler when one exists. Else timers around
the halves of the path. The hot spot is the part that holds most of the
time, with its share stated: "900 of 1200 ms". Stop there.

The fix the ticket names takes the first rung of this order that
reaches the target:

1. Don't do it: remove work whose result nobody uses.
2. Don't repeat it: keep a result and use it again.
3. Do less: fewer rows, calls, or bytes.
4. Do it later: when the result is needed, not before.
5. Do it in parallel: run work that waits on nothing else at the same time.
6. Do it cheaper: a faster way to do the same work.

## Confirm

The cause is confirmed when one change flips the symptom both ways: change
the one thing, symptom gone; change it back, symptom returns. For perf, the
number moves when the hot spot is stubbed. A cause that has not flipped the
symptom is still a hypothesis. Say so.

## Same mistake

A confirmed cause is one place a mistake was made, and the same mistake
is often made again: the same call skipped, the same field read raw, the
same check left out. Name the mistake as a pattern, not as the line.
Search where the cause lives for that pattern: `rg` for the names and
the shape, and a search by meaning when the mistake can wear other
names. Read each hit and keep only the ones that make the same mistake.
Each one kept is a `file:line` on the `Also at:` line. None kept:
`Also at: none found`, with the search that ran, so a reader can run it
again.

## Clean

Every probe, log line, throwaway file, and changed setting goes. The repo
and the machine are as you found them. Shared systems were read-only
throughout: no writes, no restarts, no config changes on anything other
people use.
