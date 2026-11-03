# Local checks

The Gates and the perf measure of a plan with `UI: none`, which starts
no Sandbox (ADR 0019). SKILL.md step 8 reads this file, and so does
`/ship` step 7 after a review fix. Paths start at the skill folder.
`WT`, `BASE`, `PERF`, and `PROOF` are the ones SKILL.md holds. The
checks run on the head commit.

## Where each Gate runs

The Gates are the full suite, typecheck, lint, and build under the
plan's `Facts`, and every command the repo's `AGENTS.md` or `CLAUDE.md`
names as a check. Sort each one:

- **CI covers it**: a file under `$WT/.github/workflows/` names its
  command, in a job that runs on a pull request. A longer command does
  not cover it (`pnpm test:e2e` is not `pnpm test`), and neither does a
  comment. It runs on the PR, not here. Its line is
  `<command> · <short SHA> · not run: CI runs it (<workflow file>)`.
- **Every other Gate** runs here, all in one call, each command in
  single quotes:

  ```bash
  bash scripts/box.sh gates "$PROOF" --local "$WT" -- '<Gate>' '<Gate>'
  ```

  It runs them one at a time, never two at once, since two suites at
  once overload the local machine (ADR 0011). It writes
  `$PROOF/checks.txt` fresh, one line per command, ending `(local
  machine)`, as in `pnpm lint · 1a2b3c4 · 0 errors (local machine)`.
  Write no such line by hand. Exit 1 means a red Gate: stderr has
  `red: <command> · exit <code> · output <file>` for each (§ Red).

Then add the line of each Gate CI covers to `checks.txt`, and again
after each later `gates` call, since that call writes the file fresh.
No Gate left to run here: skip the call and write the CI lines alone.
A repo with no workflow file covers no Gate, so every Gate runs here.

## Missing tool

A `missing tool:` line on stderr, for a tool the local machine lacks:
say `<tool> is not installed on this machine; install it, then say
go.` and wait. On `go`, run the `gates` call again. A Gate that cannot
run here for another reason, such as one that needs Docker the machine
cannot start: its line is `<command> · <short SHA> · not run: <why>`,
added as the CI lines are, and `/make-pr` names it for CI.

## Perf

With a `PERF` block, after the Gates, with no other Gate running.
Measure per `../../shared/benchmark.md`. Put the base in a second
worktree:

```bash
git -C "$WT" worktree add --detach <temp folder> origin/<BASE>
```

Run the block's `Command` in turns, `cd <temp folder> && <Command>`
then `cd "$WT" && <Command>`, as many times each as the `Pass rule`
says. Write one line to `checks.txt`: `<Command> · <short SHA> ·
<metric>: <base median> → <head median> <unit>, median of <n> in
turns, spread <low> to <high> (local machine)`. A base median outside
the `Before` spread adds ` (issue Baseline: <Before>)` before `(local
machine)`, per `../../shared/pr-shape.md` § Proof. Then `git -C "$WT"
worktree remove --force <temp folder>`.

## Red

A red Gate, or a perf line whose head misses the `Pass rule`, is the
builder's: a follow-up per `render.sh local prompt` § Follow-up,
`# Check` naming the Gate and its output file, so the builder reads the
output and does not run the Gate again. Then run the checks again, from
§ Where each Gate runs.

Every Gate here is green, and every other line is `not run`: the
checks are done.
