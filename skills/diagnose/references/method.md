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
Still no loop: stop, exit as a `spike`.

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

Then halve on the numbers. A profiler when one exists. Else timers around
the halves of the path. The hot spot is the part that holds most of the
time, with its share stated: "900 of 1200 ms". Stop there.

## Confirm

The cause is confirmed when one change flips the symptom both ways: change
the one thing, symptom gone; change it back, symptom returns. For perf, the
number moves when the hot spot is stubbed. A cause that has not flipped the
symptom is still a hypothesis. Say so.

## Clean

Every probe, log line, throwaway file, and changed setting goes. The repo
and the machine are as you found them. Shared systems were read-only
throughout: no writes, no restarts, no config changes on anything other
people use.
