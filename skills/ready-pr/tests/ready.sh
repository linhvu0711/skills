# ready.sh: the cases for this skill's ready.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Items of a status check rollup, as `gh pr view` gives them.
ci_green='{"__typename":"CheckRun","name":"check","status":"COMPLETED","conclusion":"SUCCESS"}'
ci_red='{"__typename":"CheckRun","name":"check","status":"COMPLETED","conclusion":"FAILURE"}'
ci_pending='{"__typename":"CheckRun","name":"check","status":"IN_PROGRESS","conclusion":null}'
# Review bots post into the rollup like CI: Devin Review as a commit status,
# Cursor Bugbot as a check run.
devin_green='{"__typename":"StatusContext","context":"Devin Review","state":"SUCCESS"}'
devin_pending='{"__typename":"StatusContext","context":"Devin Review","state":"PENDING"}'
bugbot_running='{"__typename":"CheckRun","name":"Cursor Bugbot","status":"IN_PROGRESS","conclusion":null}'
bugbot_neutral='{"__typename":"CheckRun","name":"Cursor Bugbot","status":"COMPLETED","conclusion":"NEUTRAL"}'
bugbot_red='{"__typename":"CheckRun","name":"Cursor Bugbot","status":"COMPLETED","conclusion":"FAILURE"}'

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

# ready [<flag>...]: ready.sh on PR 7 as `author`, with no threads and no
# required checks unless written.
ready() {
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
  eq "line 2" "checks: 1 green on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_behind() {
  fake_gh; pr_json pr-view.json BEHIND MERGEABLE "" false "[$ci_green]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "checks: 1 green on abc1234 · open threads: 0 · merge state: BEHIND" "$(line 2)"
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

t_ready_bot_pending() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$devin_pending]"
  ready
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "1 check(s) pending: Devin Review" "$(line 2)"
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
  eq "line 2" "checks: 1 green on abc1234 · open threads: 0 · merge state: BLOCKED" "$(line 2)"
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
  eq "line 2" "1 check(s) red: check" "$(line 2)"
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
  eq "line 2" "1 check(s) pending: check; required check(s) not posted: build" "$(line 2)"
}

t_ready_required_checks_posted() {
  fake_gh; pr_json pr-view.json BLOCKED MERGEABLE REVIEW_REQUIRED false "[$ci_green,$devin_green]"
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
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"
  ready
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "no checks on abc1234 yet" "$(line 2)"
}

t_ready_absent_rollup() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false null
  ready
  eq exit 2 "$code"
  eq "line 2" "no checks on abc1234 yet" "$(line 2)"
}

t_ready_blocked_and_waiting() {
  fake_gh; pr_json pr-view.json DIRTY CONFLICTING "" false "[$ci_green,$devin_pending]"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "mergeable is CONFLICTING; merge state is DIRTY; 1 check(s) pending: Devin Review" "$(line 2)"
}

t_ready_bad_flag() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  ready --bogus
  eq exit 64 "$code"
  eq stderr "stop: unknown flag --bogus" "$err"
}

t_ready_tools_flag_gone() {
  # Given: the fake gh
  fake_gh
  # When
  ready --tools devin
  # Then
  eq exit 64 "$code"
  eq stderr "stop: unknown flag --tools" "$err"
}

t_ready_bot_check_counts() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$bugbot_neutral]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "checks: 2 green on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_wait_bot_then_ready() {
  # Given: Cursor Bugbot runs for two polls, then ends neutral
  fake_gh
  pr_json pr-view.1.json CLEAN MERGEABLE "" false "[$bugbot_running]"
  pr_json pr-view.2.json CLEAN MERGEABLE "" false "[$bugbot_running]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$bugbot_neutral]"
  # When
  ready --wait abc1234def5678 --poll-sec 1
  # Then
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "checks: 1 green on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_wait_settles_first() {
  # Given: a sleep that writes each argument; one green check
  fake_gh
  printf '#!/usr/bin/env bash\necho "$1" >> "%s/sleep.args"\n' "$T" > "$T/bin/sleep"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  # When
  ready --wait abc1234def5678 --settle-sec 7 --poll-sec 1
  # Then
  eq "first sleep" 7 "$(head -1 "$T/sleep.args")"
}

