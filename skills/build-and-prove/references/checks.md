# Step 6: Local checks

Step 6 of SKILL.md, for every plan, with walks or without. Paths start
at the skill folder. `WT`, `BASE`, `PERF`, and `PROOF` are the ones
SKILL.md holds. The checks run on the branch's head, after the push,
in round 1 and in each round after code changed. In Claude Code run
them in the background, so they run while the Proof agent films; the
tool wakes you when they end.

Each result is one line in `$PROOF/checks.txt`, in place of the line
an earlier round wrote for the same command.

## Where each Gate runs

The Gates are the full suite, typecheck, lint, and build under the
plan's `Facts`, and every command the repo's `AGENTS.md` or `CLAUDE.md`
names as a check. Sort each one:

- **CI covers it**: a workflow under `$WT/.github/workflows/` that runs
  on pull requests has a step that runs that exact command. A longer
  command does not cover it (`pnpm test:e2e` is not `pnpm test`), and
  neither does a comment or a job that pull requests skip. It runs on
  the PR, not here. Its line is
  `<command> · <short SHA> · not run: CI runs it (<workflow file>)`.
- **Every other Gate** runs here, `cd "$WT" && <command>`,
  one at a time: never two at once, since two suites at once overload
  the local machine (ADR 0011). Its line is `<command> · <short SHA> · <result>
  (local machine)`, as in `pnpm lint · 1a2b3c4 · 0 errors (local
  machine)`.

A repo with no workflow file covers no Gate, so every Gate runs here.

## Missing tool

A Gate that fails because the local machine lacks its tool (`command
not found`, exit 127): say `<tool> is not installed on this machine;
install it, then say go.` and wait. On `go`, run that Gate again. A
Gate that cannot run here for another reason, such as one that needs
Docker the machine cannot start: its line is `<command> · <short SHA>
· not run: <why>`, and `/make-pr` names it for CI.

## Perf

With a `PERF` block, after the Gates, with no other Gate running. Put
the base in a second worktree:

```bash
git -C "$WT" worktree add --detach <temp folder> origin/<BASE>
```

Run its `Command` in turns, base then head, as many times each as its
`Pass rule` says. Write one line: `<Command> · <short SHA> · <metric>:
<base median> → <head median> <unit>, median of <n> in turns, spread
<low> to <high> (local machine)`. A base median outside the `Before`
spread adds ` (issue Baseline: <Before>)` before `(local machine)`.
Then `git -C "$WT" worktree remove --force <temp folder>`.

## Red

A red Gate, or a perf line whose head misses the `Pass rule`, is the
builder's: a follow-up per `render.sh local prompt` § Follow-up, `#
Check` naming the Gate. The pane gets it with `herdr-send`; as the
builder, you do it yourself. Then push (SKILL.md step 5), and the next
round runs the checks again. A red Gate after round three: stop with
its line.

Every Gate here is green, and every other line is `not run`: the
checks are done.
