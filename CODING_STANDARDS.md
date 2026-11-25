This file is the Standard: the rules for how code is written in this repo. Read it before you write or review code. Rules a tool checks live in its config (`scripts/check.sh`, `scripts/hooks/commit-msg`, `.editorconfig`), not here.
`(name)` after a rule names its source, listed in `docs/standards/sources.md`. `[tool, after #61]` means a tool will check the rule once ticket #61 turns its check on; until then, this line is the rule.
`Old way:` names a way that existing code still uses. Add no new use of it.

## One way for each job

- Stop a script with an error: `die()` in shell, which prints `stop: <why>` on stderr and exits 1; `sys.exit("stop: <why>")` in Python. Old way: `print` then `sys.exit(1)`, `raise SystemExit(1)` (#409).
- Call GitHub: `shared/gh.sh` in shell, `shared/gh.py` in Python. Old way: `gh` called directly (#409).
- Find a script's own folder: `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`. Old way: `dirname "$0"`, `realpath` (#409).
- Read JSON in shell: `jq`. Old way: `python3 -c` with `json.load`, `node -p`, `sed` or `grep -o` (#409).
- Write JSON in shell: literal text for a fixed fixture, `jq -n --arg` when a value comes from a variable. Old way: a hand-written string with a variable in it (#409).
- Clean up temp files: a `trap … EXIT` in shell, `try`/`finally` in Python (bash-manual). Old way: `rm` after use (#409).
- Replace a file: write a temp file in the same folder, then `mv`; Python: `os.replace`. Old way: a temp file in another folder, an own `.tmp.$$` name (#409).
- Loop over a command's output lines: `while IFS= read -r`. Old way: `for x in $(…)` (#409).
- Test a condition in shell: `[ ]` with quoted values for a plain test, `[[ ]]` for `=~` and patterns.
- Name a Python file: snake_case, since only a snake_case module can be imported (pep-8). Old way: dashes, as `build-report.py` (#410).
- Parse command-line arguments: `argparse` in Python, `util.parseArgs` in Node. Old way: `sys.argv` or `process.argv` read by hand (#410).
- Work with file paths in Python: `os.path`. Old way: `pathlib` (#410).
- Limit a CI workflow: `timeout-minutes` on each job, a `concurrency` group that cancels the older run of the same ref, and `push` on `main` only (github-actions-workflow-syntax, github-actions-events).
- Do a job every session adapter needs (load a sibling module, skip injected context, keep the project's sessions of the last N days): a helper in `shared/sessions/adapter_lib.py`. Old way: an adapter's own `load()` or its own injected-context check (#410).
- Set up a git repo in a test: `repo` from `scripts/test-lib.sh`. Old way: own setup code (#408).
- Check a result in a test: `eq`, `has`, and `lacks` from `scripts/test-lib.sh`. Old way: a bare `[ -e … ] || exit 1` check (#408).
- Start another skill from skill text: "start the `<name>` skill"; `shared/harness.md` names each harness's way.
- Lay out Markdown: one line per paragraph, list item, or table row.

## Names

- Files and folders are kebab-case, except Python files, which are snake_case per One way for each job; `SKILL.md`, `README.md`, `LICENSE`, and the root's `AGENTS.md`-style files are in capitals.
- Shell functions and variables are lower_snake_case; env vars and constants are UPPER_SNAKE with a prefix, as `WORKTREES_ROOT`.
- A shell test function is `t_<prefix>_<case>`.
- Python functions and variables are snake_case, classes CapWords, and constants UPPER_SNAKE (pep-8).
- JS functions and variables are camelCase, and constants UPPER_SNAKE.
- CSS classes and JSON or YAML keys follow the file they are in.

## Structure

- A file that two or more skills read lives in `shared/`, not inside one of the skills.
- A skill names its own files by their path from its folder, as `references/probes.md`, another skill's as `../<skill>/…`, and the shared core's as `../../shared/…`, and its `SKILL.md` opens with the real-folder line.
  Why: `docs/adr/0001-relative-paths.md`.
- A skill folder holds `SKILL.md` and, when it needs them, `scripts/`, `references/`, `assets/`, `agents/`, and `tests/`; references sit one level deep (agentskills-spec).
- A skill copied or adapted from another repo keeps its upstream's `LICENSE` in its folder, and each copied or adapted file has a row in `THIRD_PARTY_NOTICES.md`.
- Each harness has one session adapter in `shared/sessions/<harness>/` with `find` and `extract`, and `shared/sessions/find_all.py` runs each installed adapter's `find`.
  Why: `docs/adr/0016-retro-finds-harnesses-through-adapters.md`, as `docs/adr/0037-one-find-all-call-finds-every-harness.md` amends it.

## Errors

- A wrong command line prints the usage line on stderr and exits non-zero: 64 for a shell script, argparse's own 2 for a Python script, and 1 through `stop()` for a Node script.
- A script whose exit code carries an answer, as `ready.sh` returns 0, 1, or 2, keeps its codes and lists them in its usage.
- A stop message says what went wrong, what was expected, and what to try (agentskills-using-scripts).
- A missing optional tool prints `warn: <what>` on stderr, and the script goes on.
- Exit codes 126 and 127 stay the shell's own (bash-manual).

## Logging

- Scripts use no logging library: results go to stdout, problems and warnings to stderr (agentskills-using-scripts).
- No token, secret, or key reaches output or a log (owasp-logging).

## Tests

- A test for a skill's script goes in `skills/<name>/tests/`, one file per script, and its cases go in its own `cases` list, which `scripts/test.sh` runs.
- A test for a shared core script goes in `shared/tests/`, one file per script.
- A test uses the helpers and the fake `gh`, `curl`, and `nsc` of `scripts/test-lib.sh`, and marks its steps with `# Given`, `# When`, and `# Then`.

## Commits

- A commit subject follows Conventional Commits, `<type>(<scope>)!: <subject>`, with `!` for a breaking change (conventional-commits).
- The subject is in the imperative mood, with one blank line before the body (git-pro-book).
- A commit is one logical change, and a pull request has one purpose (git-pro-book, github-pr-docs).
- A branch is `<type>/<issue>-<slug>`.

## Deps

- Scripts need no package manager: they use bash, the Python standard library, `jq`, and `gh`.
- A script checks each CLI it needs with `command -v`, or `shutil.which` in Python, before it uses it (posix-command, python-shutil).

## Config and secrets

- Config comes from env vars named UPPER_SNAKE with a prefix, as `GH_ISSUE_STORE`, and per-user state lives under `~/.config/<skill>/`.
- A credential is read from an env var at run time and never sits in a tracked file (twelve-factor-config, owasp-secrets).
- `gh` gets its token from its own login, never from a script.

## API shape

- A script takes positional arguments and `--flags`, never a prompt (agentskills-using-scripts).
- A script prints its result on stdout as `KEY=value` lines, a verdict line, JSON, or TSV.

## Formatting

- Python strings use double quotes; JS strings use single quotes, and JS statements end with semicolons.
- Code has no line-length limit.

## Stack-specific

### Agent skills

- Skill text writes each step once, in words that fit every harness, and names no harness's tool; `shared/harness.md` holds each harness's tool for the step.
  Why: `docs/adr/0029-skills-never-name-a-harness.md`.
- A skill asks a helper for a job in plain words, with the job's rules pasted from `shared/facts.md`.
  Why: `docs/adr/0017-skills-ask-for-helper-jobs-in-plain-words.md` and `docs/adr/0027-the-explorer-and-the-runner-ship-in-the-repo.md`.
- A skill starts a subagent per `shared/facts.md` § Skill agents: in T3 on its home models, tried from left to right, and outside T3, or when no home can run, on its backup. When it does not run on its first home, the skill's report says so in one line.
  Why: `docs/adr/0028-a-subagents-model-depends-on-the-main-agent.md` and `docs/adr/0030-a-subagent-tries-its-home-models-in-order.md`.
- An Antigravity agent's backup is `inherit`.
  Why: `docs/adr/0026-an-antigravity-helper-takes-the-main-agents-model.md`.
- A skill description starts with a command verb, as "Find a past session…", and ends with a "Use when …" sentence (agentskills-descriptions).
- `SKILL.md` says when to read each reference file, and a reference over 100 lines opens with a table of contents (anthropic-skill-best-practices).

### Bash

- A script that runs starts with `#!/usr/bin/env bash` and `set -euo pipefail`; a sourced helper has neither (bash-manual).
- Every `$name` and `$(…)` sits in double quotes, a function's variables are `local`, and command substitution is `$(…)` (bash-manual).

### Python

- Scripts use the Python 3 standard library only.
- A script runs `main()` under `if __name__ == "__main__":`.

### Page JS

- A page is one HTML file with its script inline, and its data goes in as `const DATA = …` with `<` escaped as `<`.
- A Node script is a `.cjs` file that runs its main code only when `require.main === module` (node-docs-modules).

### GitHub Actions

- A workflow sets top-level `permissions: contents: read` (github-actions-workflow-syntax).
- An `actions/…` action is pinned to its major tag; any other action is pinned to a full commit SHA with its tag in a comment (github-actions-hardening, actions-checkout-readme).

## By folder

- `skills/ready-pr/scripts/ready.sh` only reads: it never pushes or restacks; `restack.sh` does that.
  Why: `docs/adr/0008-readiness-module-only-reads.md`.

## Each change

- Docs ship in the pull request whose code makes them true.
  Why: `docs/adr/0012-docs-ship-with-the-code.md`.
- A new repo rule goes in this file, never in `AGENTS.md`, a README, or a `REVIEW.md`.
  Why: `docs/adr/0036-the-standard-is-the-only-rules-file.md`.

## Not covered

- How a page puts text on screen (`innerHTML` with `esc()`, or `textContent`) and how it is styled (own CSS, or the Tailwind CDN): each page picks.
- Rules for one folder of `skills/build-and-prove/` or `skills/plan-up/`, the two folders with the most fixes in the 4 weeks to 2026-11-25: left out on purpose.
