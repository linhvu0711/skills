# ready.sh: the cases for this skill's ready.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Items of a status check rollup, as `gh pr view` gives them.
ci_green='{"__typename":"CheckRun","name":"check","status":"COMPLETED","conclusion":"SUCCESS"}'
ci_red='{"__typename":"CheckRun","name":"check","status":"COMPLETED","conclusion":"FAILURE"}'
ci_pending='{"__typename":"CheckRun","name":"check","status":"IN_PROGRESS","conclusion":null}'
# The rollup lists Devin Review too, as GitHub does; only a required check is read from it.
devin_in_rollup='{"__typename":"StatusContext","context":"Devin Review","state":"SUCCESS"}'

# pr_json <file> <mergeStateStatus> <mergeable> <reviewDecision> <isDraft> <rollup>:
# a `gh pr view` answer for PR 7 of acme/app, head abc1234def5678, in $FAKE_GH.
pr_json() {
  jq -n --arg ms "$2" --arg m "$3" --arg rd "$4" --argjson d "$5" --argjson r "$6" '{
    number: 7, url: "https://github.com/acme/app/pull/7", title: "fix: demo", state: "OPEN",
    isCrossRepository: false, baseRefName: "main", headRefName: "fix/7-demo",
    headRefOid: "abc1234def5678", author: {login: "author"}, mergeable: $m,
    mergeStateStatus: $ms, reviewDecision: $rd, isDraft: $d, statusCheckRollup: $r }' > "$FAKE_GH/$1"
}

# threads_json <nodes>: a review threads answer with these nodes, one page.
threads_json() {
  jq -n --argjson n "$1" '{data: {repository: {pullRequest: {reviewThreads:
    {pageInfo: {hasNextPage: false, endCursor: null}, nodes: $n}}}}}' > "$FAKE_GH/graphql.json"
}

# required_json <protection contexts> <ruleset contexts>: the required checks of
# the base branch, from branch protection and from a ruleset.
required_json() {
  jq -n --argjson c "$1" '{protection: {enabled: true, required_status_checks: {contexts: $c}}}' > "$FAKE_GH/branch.json"
  jq -n --argjson c "$2" '[{type: "required_status_checks",
    parameters: {required_status_checks: [$c[] | {context: .}]}}]' > "$FAKE_GH/rules.json"
}

# devin_status <state>: the Devin Review commit status on the head, as the
# status API gives it. `none` writes no status at all.
devin_status() {
  if [ "$1" = none ]; then printf '{"statuses":[]}\n' > "$FAKE_GH/status.json"; return; fi
  printf '{"statuses":[{"context":"Devin Review","state":"%s"}]}\n' "$1" > "$FAKE_GH/status.json"
}

# ready [<flag>...]: ready.sh on PR 7 as `author`; Devin Review success, no
# check runs, no threads, and no required checks unless written.
ready() {
  [ -f "$FAKE_GH/status.json" ] || [ -f "$FAKE_GH/status.1.json" ] || devin_status success
  [ -f "$FAKE_GH/check-runs.json" ] || printf '{"check_runs":[]}\n' > "$FAKE_GH/check-runs.json"
  [ -f "$FAKE_GH/graphql.json" ] || threads_json '[]'
  [ -f "$FAKE_GH/branch.json" ] || required_json '[]' '[]'
  run bash "$here/../scripts/ready.sh" acme/app 7 --me author "$@"
}

# line <n>: line n of the last run's stdout.
line() { printf '%s\n' "$out" | sed -n "$1p"; }

url="https://github.com/acme/app/pull/7"

t_ready_clean() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "Devin Review: success on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_behind() {
  fake_gh; pr_json pr-view.json BEHIND MERGEABLE "" false "[$ci_green]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "Devin Review: success on abc1234 · open threads: 0 · merge state: BEHIND" "$(line 2)"
}

t_ready_dirty() {
  fake_gh; pr_json pr-view.json DIRTY CONFLICTING "" false "[$ci_green]"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "mergeable is CONFLICTING; merge state is DIRTY" "$(line 2)"
}

t_ready_unknown_then_clean() {
  fake_gh; pr_json pr-view.1.json UNKNOWN UNKNOWN "" false "[$ci_green]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "pr view calls" 2 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_devin_pending() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status pending
  ready
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "Devin Review is PENDING" "$(line 2)"
}

