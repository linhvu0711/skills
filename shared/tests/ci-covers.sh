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
  wf ci.yml 'on:' '  push:' '  pull_request:' '    branches: [main]' 'jobs:' '  test:' \
    '    runs-on: ubuntu-latest' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "ci ci.yml · pnpm test" "$out"
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
  "no command after -- is a usage stop|t_cc_usage"
)
