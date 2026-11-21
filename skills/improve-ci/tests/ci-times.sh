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




t_ci_times_pr_commit() {
  # Given: two pull_request runs on head abc, CI from 10:00:00 to 10:03:30 and Lint from 10:00:02 to 10:01:00
  fake_gh
  printf '[%s,%s]' "$(run_row 1 CI 1 pull_request abc 10:00:00 10:03:30)" "$(run_row 2 Lint 1 pull_request abc 10:00:02 10:01:00)" > "$FAKE_GH/run-list.json"
  jobs 1 test success 10:00:00 10:00:04 10:03:24 "$(step 1 'Run tests' 10:00:04 10:03:24)"
  jobs 2 lint success 10:00:02 10:00:04 10:00:58 "$(step 1 'Run lint' 10:00:04 10:00:58)"
  # When
  run python3 "$G" acme/app
  # Then
  eq pr_result '{"commits": 1, "p50": 210, "p95": 210}' "$(field 'j["pr_result"]')"
}

t_ci_times_rerun() {
  # Given: run 7 of CI on its second attempt; on attempt 1 `test` failed and `lint` passed
  fake_gh
  printf '[%s]' "$(run_row 7 CI 2 push a7 10:00:00 10:09:00)" > "$FAKE_GH/run-list.json"
  jobs 1 test success 10:05:00 10:05:02 10:08:58 "$(step 1 'Run tests' 10:05:02 10:08:58)"
  printf '{"jobs":[{"name":"test","conclusion":"failure"},{"name":"lint","conclusion":"success"}]}' > "$FAKE_GH/attempt-jobs.json"
  # When
  run python3 "$G" acme/app
  # Then
  eq reruns '[{"run": 7, "workflow": "CI", "attempts": 2, "conclusion": "success", "failed_first": ["test"]}]' "$(field 'j["reruns"]')"
}

t_ci_times_no_rerun() {
  # Given: the two runs, each a first attempt
  two_runs
  # When
  run python3 "$G" acme/app
  # Then
  eq reruns '[]' "$(field 'j["reruns"]')"
  eq attempt_calls no "$([ -e "$FAKE_GH/attempt-jobs.calls" ] && echo yes || echo no)"
}
t_ci_times_jobs_past_one_page() {
  # Given: run 1 of CI with 101 jobs, 100 on page 1 and `last` on page 2
  fake_gh
  printf '[%s]' "$(run_row 1 CI 1 push a1 10:00:00 10:03:25)" > "$FAKE_GH/run-list.json"
  one='{"name":"job","conclusion":"success","created_at":"2026-11-20T10:00:00Z","started_at":"2026-11-20T10:00:01Z","completed_at":"2026-11-20T10:00:11Z","steps":[]}'
  printf '{"jobs":[%s]}' "$(for i in $(seq 100); do printf '%s,' "$one"; done | sed 's/,$//')" > "$FAKE_GH/run-jobs.1.json"
  jobs 2 last success 10:00:00 10:00:02 10:00:22 ""
  # When
  run python3 "$G" acme/app
  # Then
  eq names '["job", "last"]' "$(field '[r["job"] for r in j["jobs"]]')"
  eq pages 'api repos/acme/app/actions/runs/1/jobs?per_page=100&page=2' "$(sed -n 2p "$FAKE_GH/run-jobs.args")"
}

cases=(
  "ci-times splits a job into wait, steps, and total|t_ci_times_splits_a_job"
  "ci-times counts a named step as setup|t_ci_times_named_setup_step"
  "ci-times skips skipped and cancelled jobs|t_ci_times_skips_skipped_jobs"
  "ci-times reads a run's jobs past the first page|t_ci_times_jobs_past_one_page"
  "ci-times reports fewer runs than asked|t_ci_times_fewer_runs_than_asked"
  "ci-times prints zero runs on a repo with none|t_ci_times_no_runs"
  "ci-times stops when gh fails|t_ci_times_gh_fails"
  "ci-times times a PR commit from its first run to its last|t_ci_times_pr_commit"
  "ci-times lists a re-run with the jobs that failed first|t_ci_times_rerun"
  "ci-times lists no re-run when every run is a first attempt|t_ci_times_no_rerun"
)
