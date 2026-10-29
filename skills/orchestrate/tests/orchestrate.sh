# orchestrate.sh: the cases for this skill's orchestrate.sh, the check script and the
# one writer of a run's state file, seen through the fake gh and a fake t3.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The orchestrator script.
F="$here/../scripts/orchestrate.sh"

# fs_setup: a fresh temp folder T, the fake gh (its `repo view` names main),
# one checkout of acme/app at $T/dev/app, and a fake t3 in $T/bin. t3's
# `thread list` prints $T/t3-threads.json, or fails with the text of
# $T/t3.fail when that file exists. Issues go in with fs_issue.
fs_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"defaultBranchRef":{"name":"main"}}\n' > "$FAKE_GH/repo-view.json"
  git init -q -b main "$T/dev/app"
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/dev/app" remote add origin https://github.com/acme/app.git
  cat > "$T/bin/t3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "thread list") if [ -e "$FAKE_T3_DIR/t3.fail" ]; then cat "$FAKE_T3_DIR/t3.fail" >&2; exit 1; fi; cat "$FAKE_T3_DIR/t3-threads.json" ;;
  *) printf 'fake t3: no route for %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$T/bin/t3"
  echo '[]' > "$T/t3-threads.json"
  mkdir -p "$T/issues"
  export FAKE_T3_DIR="$T"
}

# fs_issue <n> <state> <labels> [blocked-by] [prs] [subs] [title]: issue #n
# in the GraphQL answer. <labels> is a JSON list of names; the rest are JSON
# lists of nodes, empty when left out. The title is "Export orders" unless
# given. decide.sh's `issue view` gets the same issue.
fs_issue() {
  local title="${7:-Export orders}"
  jq -cn --argjson n "$1" --arg s "$2" --argjson l "$3" --argjson b "${4:-[]}" \
    --argjson p "${5:-[]}" --argjson u "${6:-[]}" --arg t "$title" \
    '{number: $n, title: $t, state: $s, createdAt: "2026-10-01T00:00:00Z",
      labels: {nodes: [$l[] | {name: .}]}, subIssues: {nodes: $u},
      blockedBy: {nodes: $b}, closedByPullRequestsReferences: {nodes: $p}}' > "$T/issues/$1.json"
  jq -s '{data: {repository: (map({key: "i\(.number)", value: .}) | from_entries)}}' "$T/issues"/*.json > "$FAKE_GH/graphql.json"
  jq -c '{number, title, state, labels: .labels.nodes, subIssues}' "$T/issues/$1.json" > "$FAKE_GH/issue-view.json"
}

# fs_go <args...>: orchestrate.sh from T, inside T3 Code, with the search root,
# the repo map, and the orchestrator home inside T.
fs_go() {
  cd "$T"
  run env T3CODE_CLI_PATH="$T/bin/t3" KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" \
    ORCHESTRATE_HOME="$T/orchestrate" bash "$F" "$@"
}

# fs_start <n>...: a run of these issues, named after the first.
fs_start() {
  fs_go start acme/app --name "#$1" --thread f1 --env e1 "$@"
  eq "start exit" 0 "$code"
}

# fs_state [jq flags] <jq>: the jq filter on the newest run's state file.
fs_state() { jq -c "$@" "$(ls -1d "$T"/orchestrate/acme-app/*/ | sort | tail -1)state.json"; }

# fs_run: the newest run's folder, with no slash at the end.
fs_run() { ls -1d "$T"/orchestrate/acme-app/*/ | sort | tail -1 | sed 's#/$##'; }

# fs_board [jq flags] <jq>: the jq filter on the newest run's board.json.
fs_board() { jq -c "$@" "$(fs_run)/board.json"; }

t_fs_start_writes_run() {
  # Given: #42 "Export orders", open, size/L
  fs_setup; fs_issue 42 OPEN '["size/L"]'
  # When
  fs_go start acme/app --name "#42" --thread f1 --env e1 42
  # Then
  eq exit 0 "$code"
  eq runs 1 "$(ls -1 "$T/orchestrate/acme-app" | wc -l | tr -d ' ')"
  eq state '{"set":[42],"status":"running","every":5,"threads":[]}' "$(fs_state '{set, status, every: .timer.every, threads}')"
}

t_fs_ticket_starts_ship_ready() {
  # Given: a run of #42, open, size/L, no blocker, no PR
  fs_setup; fs_issue 42 OPEN '["size/L"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"command":"ship-ready","command_from":"set","model":"opus","model_from":"default","effort":"high","effort_from":"default"' "$out"
  has stdout '"message":"/ship-ready https://github.com/acme/app/issues/42","thread_title":"i42 Export orders","runtime_mode":"auto"' "$out"
}

t_fs_second_check_starts_nothing() {
  # Given: a run of #42, size/L, checked once
  fs_setup; fs_issue 42 OPEN '["size/L"]'; fs_start 42
  fs_go check acme/app
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  eq threads '[{"number":42,"stage":"ticket","status":"pending"}]' "$(fs_state '[.threads[] | {number, stage, status}]')"
}

t_fs_recorded_thread_not_again() {
  # Given: #42's ticket thread t42 started and running
  fs_setup; fs_issue 42 OPEN '["size/L"]'; fs_start 42
  fs_go check acme/app
  fs_go started acme/app 42 ticket t42 "[i42 Export orders](t3-thread://v1/t42)"
  eq "started exit" 0 "$code"
  echo '[{"threadId":"t42","status":"running"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"thread":"t42","thread_status":"running"' "$out"
}

# fs_at <iso>: the run's start time, set by hand so a PR's date is before or
# after it.
fs_at() {
  local f; f="$(ls -1d "$T"/orchestrate/acme-app/*/ | sort | tail -1)state.json"
  jq --arg at "$1" '.started_at = $at' "$f" > "$f.new" && mv "$f.new" "$f"
}

