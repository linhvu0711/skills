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

t_ready_gh_hint() {
  # Given: a clean PR; gh prints a hint on stderr beside its answer
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  printf '%s\n' 'hint: if you need to wait for this pull request to be reviewed, merged, or closed before continuing, use this instead of polling:' > "$FAKE_GH/pr-view.stderr"
  # When
  ready
  # Then
  eq "line 1" "READY $url" "$(line 1)"
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

t_ready_rules_need_pro() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  required_json '[]' '[]'
  printf '%s\n' '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' > "$FAKE_GH/rules.fail"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
}

t_ready_rules_need_team() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  required_json '[]' '[]'
  printf '%s\n' 'gh: Upgrade to GitHub Team or make this repository public to enable this feature. (HTTP 403)' > "$FAKE_GH/rules.fail"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
}

t_ready_rules_fail() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  required_json '[]' '[]'
  printf 'HTTP 502: Bad Gateway\n' > "$FAKE_GH/rules.fail"
  ready
  eq exit 1 "$code"
  eq "line 2" "gh failed: HTTP 502: Bad Gateway" "$(line 2)"
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

t_ready_bot_check_counts() {
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green,$bugbot_neutral]"
  ready
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "checks: 2 green on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

t_ready_watch_bot_then_ready() {
  # Given: Cursor Bugbot runs for two polls, then ends neutral
  fake_gh
  pr_json pr-view.1.json CLEAN MERGEABLE "" false "[$bugbot_running]"
  pr_json pr-view.2.json CLEAN MERGEABLE "" false "[$bugbot_running]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$bugbot_neutral]"
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "line 2" "checks: 1 green on abc1234 · open threads: 0 · merge state: CLEAN" "$(line 2)"
}

# real_sleep: the real sleep in place of fake_gh's no-op one, for a case
# whose watch must reach its limit, which counts real time.
real_sleep() { ln -sf /bin/sleep "$T/bin/sleep"; }

net_err='error connecting to api.github.com'

t_ready_watch_timeout() {
  # Given: Devin Review pending on every poll
  fake_gh; real_sleep; pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_pending]"
  # When
  ready --watch abc1234def5678 --settle-sec 0 --timeout-sec 2 --poll-sec 1
  # Then
  eq exit 2 "$code"
  eq "line 1" "WAITING $url" "$(line 1)"
  eq "line 2" "1 check(s) pending: Devin Review" "$(line 2)"
}

t_ready_watch_six_failures() {
  # Given: one green check, and the first six pr view calls fail on the network
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  for n in 1 2 3 4 5 6; do printf '%s\n' "$net_err" > "$FAKE_GH/pr-view.$n.fail"; done
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
}

t_ready_watch_outage_limit() {
  # Given: every pr view call fails on the network
  fake_gh; real_sleep; printf '%s\n' "$net_err" > "$FAKE_GH/pr-view.fail"
  # When
  ready --watch abc1234def5678 --settle-sec 0 --poll-sec 1 --timeout-sec 2
  # Then
  eq exit 1 "$code"
  eq "line 1" "BLOCKED $url" "$(line 1)"
  eq "line 2" "gh failed: $net_err; still failing when the watch's 2 s limit passed" "$(line 2)"
}