t_ready_thread_waits() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  threads_json '[{"id":"T1","isResolved":false,"path":"a.sh","line":3,"opener":{"nodes":[{"body":"fix this"}]},"latest":{"nodes":[{"author":{"login":"reviewer"},"body":"fix this"}]}}]'
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "1 review thread(s) wait for the author" "$(line 2)"
  eq "line 3" "T1 a.sh:3 last=reviewer :: fix this" "$(line 3)"
}

t_ready_blocked_waiting_approval() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url (waiting for approval)" "$(line 1)"
  eq "line 2" "Devin Review: success on abc1234 · open threads: 0 · merge state: BLOCKED" "$(line 2)"
}

t_ready_blocked_changes_requested() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE CHANGES_REQUESTED false "[$ci_green]"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "changes requested" "$(line 2)"
}

t_ready_blocked_red_check() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_red]"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "1 other check(s) red" "$(line 2)"
}

t_ready_blocked_no_review_rule() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE "" false "[$ci_green]"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "merge state is BLOCKED" "$(line 2)"
}

t_ready_required_check_missing() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green]"
  required_json '["check","build"]' '[]'
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "required check(s) not posted: build" "$(line 2)"
}

t_ready_ruleset_check_missing() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green]"
  required_json '[]' '["check","lint"]'
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "required check(s) not posted: lint" "$(line 2)"
}

t_ready_required_missing_while_pending() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_pending]"
  required_json '["check","build"]' '[]'
  ready
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "1 other check(s) pending; required check(s) not posted: build" "$(line 2)"
}

t_ready_required_checks_posted() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green,$devin_in_rollup]"
  required_json '["check"]' '["Devin Review"]'
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url (waiting for approval)" "$(line 1)"
}

t_ready_slash_base() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  jq '.baseRefName = "release/1.0"' "$FAKE_GH/pr-view.json" > "$FAKE_GH/pr-view.tmp" && mv "$FAKE_GH/pr-view.tmp" "$FAKE_GH/pr-view.json"
  ready
  eq exit 0 "$code"
  eq "branch and rules calls" "api repos/acme/app/branches/release%2F1.0 api repos/acme/app/rules/branches/release%2F1.0" \
    "$(cat "$FAKE_GH/branch.args" "$FAKE_GH/rules.args" | awk '{print $1, $2}' | paste -sd' ' -)"
}

t_ready_draft() {
  fake_gh; pr_json pr-view.json DRAFT MERGEABLE "" true "[$ci_green]"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "draft" "$(line 2)"
}

t_ready_zero_checks() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"; devin_status none
  ready
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "no checks on abc1234 yet; no Devin Review status on abc1234" "$(line 2)"
}

t_ready_zero_checks_no_devin() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"; devin_status none
  ready --no-devin
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "no checks on abc1234 yet" "$(line 2)"
}

t_ready_absent_rollup() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false null; devin_status none
  ready
  eq exit 2 "$code"
  eq "line 2" "no checks on abc1234 yet; no Devin Review status on abc1234" "$(line 2)"
}

t_ready_no_devin_status() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status none
  ready
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "no Devin Review status on abc1234" "$(line 2)"
}

t_ready_no_devin_flag() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status none
  ready --no-devin
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "Devin Review: none on this repo · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_blocked_and_waiting() {
  fake_gh; pr_json pr-view.json DIRTY CONFLICTING "" false "[$ci_green]"; devin_status pending
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "Devin Review is PENDING; mergeable is CONFLICTING; merge state is DIRTY" "$(line 2)"
}

t_ready_bad_flag() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  ready --bogus
  eq exit 64 "$code"
  eq stderr "stop: unknown flag --bogus" "$err"
}

t_ready_devin_check_run() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status none
  printf '{"check_runs":[{"name":"Devin Review","status":"completed","conclusion":"success"}]}\n' > "$FAKE_GH/check-runs.json"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "Devin Review: success on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_wait_success() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  printf '{"statuses":[{"context":"Devin Review","state":"pending"}]}\n' > "$FAKE_GH/status.1.json"
  devin_status success
  ready --wait abc1234def5678 --poll-sec 1
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "status calls" 3 "$(cat "$FAKE_GH/status.calls")"
}

t_ready_wait_none() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status none
  ready --wait abc1234def5678 --none-sec 2 --poll-sec 1
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "no Devin Review status on abc1234" "$(line 2)"
}

t_ready_wait_timeout() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status pending
  ready --wait abc1234def5678 --timeout-sec 2 --poll-sec 1
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "Devin Review is PENDING" "$(line 2)"
}

t_ready_wait_gh_fails() {
  fake_gh; printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/status.fail"
  ready --wait abc1234def5678
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "gh failed: gh: Bad credentials (HTTP 401)" "$(line 2)"
  eq "status calls" 5 "$(cat "$FAKE_GH/status.calls")"
}