# fs_record <n> <stage> <thread> [command] [at]: a started thread record, as
# `started` writes, with the command and claim time a check gives it.
fs_record() {
  local f; f="$(ls -1d "$T"/orchestrate/acme-app/*/ | sort | tail -1)state.json"
  jq --argjson n "$1" --arg s "$2" --arg id "$3" --arg cmd "${4:-}" --arg at "${5:-}" \
    '.threads += [{number: $n, stage: $s, thread: $id, link: "[i\($n)](t3-thread://v1/\($id))", status: "started", why: null}
      + (if $cmd == "" then {} else {command: $cmd} end) + (if $at == "" then {} else {at: $at} end)]' \
    "$f" > "$f.new" && mv "$f.new" "$f"
}

# fs_prs <node>...: decide.sh's GraphQL answer for #42's closing PRs, kept in
# the same graphql.json as the issues.
fs_prs() {
  jq --argjson p "[$(IFS=,; printf '%s' "$*")]" '.data.repository.issue = {closedByPullRequestsReferences: {nodes: $p}}' \
    "$FAKE_GH/graphql.json" > "$FAKE_GH/graphql.new" && mv "$FAKE_GH/graphql.new" "$FAKE_GH/graphql.json"
}

t_fs_seed_starts_grill() {
  # Given: a run of #42, open, labelled seed
  fs_setup; fs_issue 42 OPEN '["seed"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"grill","command_from":"set","model":"opus","model_from":"default","effort":"high"' "$out"
  has stdout '"message":"/grill https://github.com/acme/app/issues/42"' "$out"
}

t_fs_bug_starts_triage() {
  # Given: a run of #42, open, labelled bug
  fs_setup; fs_issue 42 OPEN '["bug"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"triage"' "$out"
  has stdout '"message":"/triage https://github.com/acme/app/issues/42"' "$out"
}

t_fs_old_pr_starts_ready_pr() {
  # Given: a run from 2026-10-28T12:00:00Z; #42 size/S with open PR 43 from the day before
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-27T09:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$pr]"; fs_prs "$pr"; fs_start 42; fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"ready-pr"' "$out"
  has stdout '"message":"/ready-pr https://github.com/acme/app/pull/43"' "$out"
  has stdout '"stage":"pr"' "$out"
}

t_fs_new_pr_starts_nothing() {
  # Given: a run from 2026-10-28T12:00:00Z; #42's ticket thread t42 opened PR 43 at 13:00
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$pr]"; fs_start 42; fs_at 2026-10-28T12:00:00Z; fs_record 42 ticket t42
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"stage":"ticket"' "$out"
}

t_fs_manual_never_starts() {
  # Given: a run of #42, open, labelled manual
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"stage":"task","free":true,"blocked_by":[],"skill":null' "$out"
}

t_fs_unlabeled_waits() {
  # Given: a run of #42, open, labelled only p1
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"stage":"unlabeled"' "$out"
}

t_fs_closed_seed_done() {
  # Given: a run of #42 and #43; #42 is closed and still labelled seed
  fs_setup; fs_issue 42 CLOSED '["seed"]'; fs_issue 43 OPEN '["p1"]'; fs_start 42 43
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"number":42,"title":"Export orders","stage":"done"' "$out"
}

t_fs_open_blocker_holds() {
  # Given: a run of #42, size/S, blocked by open #41 and closed #40
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":41,"state":"OPEN"},{"number":40,"state":"CLOSED"}]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"free":false,"blocked_by":[41]' "$out"
}

t_fs_closed_blockers_free() {
  # Given: a run of #42, size/S, blocked by closed #41
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":41,"state":"CLOSED"}]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"free":true,"blocked_by":[]' "$out"
  has stdout '"message":"/ship-ready https://github.com/acme/app/issues/42"' "$out"
}

t_fs_bug_turned_ticket() {
  # Given: #42's triage thread t1 ran; triage turned the bug into a size/S ticket
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 bug t1
  # When
  fs_go check acme/app
  # Then
  has stdout '"stage":"ticket"' "$out"
  has stdout '"message":"/ship-ready https://github.com/acme/app/issues/42"' "$out"
  eq threads 2 "$(fs_state '.threads | length')"
}

t_fs_restart_fresh_thread() {
  # Given: #42's ticket thread t42 started; #42 is still size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42
  # When
  fs_go change acme/app restart 42
  eq "restart exit" 0 "$code"
  fs_go check acme/app
  # Then
  has stdout '"starts":[{"number":42' "$out"
  eq threads '[{"number":42,"status":"pending"}]' "$(fs_state '[.threads[] | {number, status}]')"
}

t_fs_failed_launch_not_again() {
  # Given: #42 was claimed, and its launch failed with "no reply"
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go check acme/app
  fs_go started acme/app 42 ticket --failed "no reply"
  eq "started exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"thread":null,"thread_status":null,"claim":"failed","why":"no reply"' "$out"
}

t_fs_epic_brings_subs() {
  # Given: a run of epic #70 with open #71 (size/S) and closed #72
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"OPEN"},{"number":72,"state":"CLOSED"}]' "Order export"
  fs_issue 71 OPEN '["size/S"]'; fs_start 70
  # When
  fs_go check acme/app
  # Then
  has stdout '"joined":[71]' "$out"
  has stdout '"number":70,"title":"Order export","stage":"epic"' "$out"
  has stdout '"starts":[{"number":71' "$out"
  eq set '[70,71]' "$(fs_state .set)"
}

t_fs_followup_joins() {
  # Given: a run of #42, since closed by merged PR 43, whose Follow-ups name #50, an open seed
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":"## Summary\n\nx\n\n## Follow-ups\n\n#50: retry the export\n"}'
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"; fs_issue 50 OPEN '["seed"]' '[]' '[]' '[]' "Retry the export"
  # When
  fs_go check acme/app
  # Then
  has stdout '"joined":[50]' "$out"
  has stdout '"message":"/grill https://github.com/acme/app/issues/50"' "$out"
}

t_fs_add_to_set() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go change acme/app add 43
  # Then
  eq exit 0 "$code"
  eq set '[42,43]' "$(fs_state .set)"
}

t_fs_removed_never_rejoins() {
  # Given: a run of epic #70 with #71 joined, then removed
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"OPEN"}]' "Order export"
  fs_issue 71 OPEN '["size/S"]'; fs_start 70
  fs_go check acme/app
  fs_go change acme/app remove 71
  eq "remove exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"joined":[]' "$out"
  eq sets '{"set":[70],"removed":[71]}' "$(fs_state '{set, removed}')"
}

