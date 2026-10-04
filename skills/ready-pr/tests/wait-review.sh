# wait-review.sh: the cases for this skill's wait-review.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# wait_review [<flag>...]: wait-review.sh on the head commit of PR 7.
wait_review() { run bash "$here/../scripts/wait-review.sh" acme/app abc1234def5678 "$@"; }

t_wait_review_success() {
  fake_gh; printf '{"statuses":[{"context":"Devin Review","state":"success"}]}\n' > "$FAKE_GH/status.json"
  wait_review
  eq exit 0 "$code"
  eq stdout "DEVIN=success SHA=abc1234def5678 WAITED=0" "$out"
}

t_wait_review_none() {
  fake_gh; printf '{"statuses":[]}\n' > "$FAKE_GH/status.json"
  printf '{"check_runs":[]}\n' > "$FAKE_GH/check-runs.json"
  wait_review --none-sec 2 --poll-sec 1
  eq exit 3 "$code"
  eq stdout "DEVIN=none SHA=abc1234def5678 WAITED=2" "$out"
}

t_wait_review_gh_fails() {
  fake_gh; printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/status.fail"
  wait_review
  eq exit 4 "$code"
  eq stderr "stop: gh failed: gh: Bad credentials (HTTP 401)" "$err"
  eq "status calls" 5 "$(cat "$FAKE_GH/status.calls")"
}

t_wait_review_one_failure() {
  fake_gh; printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/status.1.fail"
  printf '{"statuses":[{"context":"Devin Review","state":"success"}]}\n' > "$FAKE_GH/status.json"
  wait_review --poll-sec 1
  eq exit 0 "$code"
  eq stdout "DEVIN=success SHA=abc1234def5678 WAITED=1" "$out"
}

cases=(
  "wait-review: success reads DEVIN=success|t_wait_review_success"
  "wait-review: no status reads DEVIN=none|t_wait_review_none"
  "wait-review: 5 failed calls stop with exit 4|t_wait_review_gh_fails"
  "wait-review: one failed call then success goes on|t_wait_review_one_failure"
)