t_ready_wait_one_failure() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/status.1.fail"
  devin_status success
  ready --wait abc1234def5678 --poll-sec 1
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "status calls" 3 "$(cat "$FAKE_GH/status.calls")"
}

t_ready_pr_view_fails() {
  fake_gh; printf 'HTTP 502: Bad Gateway\n' > "$FAKE_GH/pr-view.fail"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "gh failed: HTTP 502: Bad Gateway" "$(line 2)"
}

t_ready_wait_none_zero_checks() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"; devin_status none
  ready --wait abc1234def5678 --none-sec 2 --poll-sec 1
  eq exit 2 "$code"
  eq "line 2" "no checks on abc1234 yet; no Devin Review status on abc1234" "$(line 2)"
}

t_ready_required_missing_after_devin() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_in_rollup]"
  required_json '["build"]' '[]'
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "required check(s) not posted: build" "$(line 2)"
}

t_ready_devin_read_whole() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"; devin_status none
  printf '{"check_runs":[{"name":"Devin Review","status":"completed","conclusion":"success"}]}\n' > "$FAKE_GH/check-runs.json"
  ready
  eq exit 0 "$code"
  has "status call reads every page" "--paginate" "$(cat "$FAKE_GH/status.args")"
  has "check runs asked by name" "check_name=Devin%20Review" "$(cat "$FAKE_GH/check-runs.args")"
}

cases=(
  "ready-pr: CLEAN reads READY|t_ready_clean"
  "ready-pr: BEHIND reads READY|t_ready_behind"
  "ready-pr: DIRTY reads BLOCKED|t_ready_dirty"
  "ready-pr: UNKNOWN then CLEAN reads READY|t_ready_unknown_then_clean"
  "ready-pr: Devin pending reads WAITING|t_ready_devin_pending"
  "ready-pr: a thread waiting for the author reads BLOCKED with its line|t_ready_thread_waits"
  "ready-pr: BLOCKED waiting for approval reads READY|t_ready_blocked_waiting_approval"
  "ready-pr: BLOCKED with changes requested reads BLOCKED|t_ready_blocked_changes_requested"
  "ready-pr: BLOCKED with a red check reads BLOCKED|t_ready_blocked_red_check"
  "ready-pr: BLOCKED with no review rule reads BLOCKED|t_ready_blocked_no_review_rule"
  "ready-pr: a required check not posted reads BLOCKED|t_ready_required_check_missing"
  "ready-pr: a ruleset check not posted reads BLOCKED|t_ready_ruleset_check_missing"
  "ready-pr: a required check not posted while a check runs reads WAITING|t_ready_required_missing_while_pending"
  "ready-pr: required checks all posted reads READY (waiting for approval)|t_ready_required_checks_posted"
  "ready-pr: a base with a slash is encoded in the required checks calls|t_ready_slash_base"
  "ready-pr: a draft reads BLOCKED|t_ready_draft"
  "ready-pr: zero checks reads WAITING|t_ready_zero_checks"
  "ready-pr: zero checks under --no-devin reads WAITING|t_ready_zero_checks_no_devin"
  "ready-pr: an absent rollup is zero checks|t_ready_absent_rollup"
  "ready-pr: no Devin Review status reads WAITING|t_ready_no_devin_status"
  "ready-pr: --no-devin with green checks reads READY|t_ready_no_devin_flag"
  "ready-pr: a blocked and a waiting reason read BLOCKED|t_ready_blocked_and_waiting"
  "ready-pr: an unknown flag stops with exit 64|t_ready_bad_flag"
  "ready-pr: a Devin Review check run reads READY|t_ready_devin_check_run"
  "ready-pr: --wait waits for success, then READY|t_ready_wait_success"
  "ready-pr: --wait with no status reads WAITING|t_ready_wait_none"
  "ready-pr: --wait past the timeout reads WAITING|t_ready_wait_timeout"
  "ready-pr: --wait stops BLOCKED after 5 failed calls|t_ready_wait_gh_fails"
  "ready-pr: --wait goes on after one failed call|t_ready_wait_one_failure"
  "ready-pr: a failed pr view reads BLOCKED|t_ready_pr_view_fails"
  "ready-pr: --wait with no checks at all names the missing Devin status|t_ready_wait_none_zero_checks"
  "ready-pr: a required check not posted after Devin success reads BLOCKED|t_ready_required_missing_after_devin"
  "ready-pr: Devin Review is read across pages and by name|t_ready_devin_read_whole"
)