t_fs_ship_full_one() {
  # Given: a run of #42, size/S, set to ship-full
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go change acme/app ship full 42
  eq "ship exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"ship-full"' "$out"
  has stdout '"message":"/ship-full https://github.com/acme/app/issues/42"' "$out"
}

t_fs_ship_full_all() {
  # Given: a run of #42 and #43; #42's ticket thread t42 started
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '["size/S"]'; fs_start 42 43; fs_record 42 ticket t42
  # When
  fs_go change acme/app ship full all
  # Then
  eq exit 0 "$code"
  eq ship '{"default":"full","42":"ready"}' "$(fs_state .ship)"
}

t_fs_ship_full_started() {
  # Given: #42's ticket thread t42 started
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42
  # When
  fs_go change acme/app ship full 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has started; its mode stays ship-ready" "$err"
}

t_fs_override_one_wins() {
  # Given: sonnet at low effort for all, xhigh for #42; #42 size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go change acme/app use all --model sonnet --effort low
  eq "use all exit" 0 "$code"
  fs_go change acme/app use 42 --effort xhigh
  eq "use 42 exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"model":"sonnet","model_from":"set","effort":"xhigh","effort_from":"set"' "$out"
}

t_fs_gh_fail_starts_nothing() {
  # Given: a run of #42, size/S; gh is logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app
  # Then
  eq exit 1 "$code"
  eq stderr "stop: check failed: HTTP 401: Bad credentials" "$err"
  eq state '{"threads":[],"fails":1}' "$(fs_state '{threads, fails: .timer.fails}')"
}

t_fs_t3_fail_starts_nothing() {
  # Given: a run of #42, size/S; T3 does not answer
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'connect ECONNREFUSED\n' > "$T/t3.fail"
  # When
  fs_go check acme/app
  # Then
  eq exit 1 "$code"
  eq stderr "stop: check failed: connect ECONNREFUSED" "$err"
  eq threads '[]' "$(fs_state .threads)"
}

t_fs_third_failure_asks() {
  # Given: a run of #42, size/S; gh is logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app; fs_go check acme/app; fs_go check acme/app
  # Then
  eq stderr "stop: check failed 3 times in a row: HTTP 401: Bad credentials. You must act, then say check now." "$err"
  eq fails 3 "$(fs_state .timer.fails)"
}

t_fs_check_writes_nothing() {
  # Given: a run of #42 (size/S) and #43 (with an open PR from before the run)
  local pr='{"number":44,"url":"https://github.com/acme/app/pull/44","state":"OPEN","createdAt":"2026-10-27T09:00:00Z","body":""}'
  fs_setup; fs_issue 43 OPEN '["size/S"]' '[]' "[$pr]"; fs_issue 42 OPEN '["size/S"]'; fs_prs "$pr"; fs_start 42 43
  fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  eq writes "" "$(cat "$FAKE_GH"/*.args | grep -vE '^(api graphql|issue view|repo view)' || true)"
}

t_fs_two_prs_waits() {
  # Given: #42 has two open PRs from before the run
  local a='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-27T09:00:00Z","body":""}'
  local b='{"number":44,"url":"https://github.com/acme/app/pull/44","state":"OPEN","createdAt":"2026-10-27T10:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$a,$b]"; fs_prs "$a" "$b"; fs_start 42; fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"starts":[]' "$out"
  has stdout '"wait":"#42 has 2 open PRs: https://github.com/acme/app/pull/43 https://github.com/acme/app/pull/44"' "$out"
}

t_fs_all_closed_done() {
  # Given: a run of #42, which went from bug (t1) to ticket (t2) and is now closed by merged PR 43
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["bug"]'; fs_start 42; fs_record 42 bug t1; fs_record 42 ticket t2
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":true' "$out"
  has stdout '"number":42,"title":"Export orders","stages":["bug","ticket"]' "$out"
  has stdout '"url":"https://github.com/acme/app/pull/43","state":"MERGED"' "$out"
  eq status done "$(fs_state -r .status)"
}

t_fs_epic_done() {
  # Given: a run of epic #70, open, whose sub-issues #71 and #72 are closed
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"CLOSED"},{"number":72,"state":"CLOSED"}]' "Order export"
  fs_issue 71 CLOSED '["size/S"]'; fs_issue 72 CLOSED '["size/S"]'; fs_start 70 71 72
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":true' "$out"
  has stdout '"number":70,"title":"Order export","stage":"epic"' "$out"
}

t_fs_manual_keeps_open() {
  # Given: #42 closed; #43 an open manual task
  fs_setup; fs_issue 42 CLOSED '["size/S"]'; fs_issue 43 OPEN '["manual"]'; fs_start 42 43
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":false' "$out"
}

t_fs_unmerged_pr_keeps_open() {
  # Given: a run of #42, since closed by hand while PR 43 that closes it is still open
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":false' "$out"
}

t_fs_timer_five_min() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go timer acme/app --task s1
  # Then
  eq exit 0 "$code"
  eq timer '{"task":"s1","every":5,"fails":0}' "$(fs_state .timer)"
}

t_fs_interval_min_one() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go timer acme/app --every 0
  # Then
  eq exit 1 "$code"
  eq stderr "stop: check every takes 1 minute or more" "$err"
  eq every 5 "$(fs_state .timer.every)"
}

t_fs_paused_starts_nothing() {
  # Given: a run of #42, size/S, paused
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go timer acme/app pause
  eq "pause exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"status":"paused","starts":[]' "$out"
  eq threads '[]' "$(fs_state .threads)"
}

t_fs_stop_keeps_state() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go timer acme/app stop
  # Then
  eq exit 0 "$code"
  eq status stopped "$(fs_state -r .status)"
}

t_fs_live_run_stops_start() {
  # Given: a running run of #42 from the orchestrator thread f1
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go start acme/app --name "#43" --thread x --env e1 43
  # Then
  eq exit 1 "$code"
  eq stderr "stop: a live run in acme/app: [orchestrate: #42](t3-thread://v1/f1)" "$err"
  eq runs 1 "$(ls -1 "$T/orchestrate/acme-app" | wc -l | tr -d ' ')"
}