t_ready_wait_settle_default() {
  fake_gh
  printf '#!/usr/bin/env bash\necho "$1" >> "%s/sleep.args"\n' "$T" > "$T/bin/sleep"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  ready --wait abc1234def5678
  eq "first sleep" 60 "$(head -1 "$T/sleep.args")"
}

t_ready_wait_stops_on_red() {
  # Given: Cursor Bugbot red while the test check still runs
  fake_gh
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$bugbot_red,{\"__typename\":\"CheckRun\",\"name\":\"test\",\"status\":\"IN_PROGRESS\",\"conclusion\":null}]"
  # When
  ready --wait abc1234def5678 --poll-sec 1
  # Then
  eq exit 1 "$code"
  eq "line 2" "1 check(s) red: Cursor Bugbot; 1 check(s) pending: test" "$(line 2)"
  eq "pr view calls" 2 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_wait_timeout() {
  # Given: Devin Review pending on every poll
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_pending]"
  # When
  ready --wait abc1234def5678 --timeout-sec 2 --poll-sec 1
  # Then
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "1 check(s) pending: Devin Review" "$(line 2)"
}

t_ready_wait_zero_checks() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[]"
  ready --wait abc1234def5678 --poll-sec 1
  eq exit 2 "$code"
  eq "line 2" "no checks on abc1234 yet" "$(line 2)"
  eq "pr view calls" 2 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_wait_head_moved() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_pending]"
  ready --wait 0000000aaaaaaa --poll-sec 1
  eq exit 2 "$code"
  eq "pr view calls" 2 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_wait_gh_fails() {
  fake_gh; printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/pr-view.fail"
  ready --wait abc1234def5678
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "gh failed: gh: Bad credentials (HTTP 401)" "$(line 2)"
  eq "pr view calls" 5 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_wait_one_failure() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/pr-view.1.fail"
  ready --wait abc1234def5678 --poll-sec 1
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "pr view calls" 3 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_pr_view_fails() {
  fake_gh; printf 'HTTP 502: Bad Gateway\n' > "$FAKE_GH/pr-view.fail"
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "gh failed: HTTP 502: Bad Gateway" "$(line 2)"
}

t_ready_required_missing_after_bot() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_green]"
  required_json '["build"]' '[]'
  ready
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "required check(s) not posted: build" "$(line 2)"
}

cases=(
  "ready-pr: CLEAN reads READY|t_ready_clean"
  "ready-pr: BEHIND reads READY|t_ready_behind"
  "ready-pr: DIRTY reads BLOCKED|t_ready_dirty"
  "ready-pr: UNKNOWN then CLEAN reads READY|t_ready_unknown_then_clean"
  "ready-pr: a review bot's pending check reads WAITING with its name|t_ready_bot_pending"
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
  "ready-pr: an absent rollup is zero checks|t_ready_absent_rollup"
  "ready-pr: a blocked and a waiting reason read BLOCKED|t_ready_blocked_and_waiting"
  "ready-pr: an unknown flag stops with exit 64|t_ready_bad_flag"
  "ready-pr: --tools is an unknown flag|t_ready_tools_flag_gone"
  "ready-pr: a review bot's check run counts like any check|t_ready_bot_check_counts"
  "ready-pr: --wait waits for a bot check, then READY|t_ready_wait_bot_then_ready"
  "ready-pr: --wait sleeps the settle time first|t_ready_wait_settles_first"
  "ready-pr: --wait settles 60 seconds by default|t_ready_wait_settle_default"
  "ready-pr: --wait stops on a red check|t_ready_wait_stops_on_red"
  "ready-pr: --wait past the timeout names the pending check|t_ready_wait_timeout"
  "ready-pr: --wait with zero checks after the settle reads WAITING|t_ready_wait_zero_checks"
  "ready-pr: --wait stops when the head moved|t_ready_wait_head_moved"
  "ready-pr: --wait stops BLOCKED after 5 failed calls|t_ready_wait_gh_fails"
  "ready-pr: --wait goes on after one failed call|t_ready_wait_one_failure"
  "ready-pr: a failed pr view reads BLOCKED|t_ready_pr_view_fails"
  "ready-pr: a required check not posted after a bot's green reads BLOCKED|t_ready_required_missing_after_bot"
)