t_ready_watch_login_expired() {
  # Given: the six-failures case, with every pr view call refused for its login
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  printf 'gh: Bad credentials (HTTP 401)\n' > "$FAKE_GH/pr-view.fail"
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq "line 2" "gh failed: gh: Bad credentials (HTTP 401)" "$(line 2)"
  eq "pr view calls" 1 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_watch_verdict_read_fails() {
  # Given: one green check; the first read after the watch fails on the network
  fake_gh; pr_json pr-view.json CLEAN MERGEABLE "" false "[$ci_green]"
  printf '%s\n' "$net_err" > "$FAKE_GH/pr-view.2.fail"
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq exit 0 "$code"
  eq "line 1" "READY $url" "$(line 1)"
  eq "pr view calls" 3 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_watch_settle_counts() {
  # Given: Devin Review pending on every poll
  fake_gh; real_sleep; pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_pending]"
  # When
  ready --watch abc1234def5678 --settle-sec 2 --poll-sec 1 --timeout-sec 2
  # Then: one poll after the settle wait used the limit, then the verdict read
  eq exit 2 "$code"
  eq "pr view calls" 2 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_watch_wait_ends_at_limit() {
  # Given: a real sleep that writes each argument; Devin Review pending on every poll
  fake_gh
  printf '#!/usr/bin/env bash\necho "$1" >> "%s/sleep.args"\nexec /bin/sleep "$1"\n' "$T" > "$T/bin/sleep"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_pending]"
  # When
  ready --watch abc1234def5678 --settle-sec 0 --poll-sec 10 --timeout-sec 3
  # Then: the wait after the first poll is the time left, not --poll-sec
  eq "first wait within the limit" yes "$([ "$(sed -n 2p "$T/sleep.args")" -le 3 ] && echo yes || echo no)"
}

t_ready_watch_poll_leading_zero() {
  # Given: a sleep that writes each argument; Devin Review pending, then green
  fake_gh
  printf '#!/usr/bin/env bash\necho "$1" >> "%s/sleep.args"\n' "$T" > "$T/bin/sleep"
  pr_json pr-view.1.json CLEAN MERGEABLE "" false "[$devin_pending]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_green]"
  # When
  ready --watch abc1234def5678 --settle-sec 0 --poll-sec 08
  # Then
  eq "wait after the first poll" 8 "$(sed -n 2p "$T/sleep.args")"
}

# check_run <name> <status> <conclusion> <url> [<workflow>]: one check run of the rollup.
check_run() {
  jq -cn --arg n "$1" --arg s "$2" --arg c "$3" --arg u "$4" --arg w "${5:-}" \
    '{__typename: "CheckRun", name: $n, status: $s, conclusion: (if $c == "" then null else $c end), detailsUrl: $u, workflowName: $w}'
}

# job_json <failed step>: an Actions job answer with one green and one failed step.
job_json() {
  jq -n --arg f "$1" '{id: 22, steps: [{name: "Set up", conclusion: "success"}, {name: $f, conclusion: "failure"}]}' > "$FAKE_GH/job.json"
}

job22="https://github.com/acme/app/actions/runs/11/job/22"
job33="https://github.com/acme/app/actions/runs/11/job/33"

t_ready_watch_red_with_step() {
  # Given: test is red on two polls while Devin Review runs, then Devin Review ends green
  fake_gh; job_json "Run tests"
  red="$(check_run test COMPLETED FAILURE "$job22" CI)"
  pr_json pr-view.1.json CLEAN MERGEABLE "" false "[$red,$devin_pending]"
  pr_json pr-view.2.json CLEAN MERGEABLE "" false "[$red,$devin_pending]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$red,$devin_green]"
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq exit 1 "$code"
  eq "line 1" "RED test · workflow CI · step Run tests · FAILURE · $job22" "$(line 1)"
  eq "line 2" "BLOCKED $url" "$(line 2)"
  eq "line 3" "1 check(s) red: test" "$(line 3)"
  eq "job calls" 1 "$(cat "$FAKE_GH/job.calls")"
}

t_ready_watch_new_thread() {
  # Given: no thread on the first poll, then one; Devin Review runs, then ends green
  fake_gh
  jq -n '{data: {repository: {pullRequest: {reviewThreads:
    {pageInfo: {hasNextPage: false, endCursor: null}, nodes: []}}}}}' > "$FAKE_GH/graphql.1.json"
  threads_json '[{"id":"T1","isResolved":false,"path":"a.sh","line":3,"opener":{"nodes":[{"body":"fix this"}]},"latest":{"nodes":[{"author":{"login":"reviewer"},"body":"fix this"}]}}]'
  pr_json pr-view.1.json CLEAN MERGEABLE "" false "[$devin_pending]"
  pr_json pr-view.2.json CLEAN MERGEABLE "" false "[$devin_pending]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$devin_green]"
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq exit 1 "$code"
  eq "line 1" "THREAD T1 a.sh:3 last=reviewer :: fix this" "$(line 1)"
  eq "line 2" "BLOCKED $url" "$(line 2)"
  eq "line 3" "1 review thread(s) wait for the author" "$(line 3)"
  eq "line 4" "T1 a.sh:3 last=reviewer :: fix this" "$(line 4)"
}

t_ready_watch_past_red() {
  # Given: Cursor Bugbot red while the test check still runs, then test ends green
  fake_gh
  pr_json pr-view.1.json CLEAN MERGEABLE "" false "[$bugbot_red,{\"__typename\":\"CheckRun\",\"name\":\"test\",\"status\":\"IN_PROGRESS\",\"conclusion\":null}]"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$bugbot_red,$ci_green]"
  # When
  ready --watch abc1234def5678 --poll-sec 1
  # Then
  eq exit 1 "$code"
  eq "line 1" "RED Cursor Bugbot · workflow - · step - · FAILURE · -" "$(line 1)"
  eq "line 3" "1 check(s) red: Cursor Bugbot" "$(line 3)"
  eq "pr view calls" 3 "$(cat "$FAKE_GH/pr-view.calls")"
}