t_fs_resume_newest() {
  # Given: a stopped run of #42 whose timer was task s1
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go timer acme/app --task s1; fs_go timer acme/app stop
  # When
  fs_go resume acme/app --thread f2 --env e1
  # Then
  eq exit 0 "$code"
  has stdout '"name":"#42","old_task":"s1","every":5' "$out"
  eq state '{"status":"running","link":"[orchestrate: #42](t3-thread://v1/f2)"}' "$(fs_state '{status, link}')"
}

t_fs_no_open_issue_stops() {
  # Given: #42 is closed
  fs_setup; fs_issue 42 CLOSED '["size/S"]'
  # When
  fs_go start acme/app --name "#42" --thread x --env e1 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has no open issue" "$err"
  eq runs 0 "$(ls -1 "$T/orchestrate/acme-app" 2>/dev/null | wc -l | tr -d ' ')"
}

t_fs_outside_t3_stops() {
  # Given: #42 open, and no T3 Code
  fs_setup; fs_issue 42 OPEN '["size/S"]'
  # When
  cd "$T"
  run env -u T3CODE_CLI_PATH KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" ORCHESTRATE_HOME="$T/orchestrate" \
    bash "$F" start acme/app --name "#42" --thread x --env e1 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside T3 Code" "$err"
}

t_fs_unlabeled_listed() {
  # Given: a run of #42, open, labelled only p1
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"proposal":null,"answer":null' "$out"
  has stdout '"propose":[42]' "$out"
  has stdout '"starts":[]' "$out"
}

t_fs_added_unlabeled_listed() {
  # Given: a run of #42 (size/S); #43, open, no label, added
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '[]'; fs_start 42; fs_go change acme/app add 43
  # When
  fs_go check acme/app
  # Then
  has stdout '"propose":[43]' "$out"
  has stdout '"message":"/ship-ready https://github.com/acme/app/issues/42"' "$out"
}

t_fs_proposed_route_word() {
  # Given: a run of #42, open, labelled only p1
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When: a word that is no route, then unsure twice
  fs_go proposed acme/app 42 to-epic
  eq "to-epic exit" 1 "$code"
  eq stderr "stop: usage: orchestrate.sh proposed <owner/repo> <n> grill|triage|ship|ready-pr|task|close|unsure [--size XS|S|M|L|XL]" "$err"
  fs_go proposed acme/app 42 unsure
  eq "first exit" 0 "$code"
  fs_go proposed acme/app 42 unsure
  eq "second exit" 0 "$code"
  eq proposals '{"42":{"route":"unsure","answer":null}}' "$(fs_state .proposals)"
  fs_go check acme/app
  # Then
  has stdout '"propose":[]' "$out"
  has stdout '"proposal":"unsure"' "$out"
}

t_fs_proposed_prints_row() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 ship --size M
  # Then
  eq exit 0 "$code"
  eq stdout '{"number":42,"route":"ship","size":"M","model":"opus","effort":"high"}' "$out"
  eq proposals '{"42":{"route":"ship","answer":null,"size":"M"}}' "$(fs_state .proposals)"
}

t_fs_proposed_use_wins() {
  # Given: a run of unlabeled #42, max effort for all
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  fs_go change acme/app use all --effort max
  # When
  fs_go proposed acme/app 42 grill
  # Then
  eq exit 0 "$code"
  eq stdout '{"number":42,"route":"grill","size":null,"model":"opus","effort":"max"}' "$out"
}

t_fs_proposed_ship_needs_size() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 ship
  # Then
  eq exit 1 "$code"
  eq stderr "stop: a ship proposal needs --size XS|S|M|L|XL" "$err"
  eq proposals '{}' "$(fs_state .proposals)"
}

t_fs_proposed_task_no_size() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 task --size S
  # Then
  eq exit 1 "$code"
  eq stderr "stop: a task proposal takes no --size" "$err"
}

t_fs_proposed_no_model() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 close
  # Then
  eq exit 0 "$code"
  eq stdout '{"number":42,"route":"close","size":null,"model":null,"effort":null}' "$out"
}

t_fs_proposed_decide_stop() {
  # Given: a run of unlabeled #42, no PR closes it
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  printf '{"data":{"repository":{"issue":{"closedByPullRequestsReferences":{"nodes":[]}}}}}\n' > "$FAKE_GH/graphql.json"
  # When
  fs_go proposed acme/app 42 ready-pr
  # Then
  eq exit 0 "$code"
  eq stdout '{"number":42,"route":"ready-pr","size":null,"model":null,"effort":null,"why":"#42 has no open PR"}' "$out"
  eq route '"ready-pr"' "$(fs_state '.proposals["42"].route')"
}

t_fs_answer_keeps_size() {
  # Given: #42 proposed ship at size S
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 ship --size S
  # When
  fs_go change acme/app answer 42 yes
  # Then
  eq exit 0 "$code"
  eq proposals '{"42":{"route":"ship","answer":"ship","size":"S"}}' "$(fs_state .proposals)"
}

t_fs_ship_proposal_size_launches() {
  # Given: unlabeled #42, proposed ship at size S, answered yes
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 ship --size S; fs_go change acme/app answer 42 yes
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"command":"ship-ready","command_from":"set","model":"opus","model_from":"default","effort":"medium","effort_from":"default","reason":"size S, guessed"' "$out"
}

t_fs_label_wins_proposal_size() {
  # Given: #42 proposed unsure at size S, then labelled size/L
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 unsure --size S
  fs_issue 42 OPEN '["size/L"]'
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"model":"opus","model_from":"default","effort":"high","effort_from":"default","reason":"size L"' "$out"
}

t_fs_proposed_outside_set() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 99 grill
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #99 is not in the set" "$err"
}

t_fs_grill_answer_starts() {
  # Given: unlabeled #42, proposed grill, answered yes
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill; fs_go change acme/app answer 42 yes
  eq "answer exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/grill https://github.com/acme/app/issues/42"' "$out"
  has stdout '"stage":"unlabeled"' "$out"
  eq threads '[{"number":42,"stage":"unlabeled","status":"pending"}]' "$(fs_state '[.threads[] | {number, stage, status}]')"
}

