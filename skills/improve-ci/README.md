# improve-ci

Times a repo's GitHub Actions runs and reads its merged PRs and workflow files, then shows what makes CI slow, what hides a failure, and what leaves it unsafe. It grills you on every find and files the fixes as issues.

## Use it when

CI takes long enough that you wait on it, a check turns green after a re-run with no change, or you have never looked at what your workflows do. Type `/improve-ci` in the repo. It works on GitHub Actions only; on any other CI it says so and stops. On a repo with no CI yet, it proposes a first one.

## What you get

An HTML report that opens in your browser as a local page. The top is a timing table built from the last 150 runs: for each job, how long it waits for a machine, how long setup takes (clone, install, caches), how long the checks take, and the slowest run. A script does the math, so a p95 is always a real run's time.

Each big find gets a card: the change, its goal (speed, honesty, or security), the file and line, the time now and the target, the time limit for each job it touches, and the proof. Small ones, such as an action pinned to a tag where a commit would be safer, sit in short tables. The report ends with a top pick.

What it looks for:

- **Speed.** Machine waits, setup with no cache, the job that ends the PR result, jobs that wait on each other with no need, old runs that keep going after a new push, PRs that change only docs and still run every check, and tests a PR's diff cannot reach.
- **Honesty.** Steps that hide a failure (`continue-on-error`, `|| true`, retries, skipped tests), runs that passed only on a re-run, and tests whose fixes only ever changed the test.
- **Security.** Outside actions pinned to a tag, and a CI token with more access than its job needs.
- **Other.** Workflow files with a job that can never run, work two jobs do twice, and a push hook that does not run what CI runs.

On a TypeScript or JavaScript repo it also reads a file of TS/JS tool tips (bun, oxlint, the native TypeScript compiler), and each run checks those tips on the web before it proposes them. Other stacks get the web check alone.

When you say `go`, a [grill](../grill/) asks about every find. Each target and time limit is proposed from the repo's own run times, with the reason, and you accept or change it. Then the grill files the work as issues, each with a measured line under Done when, such as `setup p50 under 20s on 10 PR runs`. Say `drop` to skip a find.

It changes no code and no workflow file. It never proposes a retry, a wider timeout, or a skipped test as a fix, and it keeps the full test suite running before anything reaches main.

## Needs

- `gh`, logged in, with read access to the repo's Actions runs, PRs, and branch rules. Classic branch protection needs admin access; without it the report says those rules were not read.
- `python3`, for the timing script.
- Sub-agents: explorers for the workflow files, the PR history, and the stack, per the reader job in `../../shared/facts.md`, and one with the web for the tip check.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server, and the network for Tailwind. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- [grill](../grill/), for the finds.
- From the shared core: [facts.md](../../shared/facts.md) and [serve.sh](../../shared/serve.sh).

## Fits with

- Calls [grill](../grill/) on every find. The issues it files go through [plan-up](../plan-up/) and [ship](../ship/) like any other.
- [triage](../triage/) is for one slow thing whose cause you do not know yet. This skill audits the whole CI at once.
- No other skill calls it; you start it yourself.
