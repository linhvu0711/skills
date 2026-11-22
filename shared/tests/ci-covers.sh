# ci-covers.sh: the cases for the shared core's ci-covers.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# wf <file> <line>...: a workflow file in $T/wt/.github/workflows, one line
# per argument. Sets T on the first call.
wf() {
  [ -n "${T:-}" ] || T="$(cd "$(mktemp -d)" && pwd -P)"
  local f="$T/wt/.github/workflows/$1"; shift
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$@" > "$f"
}

# ci_yml <on line> <run line>: the passing case's ci.yml, with its trigger
# line and its step line given.
ci_yml() {
  wf ci.yml "$1" 'jobs:' '  test:' '    runs-on: ubuntu-latest' '    steps:' "$2"
}

covers() { run bash "$here/../ci-covers.sh" "$T/wt" -- "$@"; }

t_cc_names_the_workflow() {
  # Given
  T=""; ci_yml 'on: pull_request' '      - run: pnpm test'
  # When
  covers 'pnpm test' 'pnpm lint'
  # Then
  eq exit 0 "$code"
  eq stdout "ci ci.yml · pnpm test
here · pnpm lint" "$out"
}

t_cc_longer_command() {
  # Given
  T=""; ci_yml 'on: pull_request' '      - run: pnpm test:e2e'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

t_cc_comment() {
  # Given
  T=""; ci_yml 'on: pull_request' '      # - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

t_cc_push_only() {
  # Given
  T=""; ci_yml 'on: push' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

t_cc_run_block() {
  # Given
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  test:' '    runs-on: ubuntu-latest' '    steps:' \
    '      - run: |' '          pnpm lint' '          pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "ci ci.yml · pnpm test" "$out"
}

t_cc_no_workflows() {
  # Given
  T="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$T/wt"
  # When
  covers 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq stdout "here · pnpm test" "$out"
}

t_cc_on_list() {
  # Given: as this repo's own repo-check.yml
  T=""
  wf repo-check.yml 'on: [push, pull_request]' 'jobs:' '  check:' '    steps:' \
    '      - name: Test the checks' '        run: bash scripts/test.sh'
  # When
  covers 'bash scripts/test.sh'
  # Then
  eq stdout "ci repo-check.yml · bash scripts/test.sh" "$out"
}

t_cc_on_map() {
  # Given
  T=""
  wf ci.yml 'on:' '  push:' '    branches: [main]' '  pull_request:' 'jobs:' '  test:' \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "ci ci.yml · pnpm test" "$out"
}

t_cc_job_if_repro() {
  # Given: the issue's repro
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  test:' "    if: github.base_ref == 'release'" \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq stdout "here · pnpm test" "$out"
}

t_cc_job_if_each_step() {
  # Given
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  test:' '    runs-on: ubuntu-latest' \
    "    if: github.event_name == 'push'" '    steps:' '      - run: pnpm lint' '      - run: pnpm test' \
    '  build:' '    runs-on: ubuntu-latest' '    steps:' '      - run: pnpm build'
  # When
  covers 'pnpm lint' 'pnpm test' 'pnpm build'
  # Then
  eq stdout "here · pnpm lint
here · pnpm test
ci ci.yml · pnpm build" "$out"
}

t_cc_if_always() {
  # Given
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  test:' '    if: always()' '    runs-on: ubuntu-latest' \
    '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

t_cc_step_if() {
  # Given
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  test:' '    runs-on: ubuntu-latest' '    steps:' \
    "      - if: github.event_name == 'push'" '        run: pnpm lint' \
    '      - run: pnpm test' "        if: github.event_name == 'push'" '      - run: pnpm build'
  # When
  covers 'pnpm lint' 'pnpm test' 'pnpm build'
  # Then
  eq stdout "here · pnpm lint
here · pnpm test
ci ci.yml · pnpm build" "$out"
}

t_cc_step_if_bare_dash() {
  # Given
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  test:' '    runs-on: ubuntu-latest' '    steps:' \
    '      -' '        if: false' '        run: pnpm lint' '      -' '        run: pnpm test'
  # When
  covers 'pnpm lint' 'pnpm test'
  # Then
  eq stdout "here · pnpm lint
ci ci.yml · pnpm test" "$out"
}

t_cc_pr_filter() {
  local k
  for k in branches branches-ignore paths paths-ignore types; do
    # Given
    T=""
    wf ci.yml 'on:' '  pull_request:' "    $k: [release]" 'jobs:' '  test:' '    runs-on: ubuntu-latest' \
      '    steps:' '      - run: pnpm lint' '      - run: pnpm test'
    # When
    covers 'pnpm lint' 'pnpm test'
    # Then
    eq "stdout ($k)" "here · pnpm lint
here · pnpm test" "$out"
  done
}

t_cc_usage() {
  # Given
  T=""; ci_yml 'on: pull_request' '      - run: pnpm test'
  # When
  run bash "$here/../ci-covers.sh" "$T/wt" --
  # Then
  eq exit 1 "$code"
  eq stderr "stop: usage: ci-covers.sh <worktree> -- <command>..." "$err"
}

cases=(
  "names the workflow that runs a Gate, in the Gates' order|t_cc_names_the_workflow"
  "a longer command is not the Gate|t_cc_longer_command"
  "a comment is not a run line|t_cc_comment"
  "a push-only workflow covers nothing|t_cc_push_only"
  "a line of a run block counts|t_cc_run_block"
  "no workflows folder covers nothing|t_cc_no_workflows"
  "the list form of on counts|t_cc_on_list"
  "the map form of on counts|t_cc_on_map"
  "the issue's repro: a job if makes the Gate run here|t_cc_job_if_repro"
  "a job if sends each Gate of its steps here|t_cc_job_if_each_step"
  "if: always() counts like any if|t_cc_if_always"
  "a step if, before or after its run, sends only that step here|t_cc_step_if"
  "a step if under a bare dash sends only that step here|t_cc_step_if_bare_dash"
  "a filter under pull_request sends every Gate here|t_cc_pr_filter"
  "no command after -- is a usage stop|t_cc_usage"
)