t_fs_ship_answer_starts() {
  # Given: unlabeled #42, answered ship with no proposal
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 ship
  eq "answer exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/ship-ready https://github.com/acme/app/issues/42"' "$out"
}

t_fs_all_yes() {
  # Given: #42 proposed grill, #43 proposed triage and answered close, #44 unsure
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_issue 43 OPEN '[]'; fs_issue 44 OPEN '[]'; fs_start 42 43 44
  fs_go proposed acme/app 42 grill; fs_go proposed acme/app 43 triage; fs_go proposed acme/app 44 unsure
  fs_go change acme/app answer 43 close
  # When
  fs_go change acme/app answer all yes
  # Then
  eq exit 0 "$code"
  eq answers '{"42":"grill","43":"close","44":null}' "$(fs_state '.proposals | map_values(.answer)')"
}

t_fs_yes_on_unsure() {
  # Given: #42 proposed unsure
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 unsure
  # When
  fs_go change acme/app answer 42 yes
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has no proposal to say yes to; name a skill" "$err"
}

t_fs_answered_waits_blocker() {
  # Given: unlabeled #42, blocked by open #41, answered grill
  fs_setup; fs_issue 42 OPEN '["p1"]' '[{"number":41,"state":"OPEN"}]'; fs_start 42; fs_go change acme/app answer 42 grill
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"blocked_by":[41]' "$out"
  has stdout '"answer":"grill"' "$out"
}

t_fs_close_answer() {
  # Given: unlabeled #42, proposed close, answered yes
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 close; fs_go change acme/app answer 42 yes
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"propose":[]' "$out"
  has stdout '"answer":"close"' "$out"
  has stdout '"done":false' "$out"
  eq writes "" "$(cat "$FAKE_GH"/*.args | grep -vE '^(api graphql|issue view|repo view)' || true)"
}

t_fs_answers_survive_resume() {
  # Given: #42 proposed task and answered yes; the run stopped and resumed
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 task; fs_go change acme/app answer 42 yes
  fs_go timer acme/app --task s1; fs_go timer acme/app stop; fs_go resume acme/app --thread f2 --env e1
  # When
  fs_go check acme/app
  # Then
  has stdout '"propose":[]' "$out"
  has stdout '"answer":"task"' "$out"
  has stdout '"starts":[]' "$out"
}

t_fs_label_wins_answer() {
  # Given: #42 answered grill, its grill thread t1 ran and gave it size/S
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 grill; fs_record 42 unlabeled t1
  fs_issue 42 OPEN '["size/S"]'
  # When
  fs_go check acme/app
  # Then
  has stdout '"stage":"ticket"' "$out"
  has stdout '"message":"/ship-ready https://github.com/acme/app/issues/42"' "$out"
}

t_fs_ship_full_started_answer() {
  # Given: unlabeled #42 answered ship; its thread t42 started
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 ship; fs_record 42 unlabeled t42
  # When
  fs_go change acme/app ship full 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has started; its mode stays ship-ready" "$err"
}

t_fs_board_columns() {
  # Given: a run from 12:00 of a seed, a ticket, a ticket with a PR made at 13:00, a task, a closed ticket, a bug, and an unlabeled issue
  local pr='{"number":50,"url":"https://github.com/acme/app/pull/50","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 41 OPEN '["seed"]'; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '["size/S"]' '[]' "[$pr]"
  fs_issue 44 OPEN '["manual"]'; fs_issue 45 CLOSED '["size/S"]'; fs_issue 46 OPEN '["bug"]'; fs_issue 47 OPEN '["p1"]'
  fs_start 41 42 43 44 45 46 47; fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  eq columns '{"41":"shape","42":"build","43":"review","44":"build","45":"done","46":"shape","47":"shape"}' \
    "$(fs_board '[.issues[] | {key: (.number|tostring), value: .column}] | sort_by(.key) | from_entries')"
}

t_fs_board_one_file() {
  # Given: a run of #42, size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go check acme/app; fs_go check acme/app
  # Then
  eq files "$(printf 'board.html\nboard.json\nstate.json')" "$(ls -A "$(fs_run)")"
}

t_fs_start_copies_page() {
  # Given: #42 open, size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'
  # When
  fs_go start acme/app --name "#42" --thread f1 --env e1 42
  # Then
  eq page "1 e1" "$(grep -c "<meta name=\"orchestrate-run\" content=\"acme/app/$(basename "$(fs_run)")\">" "$(fs_run)/board.html") $(fs_state -r .env)"
}

t_fs_start_needs_env() {
  # Given: #42 open, size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'
  # When
  fs_go start acme/app --name "#42" --thread f1 42
  # Then
  eq stderr "stop: usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>..." "$err"
}

t_fs_board_chips() {
  # Given: a bug, a seed, a manual task, an unlabeled issue, and three tickets titled "[fix] ...", "feat: ...", and with no type
  fs_setup; fs_issue 41 OPEN '["bug"]'; fs_issue 42 OPEN '["seed"]'; fs_issue 43 OPEN '["manual"]'; fs_issue 44 OPEN '["p1"]'
  fs_issue 45 OPEN '["size/S"]' '[]' '[]' '[]' "[fix] Refund rows"; fs_issue 46 OPEN '["size/M"]' '[]' '[]' '[]' "feat: retry an export"
  fs_issue 47 OPEN '["size/L"]' '[]' '[]' '[]' "Email a link"; fs_start 41 42 43 44 45 46 47
  # When
  fs_go check acme/app
  # Then
  eq chips '["bug","seed","task","unlabeled","fix · S","feat · M","ticket · L"]' "$(fs_board '[.issues | sort_by(.number)[] | .chip]')"
}

# fs_thread <id> <status>: T3 lists one thread, made at 12:10.
fs_thread() { printf '[{"threadId":"%s","status":"%s","createdAt":"2026-10-28T12:10:00Z"}]\n' "$1" "$2" > "$T/t3-threads.json"; }

