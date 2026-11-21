# ci-times.sh: the cases for improve-ci's scripts/ci-times.py. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
G="$here/../scripts/ci-times.py"

# run_row <id> <workflow> <attempt> <event> <sha> <created> <updated> [conclusion]: one run of run-list.
run_row() {
  printf '{"databaseId":%s,"workflowName":"%s","attempt":%s,"event":"%s","headSha":"%s","createdAt":"2026-11-20T%sZ","updatedAt":"2026-11-20T%sZ","conclusion":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${8:-success}"
}

# step <number> <name> <start> <end>: one step of a job.
step() {
  printf '{"number":%s,"name":"%s","conclusion":"success","started_at":"2026-11-20T%sZ","completed_at":"2026-11-20T%sZ"}' "$1" "$2" "$3" "$4"
}

# jobs <n> <name> <conclusion> <created> <started> <completed> <steps json>: run-jobs.<n>.json with one job.
jobs() {
  printf '{"jobs":[{"name":"%s","conclusion":"%s","created_at":"2026-11-20T%sZ","started_at":"2026-11-20T%sZ","completed_at":"2026-11-20T%sZ","steps":[%s]}]}' \
    "$2" "$3" "$4" "$5" "$6" "$7" > "$FAKE_GH/run-jobs.$1.json"
}

# two_runs: runs 1 and 2 of workflow CI, each with one job `test`.
two_runs() {
  fake_gh
  printf '[%s,%s]' "$(run_row 1 CI 1 push a1 10:00:00 10:03:25)" "$(run_row 2 CI 1 push a2 11:00:00 11:04:11)" > "$FAKE_GH/run-list.json"
  jobs 1 test success 10:00:00 10:00:04 10:03:24 "$(step 1 'Set up job' 10:00:04 10:00:06),$(step 2 'Run tests' 10:00:06 10:03:24)"
  jobs 2 test success 11:00:00 11:00:10 11:04:10 "$(step 1 'Set up job' 11:00:10 11:00:13),$(step 2 'Run tests' 11:00:13 11:04:10)"
}

# field <python expression on j>: the value from the JSON on stdout.
field() { printf '%s' "$out" | python3 -c 'import json,sys; j=json.load(sys.stdin); print(json.dumps(eval(sys.argv[1]), separators=(", ", ": ")))' "$1"; }

t_ci_times_splits_a_job() {
  # Given: two runs of CI's job `test`, waits 4 s and 10 s, totals 200 s and 240 s
  two_runs
  # When
  run python3 "$G" acme/app
  # Then
  eq exit 0 "$code"
  eq job '{"workflow": "CI", "job": "test", "runs": 2, "wait": {"p50": 4, "p95": 10}, "setup": {"p50": 2, "p95": 3}, "work": {"p50": 198, "p95": 237}, "total": {"p50": 200, "p95": 240}, "slowest": 240, "steps": [{"name": "Set up job", "p50": 2, "p95": 3}, {"name": "Run tests", "p50": 198, "p95": 237}]}' "$(field 'j["jobs"][0]')"
}

t_ci_times_named_setup_step() {
  # Given: the two runs
  two_runs
  # When
  run python3 "$G" acme/app --setup "Run tests"
  # Then
  eq setup '{"p50": 200, "p95": 240}' "$(field 'j["jobs"][0]["setup"]')"
  eq work '{"p50": 0, "p95": 0}' "$(field 'j["jobs"][0]["work"]')"
}

t_ci_times_skips_skipped_jobs() {
  # Given: the two runs, plus run 3 with a skipped job and run 4 with a cancelled one
  two_runs
  printf '[%s,%s,%s,%s]' "$(run_row 1 CI 1 push a1 10:00:00 10:03:25)" "$(run_row 2 CI 1 push a2 11:00:00 11:04:11)" \
    "$(run_row 3 CI 1 push a3 12:00:00 12:00:01)" "$(run_row 4 CI 1 push a4 13:00:00 13:09:00 cancelled)" > "$FAKE_GH/run-list.json"
  jobs 3 test skipped 12:00:00 12:00:00 12:00:00 ""
  jobs 4 test cancelled 13:00:00 13:00:01 13:09:00 "$(step 1 'Run tests' 13:00:01 13:09:00)"
  # When
  run python3 "$G" acme/app
  # Then
  eq runs 2 "$(field 'j["jobs"][0]["runs"]')"
  eq total_p95 240 "$(field 'j["jobs"][0]["total"]["p95"]')"
}

t_ci_times_fewer_runs_than_asked() {
  # Given: the two runs
  two_runs
  # When
  run python3 "$G" acme/app --runs 150
  # Then
  eq counts '[150, 2]' "$(field '[j["asked"], j["runs"]]')"
}

t_ci_times_no_runs() {
  # Given: a repo with no completed run
  fake_gh
  printf '[]' > "$FAKE_GH/run-list.json"
  # When
  run python3 "$G" acme/app
  # Then
  eq exit 0 "$code"
  eq empty '[0, []]' "$(field '[j["runs"], j["jobs"]]')"
}

t_ci_times_gh_fails() {
  # Given: the two runs, and gh refuses the run list
  two_runs
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/run-list.fail"
  # When
  run python3 "$G" acme/app
  # Then
  eq exit 1 "$code"
  eq stderr 'stop: gh could not list runs: HTTP 401: Bad credentials' "$err"
}




cases=(
  "ci-times splits a job into wait, steps, and total|t_ci_times_splits_a_job"
  "ci-times counts a named step as setup|t_ci_times_named_setup_step"
  "ci-times skips skipped and cancelled jobs|t_ci_times_skips_skipped_jobs"
  "ci-times reports fewer runs than asked|t_ci_times_fewer_runs_than_asked"
  "ci-times prints zero runs on a repo with none|t_ci_times_no_runs"
  "ci-times stops when gh fails|t_ci_times_gh_fails"
)
