# ready.sh: the cases for this skill's ready.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Items of a status check rollup, as `gh pr view` gives them.
ci_green='{"__typename":"CheckRun","name":"check","status":"COMPLETED","conclusion":"SUCCESS"}'
ci_red='{"__typename":"CheckRun","name":"check","status":"COMPLETED","conclusion":"FAILURE"}'
devin_ok='{"__typename":"StatusContext","context":"Devin Review","state":"SUCCESS"}'
devin_pending='{"__typename":"StatusContext","context":"Devin Review","state":"PENDING"}'

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

# ready [<flag>...]: ready.sh on PR 7 as `author`; no threads and no required
# checks unless written.
ready() {
  [ -f "$FAKE_GH/graphql.json" ] || threads_json '[]'
  [ -f "$FAKE_GH/branch.json" ] || required_json '[]' '[]'
  run bash "$here/../scripts/ready.sh" acme/app 7 --me author "$@"
}

last() { printf '%s\n' "$out" | tail -1; }

t_ready_clean() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$devin_ok]"
  ready
  eq exit 0 "$code"
  eq "last line" "READY https://github.com/acme/app/pull/7" "$(last)"
}

t_ready_behind() {
  fake_gh; pr_json pr-view.json BEHIND MERGEABLE "" false "[$ci_green,$devin_ok]"
  ready
  eq exit 0 "$code"
  eq "last line" "READY https://github.com/acme/app/pull/7" "$(last)"
}

t_ready_dirty() {
  fake_gh; pr_json pr-view.json DIRTY CONFLICTING "" false "[$ci_green,$devin_ok]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: mergeable is CONFLICTING; merge state is DIRTY" "$(last)"
}

t_ready_unknown_then_clean() {
  fake_gh; pr_json pr-view.1.json UNKNOWN UNKNOWN "" false "[$ci_green,$devin_ok]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$devin_ok]"
  ready
  eq exit 0 "$code"
  eq "last line" "READY https://github.com/acme/app/pull/7" "$(last)"
  eq "pr view calls" 2 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_devin_pending() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$devin_pending]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: Devin Review is PENDING" "$(last)"
}

t_ready_thread_waits() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$devin_ok]"
  threads_json '[{"id":"T1","isResolved":false,"path":"a.sh","line":3,"opener":{"nodes":[{"body":"fix this"}]},"latest":{"nodes":[{"author":{"login":"reviewer"},"body":"fix this"}]}}]'
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: 1 review thread(s) wait for the author" "$(last)"
}

t_ready_blocked_waiting_approval() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green,$devin_ok]"
  ready
  eq exit 0 "$code"
  eq "last line" "READY https://github.com/acme/app/pull/7 (waiting for approval)" "$(last)"
}

t_ready_blocked_changes_requested() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE CHANGES_REQUESTED false "[$ci_green,$devin_ok]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: changes requested" "$(last)"
}

t_ready_blocked_red_check() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_red,$devin_ok]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: 1 other check(s) red" "$(last)"
}

t_ready_blocked_no_review_rule() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE "" false "[$ci_green,$devin_ok]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: merge state is BLOCKED" "$(last)"
}

t_ready_required_check_missing() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green,$devin_ok]"
  required_json '["check","build"]' '[]'
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: required check(s) not posted: build" "$(last)"
}

t_ready_ruleset_check_missing() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green,$devin_ok]"
  required_json '[]' '["check","lint"]'
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: required check(s) not posted: lint" "$(last)"
}

t_ready_required_checks_posted() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green,$devin_ok]"
  required_json '["check"]' '["Devin Review"]'
  ready
  eq exit 0 "$code"
  eq "last line" "READY https://github.com/acme/app/pull/7 (waiting for approval)" "$(last)"
}

t_ready_slash_base() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$devin_ok]"
  jq '.baseRefName = "release/1.0"' "$FAKE_GH/pr-view.json" > "$FAKE_GH/pr-view.tmp" && mv "$FAKE_GH/pr-view.tmp" "$FAKE_GH/pr-view.json"
  ready
  eq exit 0 "$code"
  eq "branch and rules calls" "api repos/acme/app/branches/release%2F1.0 api repos/acme/app/rules/branches/release%2F1.0" \
    "$(cat "$FAKE_GH/branch.args" "$FAKE_GH/rules.args" | awk '{print $1, $2}' | paste -sd' ' -)"
}

t_ready_draft() {
  fake_gh; pr_json pr-view.json DRAFT MERGEABLE "" true "[$ci_green,$devin_ok]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: draft" "$(last)"
}

t_ready_zero_checks() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: no checks on abc1234 yet" "$(last)"
}

t_ready_zero_checks_no_devin() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"
  ready --no-devin
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: no checks on abc1234 yet" "$(last)"
}

t_ready_absent_rollup() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false null
  ready
  eq exit 1 "$code"
  eq "last line" "NOT READY https://github.com/acme/app/pull/7: no checks on abc1234 yet" "$(last)"
}

cases=(
  "ready-pr: CLEAN reads READY|t_ready_clean"
  "ready-pr: BEHIND reads READY|t_ready_behind"
  "ready-pr: DIRTY reads NOT READY|t_ready_dirty"
  "ready-pr: UNKNOWN then CLEAN reads READY|t_ready_unknown_then_clean"
  "ready-pr: Devin pending reads NOT READY|t_ready_devin_pending"
  "ready-pr: a thread waiting for the author reads NOT READY|t_ready_thread_waits"
  "ready-pr: BLOCKED waiting for approval reads READY|t_ready_blocked_waiting_approval"
  "ready-pr: BLOCKED with changes requested reads NOT READY|t_ready_blocked_changes_requested"
  "ready-pr: BLOCKED with a red check reads NOT READY|t_ready_blocked_red_check"
  "ready-pr: BLOCKED with no review rule reads NOT READY|t_ready_blocked_no_review_rule"
  "ready-pr: a required check not posted reads NOT READY|t_ready_required_check_missing"
  "ready-pr: a ruleset check not posted reads NOT READY|t_ready_ruleset_check_missing"
  "ready-pr: required checks all posted reads READY (waiting for approval)|t_ready_required_checks_posted"
  "ready-pr: a base with a slash is encoded in the required checks calls|t_ready_slash_base"
  "ready-pr: a draft reads NOT READY|t_ready_draft"
  "ready-pr: zero checks reads NOT READY|t_ready_zero_checks"
  "ready-pr: zero checks under --no-devin reads NOT READY|t_ready_zero_checks_no_devin"
  "ready-pr: an absent rollup is zero checks|t_ready_absent_rollup"
)