# fs_card <n>: the column, mark, and action of #n's card.
fs_card() { fs_board --argjson n "$1" '.issues[] | select(.number == $n) | {column, mark, action}'; }

t_fs_board_waiting_yours() {
  # Given: #42's ticket thread t42 waits on the user
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42; fs_thread t42 waiting
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Answer the thread"}' "$(fs_card 42)"
}

t_fs_board_failed_yours() {
  # Given: #42's ticket thread t42 failed
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42; fs_thread t42 failed
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Thread failed: open it, or say restart #42"}' "$(fs_card 42)"
}

t_fs_board_interrupted_yours() {
  # Given: #42's ticket thread t42 was interrupted
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42; fs_thread t42 interrupted
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Thread interrupted: open it, or say restart #42"}' "$(fs_card 42)"
}

t_fs_board_no_change_yours() {
  # Given: #42 is still a bug, and its bug thread t42 completed
  fs_setup; fs_issue 42 OPEN '["bug"]'; fs_start 42; fs_record 42 bug t42; fs_thread t42 completed
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"shape","mark":"you","action":"No change: say restart #42"}' "$(fs_card 42)"
}

t_fs_board_launch_failed_yours() {
  # Given: #42 was claimed, and its launch failed with "no reply"
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go check acme/app; fs_go started acme/app 42 ticket --failed "no reply"
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Launch failed: say restart #42"}' "$(fs_card 42)"
}

t_fs_board_task_yours() {
  # Given: #42, a manual task with no blocker
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Do the task, then close it"}' "$(fs_card 42)"
}

# fs_merge_ready: a run from 12:00 of #42, whose ticket thread t42 completed
# after it opened PR 50 at 13:00.
fs_merge_ready() {
  local pr='{"number":50,"url":"https://github.com/acme/app/pull/50","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$pr]"; fs_start 42; fs_at 2026-10-28T12:00:00Z
  fs_record 42 ticket t42; fs_thread t42 completed
}

t_fs_board_merge_yours() {
  # Given: #42's PR 50 is open and its thread completed
  fs_merge_ready
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"review","mark":"you","action":"Merge PR #50"}' "$(fs_card 42)"
}

t_fs_board_unlabeled_proposing() {
  # Given: #42, labelled only p1, no proposal yet
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"shape","mark":"agent","action":"proposing a route"}' "$(fs_card 42)"
}

t_fs_board_proposal_yours() {
  # Given: unlabeled #42, proposed grill, no answer
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"shape","mark":"you","action":"Answer the proposal: /grill"}' "$(fs_card 42)"
}

t_fs_board_unsure_yours() {
  # Given: unlabeled #42, proposed unsure
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 unsure
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"shape","mark":"you","action":"Answer the proposal"}' "$(fs_card 42)"
}

t_fs_board_answers() {
  # Given: unlabeled #42 answered skip, #43 answered close, #44 answered task
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_issue 43 OPEN '["p1"]'; fs_issue 44 OPEN '["p1"]'; fs_start 42 43 44
  fs_go change acme/app answer 42 skip; fs_go change acme/app answer 43 close; fs_go change acme/app answer 44 task
  # When
  fs_go check acme/app
  # Then
  eq cards '[{"mark":"you","action":"Close it"},{"mark":"you","action":"Do the task, then close it"},{"mark":"blocked","action":"skipped"}]' \
    "$(fs_board -c '[.issues[] | {mark, action}]')"
}

t_fs_board_wait_before_merge() {
  # Given: #42's PR 50 is open and its thread completed, then #42 removed
  fs_merge_ready; fs_go change acme/app remove 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"review","mark":"blocked","action":"waits: removed from the set"}' "$(fs_card 42)"
}

t_fs_removed_read_fails() {
  # Given: a run of #42 and #44, #44 removed, and the read of the removed fails
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 42 OPEN '["size/S"]'; fs_start 42 44; fs_go change acme/app remove 44
  printf 'HTTP 502: Bad gateway\n' > "$FAKE_GH/graphql.3.fail"
  # When
  fs_go check acme/app
  # Then
  eq "exit and cards" '0 [42] 0' "$code $(fs_board -c '[.issues[].number]') $(fs_state .timer.fails)"
}

t_fs_removed_deleted() {
  # Given: a run of #42 and #44, #44 removed, then deleted
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 42 OPEN '["size/S"]'; fs_start 42 44; fs_go change acme/app remove 44
  rm "$T/issues/44.json"; fs_issue 42 OPEN '["size/S"]'
  # When
  fs_go check acme/app
  # Then
  eq "exit and cards" '0 [42]' "$code $(fs_board -c '[.issues[].number]')"
}

t_fs_board_running_agent() {
  # Given: #42's ship-ready thread t42 runs since 12:10
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42 ship-ready; fs_thread t42 running
  # When
  fs_go check acme/app
  # Then
  eq card '{"mark":"agent","action":"/ship-ready","since":"2026-10-28T12:10:00Z"}' "$(fs_board '.issues[0] | {mark, action, since}')"
}

t_fs_board_claimed_starting() {
  # Given: #42, size/S, no thread yet
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"agent","action":"starting /ship-ready"}' "$(fs_card 42)"
}

t_fs_board_blocked() {
  # Given: #42 is blocked by open #7 and #8
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":7,"state":"OPEN"},{"number":8,"state":"OPEN"}]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"blocked","action":"blocked by #7 #8"}' "$(fs_card 42)"
}

t_fs_board_paused_holds() {
  # Given: #42, size/S, in a paused run
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go timer acme/app pause
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"blocked","action":"paused: starts on resume"}' "$(fs_card 42)"
}

t_fs_board_done() {
  # Given: #42 closed, and #43 still open so the run goes on
  fs_setup; fs_issue 42 CLOSED '["size/S"]'; fs_issue 43 OPEN '["size/S"]'; fs_start 42 43
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"done","mark":"done","action":"closed"}' "$(fs_card 42)"
}

