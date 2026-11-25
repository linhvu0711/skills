---
name: improve-ci
description: "Audit a repo's GitHub Actions CI from its past runs, merged PRs, and workflow files: what makes it slow, what lets it lie, what leaves it unsafe. Show the finds in a visual report with real times, then grill every one and file the fixes as issues. Use when the user asks why CI is slow, flaky, or unsafe, or to audit it."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Read `references/playbook.md` first. It holds the three rules every fix keeps, how a target and a time limit are proposed, and every kind of **find** this skill looks for, by goal: speed, honesty, security, and other. Use its words in every brief, every card, and every question. The domain terms come from `CONTEXT.md`. ADRs under `docs/adr/`, and the `## Docs to write` text in open issues, record decisions this skill does not re-litigate.

A find is **big** (a design choice, or many jobs) or **small** (one clear edit, such as adding a cancel-old-runs rule). You judge the size from the find itself.

You change no code and no workflow file. The output is a report, a grill, and the issues the grill files.

## Facts

Read `../../shared/facts.md` first: you are the brain, explorers retrieve, short lookups are yours. An explorer has no network, so every `gh` call is yours and its output goes to the explorer as a file.

## Steps

1. **Preflight.** Hold `REPO`, `isInOrganization`, `visibility`, and the default branch `BRANCH` from `gh repo view --json nameWithOwner,isInOrganization,visibility,defaultBranchRef`: the playbook's full-suite rule reads the first three.
   - `gh auth status` fails: say `gh is not logged in. Run: gh auth login` and stop.
   - The repo has a `.github/workflows/*.yml` or `.github/workflows/*.yaml` file: GitHub Actions, go on.
   - None, but another CI file (`.gitlab-ci.yml`, `.circleci/config.yml`, `Jenkinsfile`, `azure-pipelines.yml`, `bitbucket-pipelines.yml`, `.travis.yml`): say `improve-ci reads GitHub Actions only; this repo uses <that CI>.` and stop.
   - No CI file at all: the **first-CI** path. Skip step 2, do step 3 for the stack alone, and the report and the grill hold one find: the first CI, built from the playbook and the stack tips.

   Done when you hold `REPO`, `isInOrganization`, `visibility`, `BRANCH`, and the path.

2. **Measure.**

   ```bash
   python3 scripts/ci-times.py <REPO>
   ```

   It reads the last 150 completed runs and prints JSON: per job the wait, setup, work, total, slowest, and each step, at p50 and p95; the PR result time; and every re-run with the jobs that failed first. `stop:` on stderr: show it and stop.

   Read each job's step names. Setup counts the built-in steps and the checkout, setup, and cache actions. A step that installs or restores, named by the repo (`bun install`, `Install deps`, `Restore build`), is setup too: run the script again with one `--setup "<step name>"` per such step. `runs` under `asked` goes in the report header, as `112 of 150 runs`. `runs` 0: the report says no run history, and the targets come from the stack alone.

   Done when every job's setup holds every step that prepares the machine and none that checks the code.

3. **Research.** First save the merged PRs and the branch rules to temp files:

   ```bash
   gh pr list --state merged -L 100 --json number,title,files,changedFiles,commits > <tmp>/prs.json
   gh api --paginate repos/<REPO>/rules/branches/<BRANCH> --jq '.[]' > <tmp>/rules.jsonl
   gh api repos/<REPO>/branches/<BRANCH>/protection > <tmp>/protection.json
   ```

   `rules.jsonl` holds one ruleset rule per line, every page read.
   - The rules call fails with `make this repository public to enable this feature`: a private repo on a free plan has no rulesets, so an empty file is the answer. It fails another way: the report says the rulesets were not read.
   - The protection call fails with `Branch not protected`: the branch has no classic rule, so save `{}`. It fails another way (a token with no admin access gets 403): save the part read access can see, `gh api repos/<REPO>/branches/<BRANCH> --jq .protection`, which names the required checks. The report says the rest of the classic rules were not read.

   Then start explorers per `facts.md`, one per concern, in one message. Each brief names the repo's checkout, the playbook's find kinds for its concern pasted in, and the files it reads:

   - **Workflows**: every workflow file, the repo's hook files and hook tool config, `AGENTS.md`, and `rules.jsonl` and `protection.json` for the checks a rule requires. Ask for each honesty, security, and other find, with `path:line`.
   - **History**: `prs.json` and the re-runs from step 2. Ask for the share of PRs that changed only files no check reads, with the checks that read each such file. `gh` lists at most 100 files per PR: a PR whose `changedFiles` is more than its `files` holds counts as one that changed code. Ask also for the tests whose fixes changed only the test file; and each re-run's failed job.
   - **Stack**: the lockfiles, manifests, and tool configs. Ask for the languages, package manager, test runner, linter, formatter, and typechecker, each with its file.

   When the stack has a file under `references/stacks/`, read it (TS/JS: `references/stacks/ts-js.md`); a stack with no file gets the playbook alone. Then one explorer whose brief asks for the web checks each tip against current docs: is the tool still the fastest choice, is the named version current, did a newer tool replace it. A tip the web shows stale is dropped or replaced, with the source. The web check fails or returns nothing: use the file as it is, and the report says the tips were not checked.

   Every find gets its numbers from step 2, its proof with an evidence label, a goal, and a size. A big find also gets its proposed target and time limit, per the playbook. Done when every find kind in the playbook was looked for, and each one found or ruled out.

4. **Report.** Build the report per `references/html-report.md`, serve it, and open it. No find: the report says so, and the run ends with no grill. Else say how many finds, big and small, and ask the user to say `go` when they have read it. Stop and wait.

5. **Grill.** On `go`, read `../grill/SKILL.md` and follow it. Seed: the report. Open decisions, in this order: each big find, the one with the most time to win first, each with its proposed target and time limit as the pick; then each small table as one decision; then the time limit for every job no big find covers. The user's `drop` skips a find; a big one dropped for a reason that will still hold next run goes in the grill's ADR list, so the next run leaves it out. The grill's close-out files the work in the shape it picks. Each issue's Done when follows the playbook's § Issues.

   The first-CI path seeds one decision: the first CI, its jobs, its targets, and its time limits. It files one issue.

## Examples

**User:** `/improve-ci`

A TS/JS web app. Step 2: 150 runs; the PR result is 6m10s at p50. Job `test` spends 1m50s in setup; its `pnpm install` step is setup, so the script runs again with `--setup "pnpm install"`. Research: 41 of 100 merged PRs changed only `docs/`, and no check reads `docs/`; `e2e` has `continue-on-error: true`; 3 re-runs failed first on `test`; `actions/checkout@v4` is not pinned to a commit. `ts-js.md` fits; the web check finds its tips current. Report: three big cards (cache the installed packages, skip docs-only PRs inside the job, make `e2e` count) and one small table (pin the actions, cancel old runs). The grill opens with the install cache, target setup 20s, limit 4m.

**User:** `/improve-ci` on a Go repo with no `.github/workflows`

No CI file: the first-CI path. Research finds `go.mod`, `golangci.yml`, and tests under `./...`. No stack file fits; the web check gives the current Go cache and lint actions. The report holds one card, the first CI: lint, test, and build side by side, with caches. The grill settles its jobs and targets and files one issue.
