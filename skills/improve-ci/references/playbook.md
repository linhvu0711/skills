# CI playbook

What a CI audit looks for and how each fix is judged. A **find** is one
thing that makes CI slow, lets it lie, or leaves it unsafe, with its
numbers and its proof.

## Rules

Every fix the report proposes keeps these three. A fix that breaks one
is no fix; a CI that breaks one today is a find.

1. **Full suite before main.** Every test runs before code reaches the
   default branch. Test selection only narrows the feedback on a PR.
2. **A failure stays red.** A check that needs a retry has a bug; the
   fix finds it. Retries, wider timeouts, and skipped tests are finds,
   never fixes.
3. **Checks only stay or grow.** Lint rules and required checks are
   kept or added. A tool swap lists, before the switch, every case the
   old tool caught that the new one misses.

## Targets and time limits

A **run part** is a job's waiting, setup, or work time. A **target** is
the time a run part, or the whole PR result, should reach after the fix.
Propose it from the measured p50 and p95 and the stack, with the reason
in one line, as `setup 1m50s → 20s: the packages come from a cache`.
Pick what the stack can reach on this repo; a native build or a large
test suite gets a target it can meet.

A **time limit** is the run time past which a job fails. Every job gets
one, from its own runs: just above its slowest normal run, as
`tests: p95 38s, slowest 44s, limit 1m`. It goes in the job as
`timeout-minutes`, which takes whole minutes, so round up. The limit
catches a real break, such as a lost cache, while a busy machine still
passes.

## Find kinds

Look for every kind below. Each find names its goal, its `path:line`
or its numbers, and its size.

### Speed

- **Waiting**: a job's wait p95 over 30s, or jobs queued behind each
  other.
- **Setup**: the biggest setup steps: an install with no cache, a cache
  that misses on PRs because main never saves it, a full clone where
  `filter: blob:none` or a shallow fetch would do, a toolchain that
  installs on every run.
- **Slowest job**: the job that ends the PR result. Split it, or give
  its tests more cores before more shards: match workers to cores,
  split a test file over 20s, balance shards from recorded file times,
  and give each shard its own throwaway database.
- **Shape**: a required job that waits on another with no need; small
  checks spread over jobs that could be one job listing every failure.
- **Old runs**: no `concurrency` group with `cancel-in-progress`, so a
  new push leaves the old run going.
- **Skip list**: PRs that change only files no check reads, such as
  docs. Build the skip list per repo from which checks read which files:
  a README that a repo check reads keeps that check. The skip goes
  inside the job, as a first step or a job `if:`, so a required check
  still reports. A workflow-level `paths` filter leaves a required
  check waiting forever.
- **Test selection**: on a PR, run only the tests the diff can reach,
  and list the inputs that rerun everything (a lockfile, a shared
  config). Rule 1 holds by what the repo can use. GitHub gives a merge
  queue to an org repo that is public, or private on Enterprise Cloud:
  there the queue runs the full suite. Any other repo: a draft PR runs
  the selected tests and a PR marked ready runs the full suite as a
  required check, with the branch up to date with main. A private org
  repo: propose the queue only when the user says the org has
  Enterprise Cloud; the grill asks.

### Honesty

- `continue-on-error: true`, `|| true`, `set +e` around a check, or a
  step that swallows its exit code.
- Retries: a retry action, a test runner's retry flag, a wider timeout
  added after a failure.
- Skipped tests: `.skip`, `xit`, `@skip`, a test filter in CI.
- A required check that no job reports, or a job no rule requires.
- **Flaky runs**: each re-run from the timing script whose `conclusion`
  is `success`, with the job that failed first. A re-run that failed
  again is a real failure, not a flaky run. Two or more flaky runs on
  one job is a big find.
- **Change detectors**: tests whose fixes in merged PRs changed only the
  test, never the code, such as a snapshot rewritten on every menu
  change. Tests of login, privacy, data migrations, or parallel work
  stay, whatever their history.

### Security

- An outside action pinned to a tag or a branch, as `@v4`, where a
  commit SHA would fix the code it runs.
- No `permissions` block, or one broader than the job needs, as
  `contents: write` on a job that only reads.

### Other

- **Broken workflow files**: a job that can never run, a `needs` on a
  missing job, an expression that never matches.
- **Work done twice**: two jobs that each install or build the same
  thing, where one job builds it and the others take its output.
- **Local hooks**: a pre-push hook that runs the same checks as CI, so a
  red shows before the push. A hook beats a line in `AGENTS.md`, since
  an agent skips a step it only reads.

## Issues

Each issue's Done when holds:

- the target, measured on at least 10 real runs after the change, as
  `setup p50 under 20s on 10 PR runs`;
- the time limit set on each job it touches;
- for a tool swap, the old and new tools run side by side first, and the
  issue lists what the new one misses;
- for test selection, a real change hidden from it on purpose turns CI
  red;
- at the top, any account, secret, or setting only the user can give.