t_fs_board_links() {
  # Given: #42's PR 50 is open and its thread t42 completed, in a run with env e1
  fs_merge_ready
  # When
  fs_go check acme/app
  # Then
  eq links '{"url":"https://github.com/acme/app/issues/42","thread":"t3code://threads/e1/t42","pr":{"number":50,"url":"https://github.com/acme/app/pull/50"}}' \
    "$(fs_board '.issues[0] | {url, thread: .thread.url, pr}')"
}

t_fs_board_order() {
  # Given: in Build, #42 blocked by open #9, #43 a ticket about to start, #44 a free task
  # (#43 last, since decide.sh's fake `issue view` answers with the last issue given)
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":9,"state":"OPEN"}]'; fs_issue 44 OPEN '["manual"]'; fs_issue 43 OPEN '["size/S"]'
  fs_start 42 43 44
  # When
  fs_go check acme/app
  # Then
  eq order '[44,43,42]' "$(fs_board '[.issues[] | .number]')"
}

t_fs_board_extra_chips() {
  # Given: #42 closed by merged PR 43, whose Follow-ups name #50, an open seed; #44 removed; #45 set to ship-full
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":"## Follow-ups\n\n#50: retry the export\n"}'
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 45 OPEN '["size/S"]'; fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  fs_issue 50 OPEN '["seed"]' '[]' '[]' '[]' "Retry the export"; fs_start 42 44 45
  fs_go change acme/app remove 44; fs_go change acme/app ship full 45
  # When
  fs_go check acme/app
  # Then
  eq chips '[{"number":44,"removed":true,"made":false,"ship_full":false},{"number":45,"removed":false,"made":false,"ship_full":true},{"number":50,"removed":false,"made":true,"ship_full":false}]' \
    "$(fs_board '[.issues[] | select(.removed or .made or .ship_full) | {number, removed, made, ship_full}] | sort_by(.number)')"
}

t_fs_removed_starts_nothing() {
  # Given: a run of #42 and #44, both size/S, then #44 removed
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 42 OPEN '["size/S"]'; fs_start 42 44; fs_go change acme/app remove 44
  # When
  fs_go check acme/app
  # Then
  eq started '[42]' "$(fs_state '[.threads[] | .number]')"
}

t_fs_check_records_time() {
  # Given: a run of #42, size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq health '{"time":true,"why":null}' "$(fs_state '{time: (.timer.checked_at | test("^2[0-9]{3}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")), why: .timer.why}')"
}

t_fs_failed_check_why() {
  # Given: a run of #42; gh is logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app
  # Then
  eq timer '{"fails":1,"why":"HTTP 401: Bad credentials"}' "$(fs_state '{fails: .timer.fails, why: .timer.why}')"
}

t_fs_failed_check_keeps_board() {
  # Given: a run of #42 checked once, then gh logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go check acme/app; cp "$(fs_run)/board.json" "$T/board.before"
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app
  # Then
  eq board same "$(cmp -s "$T/board.before" "$(fs_run)/board.json" && echo same)"
}

t_fs_board_journey() {
  # Given: #42 went from bug (t1, completed, 12:10) to ticket (t2, running, 12:40)
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_record 42 bug t1 triage 2026-10-28T12:10:00Z; fs_record 42 ticket t2 ship-ready 2026-10-28T12:40:00Z
  printf '[{"threadId":"t1","status":"completed","createdAt":"2026-10-28T12:10:00Z"},{"threadId":"t2","status":"running","createdAt":"2026-10-28T12:40:00Z"}]\n' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq journey '["joined","bug","ticket"] {"thread_url":"t3code://threads/e1/t2","status":"running"}' \
    "$(fs_board '.issues[0].journey | map(.stage // .step)') $(fs_board '.issues[0].journey[2] | {thread_url, status}')"
}

t_fs_board_fixture_shape() {
  # Given: a run of #42, size/S, whose thread t42 runs, checked
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42 ship-ready; fs_thread t42 running
  fs_go check acme/app
  # When
  local fixture; fixture="$(jq -c '.issues[0] | keys' "$here/fixtures/board/board.json")"
  # Then
  eq keys "$fixture" "$(fs_board '.issues[0] | keys')"
}

t_fs_page_no_mockup_data() {
  # Given: the board page
  # When
  local hits; hits="$(grep -c -e StatePanel -e env-demo -e acme/shop -e thr_i "$here/../assets/board.html" || true)"
  # Then
  eq hits 0 "$hits"
}

t_fs_resume_copies_page() {
  # Given: a stopped run of #42 whose board page is old
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go timer acme/app stop
  printf 'old\n' > "$(fs_run)/board.html"
  # When
  fs_go resume acme/app --thread f2 --env e2
  # Then
  eq page "1 e2" "$(grep -c "<meta name=\"orchestrate-run\" content=\"acme/app/$(basename "$(fs_run)")\">" "$(fs_run)/board.html") $(fs_state -r .env)"
}

t_fs_two_runs_two_pages() {
  # Given: a run of #42, stopped, then a second run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go timer acme/app stop
  # (both start in one second here, so the first run's folder moves back a
  # year, and a resume names that folder in its page)
  local first="$T/orchestrate/acme-app/20200101T000000Z"; mv "$(fs_run)" "$first"
  fs_go resume acme/app --thread f1 --env e1; fs_go timer acme/app stop; fs_start 42
  # When
  local diff=same; cmp -s "$first/board.html" "$(fs_run)/board.html" || diff=differ
  # Then
  eq pages differ "$diff"
}

