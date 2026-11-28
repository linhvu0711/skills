# ci-covers.sh: the cases for the shared core's ci-covers.sh. tests/run.sh
# sources this file after lib.sh and runs its cases.

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

covers() { run bash "$here/../../shared/ci-covers.sh" "$T/wt" -- "$@"; }

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

t_cc_push_only() {
  # Given
  T=""; ci_yml 'on: push' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
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

t_cc_pr_inline_filter() {
  local v
  for v in '{branches: [main]}' '{types: [opened]}'; do
    # Given: the issue's repro
    T=""
    wf ci.yml 'on:' "  pull_request: $v" 'jobs:' '  t:' '    steps:' '      - run: pnpm test'
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($v)" "here · pnpm test" "$out"
  done
}

t_cc_needs_if_repro() {
  # Given: the issue's repro
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  a:' '    if: false' '    steps:' '      - run: pnpm lint' \
    '  t:' '    needs: a' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq stdout "here · pnpm test" "$out"
}

t_cc_needs_chain() {
  # Given
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  a:' '    if: false' '    steps:' '      - run: pnpm lint' \
    '  b:' '    needs: a' '    steps:' '      - run: pnpm build' \
    '  t:' '    needs: b' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

t_cc_needs_chain_reversed() {
  # Given: each job above the job it needs, so one pass down the file is not enough
  T=""
  wf ci.yml 'on: pull_request' 'jobs:' '  t:' '    needs: b' '    steps:' '      - run: pnpm test' \
    '  b:' '    needs: a' '    steps:' '      - run: pnpm build' \
    '  a:' '    if: false' '    steps:' '      - run: pnpm lint'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

# needs_yml <if line of job a, or empty> <needs line of job b, or empty>
# <needs line>...: ci.yml with jobs a (step pnpm lint), b (step pnpm
# build), and t (step pnpm test), t's needs given as one or more lines.
needs_yml() {
  local aif="$1" bneeds="$2"; shift 2
  local a=('  a:') b=('  b:')
  [ -z "$aif" ] || a+=("$aif")
  [ -z "$bneeds" ] || b+=("$bneeds")
  wf ci.yml 'on: pull_request' 'jobs:' "${a[@]}" '    steps:' '      - run: pnpm lint' \
    "${b[@]}" '    steps:' '      - run: pnpm build' \
    '  t:' "$@" '    steps:' '      - run: pnpm test'
}

# The forms of t's needs, one a line, the block list's lines split on |.
# Each list names a last, so a reader that keeps only the first name fails.
needs_forms=('    needs: a' '    needs: [b, a]' '    needs:|      - b|      - a' '    needs:|      [b, a]')

t_cc_needs_forms() {
  local f lines
  for f in "${needs_forms[@]}"; do
    # Given
    T=""; IFS='|' read -r -a lines <<<"$f"
    needs_yml '    if: false' '' "${lines[@]}"
    # When
    covers 'pnpm test' 'pnpm build'
    # Then
    eq "stdout ($f)" "here · pnpm test
ci ci.yml · pnpm build" "$out"
  done
}

t_cc_needs_no_if() {
  local f lines
  for f in "${needs_forms[@]}"; do
    # Given
    T=""; IFS='|' read -r -a lines <<<"$f"
    needs_yml '' '    needs: a' "${lines[@]}"
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($f)" "ci ci.yml · pnpm test" "$out"
  done
}

t_cc_needs_next_line() {
  local f lines
  for f in '    needs:|      a' '    needs:|      -|        a'; do
    # Given
    T=""; IFS='|' read -r -a lines <<<"$f"
    needs_yml '    if: false' '' "${lines[@]}"
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($f)" "here · pnpm test" "$out"
  done
}

t_cc_job_quoted_keys() {
  local k
  for k in '"needs": a' "'needs': a"; do
    # Given
    T=""; needs_yml '    if: false' '' "    $k"
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($k)" "here · pnpm test" "$out"
  done
  for k in '"if": false' "'if': false"; do
    # Given
    T=""; needs_yml "    $k" '' '    needs: a'
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($k)" "here · pnpm test" "$out"
  done
}

t_cc_quoted_step_keys() {
  local k
  for k in '"if": false' "'if': false" '"if" : false'; do
    # Given
    T=""; wf ci.yml 'on: pull_request' 'jobs:' '  t:' '    steps:' '      - run: pnpm test' "        $k"
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($k)" "here · pnpm test" "$out"
  done
  # Given
  T=""; wf ci.yml 'on: pull_request' 'jobs:' '  t:' '    "steps":' '      - run: pnpm test' '        if: false'
  # When
  covers 'pnpm test'
  # Then
  eq 'stdout ("steps":)' "here · pnpm test" "$out"
  for k in '    "steps":' '    steps:'; do
    # Given
    T=""; wf ci.yml 'on: pull_request' 'jobs:' '  t:' "$k" '      - run: pnpm test'
    # When
    covers 'pnpm test'
    # Then
    eq "stdout ($k, no if)" "ci ci.yml · pnpm test" "$out"
  done
  # Given
  T=""; wf ci.yml 'on: pull_request' '"jobs":' '  t:' '    if: false' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq 'stdout ("jobs":)' "here · pnpm test" "$out"
  # Given
  T=""; wf ci.yml 'on: pull_request' '"jobs":' '  t:' '    steps:' '      - run: pnpm test'
  # When
  covers 'pnpm test'
  # Then
  eq 'stdout ("jobs":, no if)' "ci ci.yml · pnpm test" "$out"
}

t_cc_needs_unknown_job() {
  # Given
  T=""; needs_yml '' '    needs: a' '    needs: c'
  # When
  covers 'pnpm test'
  # Then
  eq stdout "here · pnpm test" "$out"
}

cases=(
  "names the workflow that runs a Gate, in the Gates' order|t_cc_names_the_workflow"
  "a longer command is not the Gate|t_cc_longer_command"
  "a push-only workflow covers nothing|t_cc_push_only"
  "no workflows folder covers nothing|t_cc_no_workflows"
  "the issue's repro: a job if makes the Gate run here|t_cc_job_if_repro"
  "a job if sends each Gate of its steps here|t_cc_job_if_each_step"
  "if: always() counts like any if|t_cc_if_always"
  "a step if, before or after its run, sends only that step here|t_cc_step_if"
  "a step if under a bare dash sends only that step here|t_cc_step_if_bare_dash"
  "a filter under pull_request sends every Gate here|t_cc_pr_filter"
  "the issue's repro: a filter on the pull_request line sends the Gate here|t_cc_pr_inline_filter"
  "the issue's repro: needs on a job with an if sends the Gate here|t_cc_needs_if_repro"
  "needs through a chain to a job with an if sends the Gate here|t_cc_needs_chain"
  "a chain whose jobs come before the jobs they need sends the Gate here|t_cc_needs_chain_reversed"
  "each form of needs is read|t_cc_needs_forms"
  "needs with no if in the chain leaves the Gate to CI|t_cc_needs_no_if"
  "a needs name on the line under the key, bare or after a bare dash, is read|t_cc_needs_next_line"
  "a quoted needs or if key on a job counts|t_cc_job_quoted_keys"
  "a quoted if, steps, or jobs key counts|t_cc_quoted_step_keys"
  "needs on a job not in the file sends the Gate here|t_cc_needs_unknown_job"
)