t_ready_watch_red_when_threads_fail() {
  # Given: test is red while Devin Review runs, and the thread list fails on every poll
  fake_gh; real_sleep; job_json "Run tests"
  printf 'HTTP 502: Bad Gateway\n' > "$FAKE_GH/graphql.fail"
  pr_json pr-view.json CLEAN MERGEABLE "" false "[$(check_run test COMPLETED FAILURE "$job22" CI),$devin_pending]"
  # When
  ready --watch abc1234def5678 --settle-sec 0 --poll-sec 1 --timeout-sec 2
  # Then
  eq "line 1" "RED test · workflow CI · step Run tests · FAILURE · $job22" "$(line 1)"
  eq "line 2" "BLOCKED $url" "$(line 2)"
  eq "line 3" "gh failed: HTTP 502: Bad Gateway; still failing when the watch's 2 s limit passed" "$(line 3)"
}

cases=(
  "ready-pr: CLEAN reads READY|t_ready_clean"
  "ready-pr: a gh hint on stderr still reads READY|t_ready_gh_hint"
  "ready-pr: BEHIND reads READY|t_ready_behind"
  "ready-pr: DIRTY reads BLOCKED|t_ready_dirty"
  "ready-pr: a review bot's pending check reads WAITING with its name|t_ready_bot_pending"
  "ready-pr: a thread waiting for the author reads BLOCKED with its line|t_ready_thread_waits"
  "ready-pr: BLOCKED waiting for approval reads READY|t_ready_blocked_waiting_approval"
  "ready-pr: BLOCKED with changes requested reads BLOCKED|t_ready_blocked_changes_requested"
  "ready-pr: BLOCKED with a red check reads BLOCKED|t_ready_blocked_red_check"
  "ready-pr: BLOCKED with no review rule reads BLOCKED|t_ready_blocked_no_review_rule"
  "ready-pr: a required check not posted reads BLOCKED|t_ready_required_check_missing"
  "ready-pr: a ruleset check not posted reads BLOCKED|t_ready_ruleset_check_missing"
  "ready-pr: required checks all posted reads READY (waiting for approval)|t_ready_required_checks_posted"
  "ready-pr: a base with a slash is encoded in the required checks calls|t_ready_slash_base"
  "ready-pr: no rulesets on a free private repo reads READY|t_ready_rules_need_pro"
  "ready-pr: no rulesets on a free organization's private repo reads READY|t_ready_rules_need_team"
  "ready-pr: a failed rules call reads BLOCKED|t_ready_rules_fail"
  "ready-pr: a draft reads BLOCKED|t_ready_draft"
  "ready-pr: zero checks reads WAITING|t_ready_zero_checks"
  "ready-pr: an absent rollup is zero checks|t_ready_absent_rollup"
  "ready-pr: a review bot's check run counts like any check|t_ready_bot_check_counts"
  "ready-pr: --watch waits for a bot check, then READY|t_ready_watch_bot_then_ready"
  "ready-pr: --watch past the timeout names the pending check|t_ready_watch_timeout"
  "ready-pr: --watch goes on through six failed calls|t_ready_watch_six_failures"
  "ready-pr: --watch stops at its limit while gh keeps failing|t_ready_watch_outage_limit"
  "ready-pr: --watch stops at once on an expired login|t_ready_watch_login_expired"
  "ready-pr: --watch reads the verdict again after a failed read|t_ready_watch_verdict_read_fails"
  "ready-pr: --watch counts the settle time in its limit|t_ready_watch_settle_counts"
  "ready-pr: --watch waits no longer than the time left|t_ready_watch_wait_ends_at_limit"
  "ready-pr: --poll-sec 08 reads as 8 seconds|t_ready_watch_poll_leading_zero"
  "ready-pr: --watch prints a red check with its workflow and failed step, once|t_ready_watch_red_with_step"
  "ready-pr: --watch prints a new thread when it appears|t_ready_watch_new_thread"
  "ready-pr: --watch goes on past a red check until none is pending|t_ready_watch_past_red"
  "ready-pr: --watch prints a red check when the thread list fails|t_ready_watch_red_when_threads_fail"
)