cases=(
  "start writes the run and its set|t_fs_start_writes_run"
  "a free ticket starts ship-ready|t_fs_ticket_starts_ship_ready"
  "a second check starts nothing|t_fs_second_check_starts_nothing"
  "a recorded thread is not started again|t_fs_recorded_thread_not_again"
  "a seed starts grill|t_fs_seed_starts_grill"
  "a bug starts triage|t_fs_bug_starts_triage"
  "a PR from before the run starts ready-pr|t_fs_old_pr_starts_ready_pr"
  "a PR the run opened starts nothing new|t_fs_new_pr_starts_nothing"
  "a manual task never starts|t_fs_manual_never_starts"
  "an unlabeled issue waits|t_fs_unlabeled_waits"
  "a closed seed is done|t_fs_closed_seed_done"
  "an open blocker holds the issue|t_fs_open_blocker_holds"
  "closed blockers free the issue|t_fs_closed_blockers_free"
  "a bug turned ticket starts ship-ready|t_fs_bug_turned_ticket"
  "restart starts a fresh thread|t_fs_restart_fresh_thread"
  "a failed launch is not started again|t_fs_failed_launch_not_again"
  "an epic in the set brings its open sub-issues|t_fs_epic_brings_subs"
  "a follow-up in a PR body joins|t_fs_followup_joins"
  "add puts an issue in the set|t_fs_add_to_set"
  "a removed issue never rejoins|t_fs_removed_never_rejoins"
  "ship-full for one issue|t_fs_ship_full_one"
  "ship-full for all leaves started issues|t_fs_ship_full_all"
  "ship-full for a started issue stops|t_fs_ship_full_started"
  "an override for one issue wins over all|t_fs_override_one_wins"
  "a failed gh call starts nothing|t_fs_gh_fail_starts_nothing"
  "T3 not answering starts nothing|t_fs_t3_fail_starts_nothing"
  "the third failure in a row asks the user to act|t_fs_third_failure_asks"
  "the check writes nothing to GitHub|t_fs_check_writes_nothing"
  "two open PRs make the issue wait|t_fs_two_prs_waits"
  "all closed ends the run with a summary|t_fs_all_closed_done"
  "an epic with closed sub-issues is done|t_fs_epic_done"
  "an open manual task keeps the run open|t_fs_manual_keeps_open"
  "an unmerged PR keeps the run open|t_fs_unmerged_pr_keeps_open"
  "start sets a 5 minute timer|t_fs_timer_five_min"
  "the interval takes 1 minute or more|t_fs_interval_min_one"
  "a paused run starts nothing|t_fs_paused_starts_nothing"
  "stop keeps the state file|t_fs_stop_keeps_state"
  "a live run stops a second start|t_fs_live_run_stops_start"
  "resume takes the newest run that is not done|t_fs_resume_newest"
  "a set with no open issue stops|t_fs_no_open_issue_stops"
  "outside T3 Code stops|t_fs_outside_t3_stops"
  "an unlabeled issue is listed to propose|t_fs_unlabeled_listed"
  "an added unlabeled issue is listed to propose|t_fs_added_unlabeled_listed"
  "proposed takes only a route word|t_fs_proposed_route_word"
  "proposed for an issue outside the set stops|t_fs_proposed_outside_set"
  "proposed prints the model and effort|t_fs_proposed_prints_row"
  "proposed takes the use pick|t_fs_proposed_use_wins"
  "a ship proposal needs a size|t_fs_proposed_ship_needs_size"
  "a task proposal takes no size|t_fs_proposed_task_no_size"
  "a close proposal has no model|t_fs_proposed_no_model"
  "a decide stop keeps the proposal and says why|t_fs_proposed_decide_stop"
  "an answer keeps the size|t_fs_answer_keeps_size"
  "a ship proposal launches with its size|t_fs_ship_proposal_size_launches"
  "a size label wins over the proposal's size|t_fs_label_wins_proposal_size"
  "a grill answer starts grill|t_fs_grill_answer_starts"
  "a ship answer starts ship-ready|t_fs_ship_answer_starts"
  "all yes takes every sure proposal|t_fs_all_yes"
  "yes on an unsure proposal stops|t_fs_yes_on_unsure"
  "an answered issue waits for its blocker|t_fs_answered_waits_blocker"
  "a close answer starts nothing and writes nothing|t_fs_close_answer"
  "answers survive stop and resume|t_fs_answers_survive_resume"
  "a label wins over an answer|t_fs_label_wins_answer"
  "ship-full for a started ship answer stops|t_fs_ship_full_started_answer"
  "the board puts each issue in its column|t_fs_board_columns"
  "a second check leaves one board file|t_fs_board_one_file"
  "start copies the board page into the run|t_fs_start_copies_page"
  "start without an env id stops|t_fs_start_needs_env"
  "the board chip is the kind and the size|t_fs_board_chips"
  "a waiting thread is yours|t_fs_board_waiting_yours"
  "a failed thread is yours|t_fs_board_failed_yours"
  "an interrupted thread is yours|t_fs_board_interrupted_yours"
  "a completed thread with no new stage is yours|t_fs_board_no_change_yours"
  "a failed launch is yours|t_fs_board_launch_failed_yours"
  "a free task is yours|t_fs_board_task_yours"
  "an open PR with no running thread waits for your merge|t_fs_board_merge_yours"
  "an unlabeled issue with no proposal is the agent's|t_fs_board_unlabeled_proposing"
  "a proposal with no answer is yours|t_fs_board_proposal_yours"
  "an unsure proposal is yours|t_fs_board_unsure_yours"
  "a skip, close, or task answer shows on the card|t_fs_board_answers"
  "a wait shows before an open PR|t_fs_board_wait_before_merge"
  "a failed read of removed issues fails no check|t_fs_removed_read_fails"
  "a deleted removed issue has no card|t_fs_removed_deleted"
  "a running thread is the agent's|t_fs_board_running_agent"
  "a claimed thread is starting|t_fs_board_claimed_starting"
  "an open blocker holds the card|t_fs_board_blocked"
  "a paused run holds a free ticket|t_fs_board_paused_holds"
  "a closed issue is done|t_fs_board_done"
  "the board links the thread and the PR|t_fs_board_links"
  "the board orders you, agent, blocked|t_fs_board_order"
  "the board marks removed, made by run, and ship-full|t_fs_board_extra_chips"
  "a removed issue starts nothing|t_fs_removed_starts_nothing"
  "a good check records its time|t_fs_check_records_time"
  "a failed check records why|t_fs_failed_check_why"
  "a failed check keeps the last board|t_fs_failed_check_keeps_board"
  "the journey lists each stage and its thread|t_fs_board_journey"
  "the walk fixture has the board's shape|t_fs_board_fixture_shape"
  "the page ships no mockup data|t_fs_page_no_mockup_data"
  "resume copies the board page again|t_fs_resume_copies_page"
  "two runs get two different pages|t_fs_two_runs_two_pages"
)
