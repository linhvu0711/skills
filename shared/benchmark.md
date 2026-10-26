<!-- template: the benchmark checklist, one source. triage, plan-up, and build-and-prove read it; render.sh pastes it into the handoff rules under ## A perf plan. Keep it free of executor blocks and of links to other files: the include pastes it raw. Edit here only. -->
A speed number is trusted only when every check below holds. A number
that fails one is reported with the check it fails, never as a result.
A baseline measures one side alone, so `Alternate` and `Both sides
tuned` wait until old and new are compared; every other check holds for
it.

### Repeat

Run the measure at least five times per side. Report the median and the
spread, lowest to highest. Count the errors in each run: a run with an
error is not a timing. Each run does the same work, the same rows,
requests, or items. One run is allowed only as a ballpark the user
asked for, and it is labelled `1 run`.

### Alternate

When old and new are compared, they run in turns on one machine: old,
new, old, new. Never all old runs and then all new ones, since warm
caches and a busy machine then favor one side. A gap smaller than the
spread is `no measurable change`.

### Name the limit

Say what limits the number: CPU, disk, network, or a lock. Read it from
a profile or the system counters of a separate run, never from reading
the code. No limit named: the result is `inconclusive`.

### Both sides tuned

When old and new are compared, they use the same build mode, flags,
data, versions, pool sizes, and cache state, warm or cold as production
runs. A side left untuned
gives no winner.

### Physical limit

Check the number against what the hardware can do: bytes per second
against the disk or network bandwidth, and operations per second times
the cost of one against the cores. A result past the limit measures
something else: skipped work, a cache, an error. Work that took 10% of
the time can make the whole at most about 11% faster when it is
removed; a bigger gain means the measure is wrong.

### Share of the path

A measure of one part says its share of the end-to-end path the user
waits on, as in `orders query: 900 of 1200 ms`. A part that holds 5% of
the path can make it at most 5% faster. A micro result comes with one
end-to-end run on real data.

### Write it down

A trusted number carries the metric and unit, the median, the spread,
the run count, the command, the machine, and the limit, as in
`p95 of GET /orders: 1200 ms, median of 5, spread 1150 to 1260 ms, pnpm bench orders, M2 laptop, limit: a lock on orders`.
