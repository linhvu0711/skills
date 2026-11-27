# orchestrate.sh: the cases for this skill's orchestrate.sh, the check script and the
# one writer of a run's state file, seen through the fake gh and a fake t3.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The orchestrator script.
F="$here/../scripts/orchestrate.sh"

# fs_setup: a fresh temp folder T, the fake gh (its `repo view` names main),
# one checkout of acme/app at $T/dev/app, and a fake t3 in $T/bin. t3's
# `thread list --project <path>` prints $T/t3-threads.<folder name>.json when
# that file exists, else $T/t3-threads.json, or fails with the text of
# $T/t3.fail when that file exists, or when $T/no-project lists the path.
# Its `project add <path>` logs `project add <path>` to $T/t3.log and takes
# the path off $T/no-project. Its `thread send` adds its arguments as
# one line to $T/t3-sends.log, or fails with the text of $T/t3-send.fail
# when that file exists. Issues go in with fs_issue.
fs_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"acme/app"}\n' > "$FAKE_GH/repo-view.json"
  git init -q -b main "$T/dev/app"
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/dev/app" remote add origin https://github.com/acme/app.git
  cat > "$T/bin/t3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "thread list")
    if [ -e "$FAKE_T3_DIR/t3.fail" ]; then cat "$FAKE_T3_DIR/t3.fail" >&2; exit 1; fi
    if grep -qxF "$4" "$FAKE_T3_DIR/no-project" 2>/dev/null; then echo "no project at $4" >&2; exit 1; fi
    f="$FAKE_T3_DIR/t3-threads.$(basename "$4").json"; [ -f "$f" ] || f="$FAKE_T3_DIR/t3-threads.json"
    cat "$f" ;;
  "project add")
    echo "project add $3" >> "$FAKE_T3_DIR/t3.log"
    grep -vxF "$3" "$FAKE_T3_DIR/no-project" > "$FAKE_T3_DIR/no-project.new" || true
    mv "$FAKE_T3_DIR/no-project.new" "$FAKE_T3_DIR/no-project" ;;
  "thread send") if [ -e "$FAKE_T3_DIR/t3-send.fail" ]; then cat "$FAKE_T3_DIR/t3-send.fail" >&2; exit 1; fi; echo "$*" >> "$FAKE_T3_DIR/t3-sends.log" ;;
  *) printf 'fake t3: no route for %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$T/bin/t3"
  echo '[]' > "$T/t3-threads.json"
  echo https://github.com/acme/app/issues/42 > "$FAKE_GH/issue-edit.json"
  mkdir -p "$T/issues"
  export FAKE_T3_DIR="$T"
}

# fs_issue <n> <state> <labels> [blocked-by] [prs] [subs] [title]: issue #n
# in the GraphQL answer of acme/app, or of acme/$FS_REPO when that is set.
# <labels> is a JSON list of names; the rest are JSON lists of nodes, empty
# when left out. A blocker or sub-issue node with no repository is in the
# issue's repo. The title is "Export orders" unless given.
fs_issue() {
  local title="${7:-Export orders}" dir="$T/issues${FS_REPO:+-$FS_REPO}"
  mkdir -p "$dir"
  jq -cn --argjson n "$1" --arg s "$2" --argjson l "$3" --argjson b "${4:-[]}" \
    --argjson p "${5:-[]}" --argjson u "${6:-[]}" --arg t "$title" --arg repo "acme/${FS_REPO:-app}" \
    'def inrepo: map(.repository //= {nameWithOwner: $repo});
     {number: $n, title: $t, state: $s, createdAt: "2026-10-01T00:00:00Z",
      labels: {nodes: [$l[] | {name: .}]}, subIssues: {nodes: ($u | inrepo)},
      blockedBy: {nodes: ($b | inrepo)}, closedByPullRequestsReferences: {nodes: $p}}' > "$dir/$1.json"
  jq -s '{data: {repository: (map({key: "i\(.number)", value: .}) | from_entries)}}' "$dir"/*.json \
    > "$FAKE_GH/graphql${FS_REPO:+.$FS_REPO}.json"
}

# fs_go <args...>: orchestrate.sh from T, inside T3 Code, with the search root,
# the repo map, the orchestrator home, and the issue conventions store inside T.
fs_go() {
  cd "$T"
  run env T3CODE_CLI_PATH="$T/bin/t3" KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" GH_ISSUE_STORE="$T/conv.json" \
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

# fs_remote: a bare repo $T/remote.git made from the checkout, which the
# checkout's GitHub origin URL now reaches, and a second clone $T/other to
# push from.
fs_remote() {
  git clone -q --bare "$T/dev/app" "$T/remote.git"
  git -C "$T/dev/app" config url."$T/remote.git".insteadOf https://github.com/acme/app.git
  git -C "$T/dev/app" fetch -q origin
  git clone -q "$T/remote.git" "$T/other"
}

# fs_push <file> <text>: a commit in $T/other that writes the file, pushed to main.
fs_push() {
  printf '%s\n' "$2" > "$T/other/$1"
  git -C "$T/other" add "$1"
  git -C "$T/other" -c user.email="t""@""example.invalid" -c user.name=t commit -q -m "$2"
  git -C "$T/other" push -q origin main
}

# fs_short <dir> <rev>: the 7-character SHA of the rev.
fs_short() { git -C "$1" rev-parse --short=7 "$2"; }

t_fs_start_writes_run() {
  # Given: #42 "Export orders", open, size/L
  fs_setup; fs_issue 42 OPEN '["size/L"]'
  # When
  fs_go start acme/app --name "#42" --thread f1 --env e1 42
  # Then
  eq exit 0 "$code"
  eq runs 1 "$(ls -1 "$T/orchestrate/acme-app" | wc -l | tr -d ' ')"
  eq state '{"set":["acme/app#42"],"status":"running","every":5,"threads":[]}' "$(fs_state '{set, status, every: .timer.every, threads}')"
}

t_fs_old_state_converted() {
  # Given: a run of #42 after one check, its state rewritten as a run from
  # before refs left it: bare numbers in the set, the threads, and the keys
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go check acme/app
  fs_set_state '.set = [42] | .threads = [{number: 42, stage: "ticket", thread: "t1", link: "[i42](t3-thread://v1/t1)", status: "started", why: null, command: "ship"}] | .proposals = {"42": {route: "ship"}}'
  # When: two checks
  fs_go check acme/app; local first="$out"
  fs_go check acme/app
  # Then
  eq state '{"set":["acme/app#42"],"thread":"acme/app#42","proposals":["acme/app#42"]}' \
    "$(fs_state -c '{set, thread: .threads[0].ref, proposals: (.proposals | keys)}')"
  eq starts '[] []' "$(jq -c .starts <<<"$first") $(jq -c .starts <<<"$out")"
}

t_fs_ticket_starts_ship() {
  # Given: a run of #42, open, size/L, no blocker, no PR
  fs_setup; fs_issue 42 OPEN '["size/L"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"command":"ship","mode":"","model":"opus","model_from":"default","effort":"high","effort_from":"default"' "$out"
  has stdout '"message":"/ship #42"' "$out"
  has stdout '"thread_title":"#42 Export orders"' "$out"
  lacks stdout '"runtime_mode"' "$out"
}

t_fs_second_check_starts_nothing() {
  # Given: a run of #42, size/L, checked once
  fs_setup; fs_issue 42 OPEN '["size/L"]'; fs_start 42
  fs_go check acme/app
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  eq threads '[{"ref":"acme/app#42","stage":"ticket","status":"pending"}]' "$(fs_state '[.threads[] | {ref, stage, status}]')"
}

t_fs_recorded_thread_not_again() {
  # Given: #42's ticket thread t42 started and running
  fs_setup; fs_issue 42 OPEN '["size/L"]'; fs_start 42
  fs_go check acme/app
  fs_go started acme/app 42 ticket t42 "[#42 Export orders](t3-thread://v1/t42)"
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

# fs_set_state [jq flags] <jq program>: change the newest run's state, as a run from an
# older orchestrate.sh left it.
fs_set_state() {
  local f; f="$(ls -1d "$T"/orchestrate/acme-app/*/ | sort | tail -1)state.json"
  jq "$@" "$f" > "$f.new" && mv "$f.new" "$f"
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
  has stdout '"command":"grill","mode":"","model":"opus","model_from":"default","effort":"high"' "$out"
  has stdout '"message":"/grill #42"' "$out"
}

t_fs_bug_starts_triage() {
  # Given: a run of #42, open, labelled bug
  fs_setup; fs_issue 42 OPEN '["bug"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"triage"' "$out"
  has stdout '"message":"/triage #42"' "$out"
}

t_fs_old_pr_starts_ready_pr() {
  # Given: a run from 2026-10-28T12:00:00Z; #42 size/S with open PR 43 from the day before
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-27T09:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$pr]"; fs_prs "$pr"; fs_start 42; fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"ready-pr"' "$out"
  has stdout '"message":"/ready-pr #43"' "$out"
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

# fs_conflict <n> <pr> <mergeable> <head>: issue #n, size/S, with open PR
# <pr> opened after the run start of fs_at 2026-10-28T12:00:00Z, so its
# stage stays ticket.
fs_conflict() {
  local pr
  pr="$(jq -cn --argjson p "$2" --arg m "$3" --arg h "$4" \
    '{number: $p, url: "https://github.com/acme/app/pull/\($p)", state: "OPEN", createdAt: "2026-10-28T13:00:00Z", body: "", mergeable: $m, headRefOid: $h}')"
  fs_issue "$1" OPEN '["size/S"]' '[]' "[$pr]"
}

# fs_conflict_run: #42 with PR 43 CONFLICTING at aaa111, and #42's ticket
# thread t42 finished its turn.
fs_conflict_run() {
  fs_setup; fs_conflict 42 43 CONFLICTING aaa111; fs_start 42; fs_at 2026-10-28T12:00:00Z; fs_record 42 ticket t42 ship
  echo '[{"threadId":"t42","status":"completed"}]' > "$T/t3-threads.json"
}

t_fs_conflict_listed() {
  # Given: #42's PR 43 conflicts at aaa111, and thread t42 is completed
  fs_conflict_run
  # When
  fs_go watch acme/app --once
  # Then
  eq exit 0 "$code"
  eq line '[{"ref":"acme/app#42","pr":43,"thread":"t42"}]' "$(jq -c .sent <<<"$out")"
  eq sends "thread send t42 /ready-pr https://github.com/acme/app/pull/43" "$(fs_sends)"
  eq state '[{"ref":"acme/app#42","pr":43,"head":"aaa111","thread":"t42"}]' "$(fs_state '[.conflicts[] | {ref, pr, head, thread}]')"
}

t_fs_conflict_once_per_head() {
  # Given: the conflict of PR 43 at aaa111 sent by one watcher check
  fs_conflict_run; fs_go watch acme/app --once
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[]' "$(jq -c .sent <<<"$out")"
  eq state 1 "$(fs_state '.conflicts | length')"
  eq sends "thread send t42 /ready-pr https://github.com/acme/app/pull/43" "$(fs_sends)"
}

t_fs_conflict_new_head() {
  # Given: the conflict at aaa111 sent, then PR 43 conflicts again at bbb222
  fs_conflict_run; fs_go watch acme/app --once
  fs_conflict 42 43 CONFLICTING bbb222
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[{"ref":"acme/app#42","pr":43,"thread":"t42"}]' "$(jq -c .sent <<<"$out")"
  eq state '["aaa111","bbb222"]' "$(fs_state '[.conflicts[] | .head]')"
}

t_fs_conflict_busy_thread() {
  # Given: PRs 43 and 45 conflict; thread t42 runs and thread t44 waits on the user
  fs_setup; fs_conflict 42 43 CONFLICTING aaa111; fs_conflict 44 45 CONFLICTING ccc333; fs_start 42 44; fs_at 2026-10-28T12:00:00Z
  fs_record 42 ticket t42 ship; fs_record 44 ticket t44 ship
  echo '[{"threadId":"t42","status":"running"},{"threadId":"t44","status":"waiting"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[]' "$(jq -c .sent <<<"$out")"
  eq sends none "$(fs_sends)"
}

t_fs_conflict_none() {
  # Given: PR 43 is MERGEABLE, PR 45 is UNKNOWN, and both threads are completed
  fs_setup; fs_conflict 42 43 MERGEABLE aaa111; fs_conflict 44 45 UNKNOWN ccc333; fs_start 42 44; fs_at 2026-10-28T12:00:00Z
  fs_record 42 ticket t42 ship; fs_record 44 ticket t44 ship
  echo '[{"threadId":"t42","status":"completed"},{"threadId":"t44","status":"completed"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[]' "$(jq -c .sent <<<"$out")"
  eq sends none "$(fs_sends)"
}

t_fs_conflict_paused() {
  # Given: PR 43 conflicts and thread t42 is completed, but the run is paused
  fs_conflict_run; fs_go timer acme/app pause
  # When
  fs_go watch acme/app --once
  # Then
  eq exit 3 "$code"
  eq state 0 "$(fs_state '.conflicts // [] | length')"
  eq sends none "$(fs_sends)"
}

t_fs_conflict_shared_pr() {
  # Given: PR 43 conflicts and closes both #42 and #44; threads t42 and t44 are completed
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":"","mergeable":"CONFLICTING","headRefOid":"aaa111"}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$pr]"; fs_issue 44 OPEN '["size/S"]' '[]' "[$pr]"; fs_start 42 44; fs_at 2026-10-28T12:00:00Z
  fs_record 42 ticket t42 ship; fs_record 44 ticket t44 ship
  echo '[{"threadId":"t42","status":"completed"},{"threadId":"t44","status":"completed"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[{"ref":"acme/app#42","pr":43}]' "$(jq -c '[.sent[] | {ref, pr}]' <<<"$out")"
  eq sends "thread send t42 /ready-pr https://github.com/acme/app/pull/43" "$(fs_sends)"
}

t_fs_conflict_shared_owner() {
  # Given: PR 43 conflicts and closes #42 and #44; #42's thread t42 runs, #44's thread t44 is completed
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":"","mergeable":"CONFLICTING","headRefOid":"bbb222"}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$pr]"; fs_issue 44 OPEN '["size/S"]' '[]' "[$pr]"; fs_start 42 44; fs_at 2026-10-28T12:00:00Z
  fs_record 42 ticket t42 ship; fs_record 44 ticket t44 ship
  echo '[{"threadId":"t42","status":"running"},{"threadId":"t44","status":"completed"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[]' "$(jq -c .sent <<<"$out")"
}

t_fs_conflict_one_per_thread() {
  # Given: #42 has PRs 43 and 45, both conflicting, and thread t42 is completed
  local a='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":"","mergeable":"CONFLICTING","headRefOid":"aaa111"}'
  local b='{"number":45,"url":"https://github.com/acme/app/pull/45","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":"","mergeable":"CONFLICTING","headRefOid":"ccc333"}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$a,$b]"; fs_start 42; fs_at 2026-10-28T12:00:00Z; fs_record 42 ticket t42 ship
  echo '[{"threadId":"t42","status":"completed"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[43]' "$(jq -c '[.sent[] | .pr]' <<<"$out")"
}

t_fs_conflict_new_stage() {
  # Given: #42's triage thread t42 is completed, #42 is now size/S, and its PR 43 conflicts
  fs_setup; fs_conflict 42 43 CONFLICTING aaa111; fs_start 42; fs_at 2026-10-28T12:00:00Z; fs_record 42 bug t42 triage
  echo '[{"threadId":"t42","status":"completed"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["start #42","settle #42"],"sent":[]}' "$(jq -c '{wake, sent}' <<<"$out")"
}

t_fs_check_no_conflict() {
  # Given: #42's PR 43 conflicts at aaa111, and thread t42 is completed
  fs_conflict_run
  # When
  fs_go check acme/app
  # Then
  eq line false "$(jq -c 'has("conflicts")' <<<"$out")"
  eq state null "$(fs_state .conflicts)"
  eq sends none "$(fs_sends)"
}

t_fs_conflict_send_failed() {
  # Given: the conflict of PR 43 claimed by a watcher check whose send T3 refused
  fs_conflict_run
  printf 'connect ECONNREFUSED\n' > "$T/t3-send.fail"; fs_go watch acme/app --once; rm "$T/t3-send.fail"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '[]' "$(jq -c .sent <<<"$out")"
  eq sends none "$(fs_sends)"
  eq state '[43]' "$(fs_state '[.conflicts[] | .pr]')"
}

t_fs_task_starts_complete_task() {
  # Given: a run of #42, open, labelled manual
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"complete-task"' "$out"
  has stdout '"model":"opus"' "$out"
  has stdout '"effort":"medium"' "$out"
  has stdout '"message":"/complete-task --ready #42"' "$out"
  has stdout '"thread_title":"#42 Export orders"' "$out"
  lacks stdout '"runtime_mode"' "$out"
}

t_fs_second_task_waits() {
  # Given: a run of #42 and #43, both open and manual
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_issue 43 OPEN '["manual"]'; fs_start 42 43
  # When
  fs_go check acme/app
  # Then
  eq starts '["acme/app#42"]' "$(jq -c '[.starts[] | .ref]' <<<"$out")"
  has stdout '"wait":"waits for the task turn: acme/app#42"' "$out"
  eq state '["acme/app#42"]' "$(fs_state '.task_turn')"
}

# fs_other_run <status> [watcher-pid]: a run of acme/web whose state holds the
# task turn for #7, with its watcher's pid. The status `broken` writes a state
# file that does not parse.
fs_other_run() {
  local f="$T/orchestrate/acme-web/20260101T000000Z/state.json"
  mkdir -p "$(dirname "$f")"
  if [ "$1" = broken ]; then echo '{"repo":' > "$f"; return; fi
  jq -cn --arg s "$1" --arg p "${2:-}" '{repo: "acme/web", status: $s, task_turn: [7],
    timer: {watcher: (if $p == "" then null else {pid: ($p | tonumber)} end)}}' > "$f"
}

t_fs_other_run_holds_turn() {
  # Given: a run of #42, open and manual; a running run of acme/web, whose
  # watcher is alive, holds the turn for #7
  local w
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  (exec -a "orchestrate.sh watch acme/web --loop" /bin/sleep 60) & w=$!
  fs_other_run running "$w"
  # When
  fs_go check acme/app
  kill "$w"
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"wait":"waits for the task turn: acme/web#7"' "$out"
}

t_fs_dead_watcher_no_turn() {
  # Given: a run of #42, open and manual; a running run of acme/web holds the
  # turn for #7, but its watcher's pid now runs something else, as after a restart
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_other_run running "$$"
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/complete-task --ready #42"' "$out"
}

t_fs_stopped_run_no_turn() {
  # Given: the same, with the acme/web run stopped
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_other_run stopped
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/complete-task --ready #42"' "$out"
}

t_fs_broken_run_no_turn() {
  # Given: a run of #42, open and manual; another run's state file does not parse
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_other_run broken
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"message":"/complete-task --ready #42"' "$out"
}

t_fs_failed_task_launch_frees_turn() {
  # Given: a run of #42, manual, claimed by a check, so it holds the turn
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  fs_go check acme/app
  eq "turn held" '["acme/app#42"]' "$(fs_state '.task_turn')"
  # When
  fs_go started acme/app 42 task --failed "no reply"
  # Then
  eq exit 0 "$code"
  eq state '[]' "$(fs_state '.task_turn')"
}

t_fs_closed_task_frees_turn() {
  # Given: a run of #42 and #43, both manual; #42's task thread started, then #42 closed
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_issue 43 OPEN '["manual"]'; fs_start 42 43
  fs_record 42 task t42
  fs_issue 42 CLOSED '["manual"]'; fs_issue 43 OPEN '["manual"]'
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/complete-task --ready #43"' "$out"
}

t_fs_later_task_holds_turn() {
  # Given: a run of #42 and #43, both manual; #43's task thread started, #42 has none
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_issue 43 OPEN '["manual"]'; fs_start 42 43
  fs_record 43 task t43
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"wait":"waits for the task turn: acme/app#43"' "$out"
}

t_fs_removed_task_frees_turn() {
  # Given: a run of #42 and #43, both manual; #42's task thread started, then #42 removed
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_issue 43 OPEN '["manual"]'; fs_start 42 43
  fs_record 42 task t42; fs_go change acme/app remove 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/complete-task --ready #43"' "$out"
}

t_fs_watch_claims_no_turn() {
  # Given: a run of #42, open and manual, with no thread record
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  # When
  fs_go watch acme/app --once
  # Then
  eq state '[]' "$(fs_state '.task_turn')"
}

t_fs_watch_frees_closed_turn() {
  # Given: a run of #42, manual, whose task thread started and holds the turn; then #42 closed
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  fs_record 42 task t42; fs_set_state '.task_turn = [42]'
  fs_issue 42 CLOSED '["manual"]'
  # When
  fs_go watch acme/app --once
  # Then
  eq state '[]' "$(fs_state '.task_turn')"
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
  has stdout '"label":"#42","url":"https://github.com/acme/app/issues/42","title":"Export orders","stage":"done"' "$out"
}

t_fs_open_blocker_holds() {
  # Given: a run of #42, size/S, blocked by open #41 and closed #40
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":41,"state":"OPEN"},{"number":40,"state":"CLOSED"}]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"starts":[]' "$out"
  has stdout '"free":false,"blocked_by":["acme/app#41"]' "$out"
}

t_fs_closed_blockers_free() {
  # Given: a run of #42, size/S, blocked by closed #41
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":41,"state":"CLOSED"}]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  has stdout '"free":true,"blocked_by":[]' "$out"
  has stdout '"message":"/ship #42"' "$out"
}

t_fs_bug_turned_ticket() {
  # Given: #42's triage thread t1 ran; triage turned the bug into a size/S ticket
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 bug t1
  # When
  fs_go check acme/app
  # Then
  has stdout '"stage":"ticket"' "$out"
  has stdout '"message":"/ship #42"' "$out"
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
  has stdout '"ref":"acme/app#42","stage":"ticket"' "$out"
  eq threads '[{"ref":"acme/app#42","status":"pending"}]' "$(fs_state '[.threads[] | {ref, status}]')"
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
  has stdout '"joined":["acme/app#71"]' "$out"
  has stdout '"label":"#70","url":"https://github.com/acme/app/issues/70","title":"Order export","stage":"epic"' "$out"
  has stdout '"ref":"acme/app#71","stage":"ticket"' "$out"
  eq set '["acme/app#70","acme/app#71"]' "$(fs_state .set)"
}

t_fs_xxl_starts_nothing() {
  # Given: a run of #42 "Rewrite the order store", open, size/XXL
  fs_setup; fs_issue 42 OPEN '["size/XXL"]' '[]' '[]' '[]' "Rewrite the order store"; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"starts":[]' "$out"
  has stdout '"stage":"too-big"' "$out"
  eq card '{"column":"shape","mark":"you","action":"Cut it with /file-epic","chip":"ticket · XXL"}' \
    "$(fs_board '.issues[0] | {column, mark, action, chip}')"
}

t_fs_xxl_answer_starts_nothing() {
  # Given: a run of unlabeled #42, proposed xxl and answered yes
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  fs_go proposed acme/app 42 xxl; fs_go change acme/app answer 42 yes
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"starts":[]' "$out"
  eq card '{"mark":"you","action":"Cut it with /file-epic"}' "$(fs_board '.issues[0] | {mark, action}')"
}

t_fs_cut_xxl_brings_subs() {
  # Given: a run of #42, size/XXL, checked once; then cut into #43, size/S
  fs_setup; fs_issue 42 OPEN '["size/XXL"]'; fs_start 42; fs_go check acme/app
  fs_issue 43 OPEN '["size/S"]'; fs_issue 42 OPEN '[]' '[]' '[]' '[{"number":43,"state":"OPEN"}]'
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"joined":["acme/app#43"]' "$out"
  has stdout '"message":"/ship #43"' "$out"
}

t_fs_followup_joins() {
  # Given: a run of #42, since closed by merged PR 43, whose Follow-ups name #50, an open seed
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":"## Summary\n\nx\n\n## Follow-ups\n\n#50: retry the export\n"}'
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"; fs_issue 50 OPEN '["seed"]' '[]' '[]' '[]' "Retry the export"
  # When
  fs_go check acme/app
  # Then
  has stdout '"joined":["acme/app#50"]' "$out"
  has stdout '"message":"/grill #50"' "$out"
}

# fs_lib: a checkout of acme/lib at $T/dev/lib.
fs_lib() {
  git init -q -b main "$T/dev/lib"
  git -C "$T/dev/lib" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/dev/lib" remote add origin https://github.com/acme/lib.git
}

# fs_lib_epic: a run of epic acme/app#70 whose open sub-issue acme/lib#5 is
# an S ticket, with a checkout of acme/lib.
fs_lib_epic() {
  fs_setup; fs_lib
  fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":5,"state":"OPEN","repository":{"nameWithOwner":"acme/lib"}}]' "Order export"
  FS_REPO=lib fs_issue 5 OPEN '["size/S"]' '[]' '[]' '[]' "Shared parser"
  fs_start 70
}

t_fs_other_repo_part_starts() {
  # Given: epic acme/app#70, whose open sub-issue acme/lib#5 is an S ticket
  fs_lib_epic
  # When
  fs_go check acme/app
  # Then
  eq ref acme/lib#5 "$(jq -r '.starts[0].ref' <<<"$out")"
  eq path "$T/dev/lib" "$(jq -r '.starts[0].path' <<<"$out")"
  eq board '{"label":"lib#5","url":"https://github.com/acme/lib/issues/5"}' \
    "$(fs_board '.issues[] | select(.ref == "acme/lib#5") | {label, url}')"
}

t_fs_other_repo_adds_project() {
  # Given: epic acme/app#70, whose part acme/lib#5 is an S ticket, in a folder that is no T3 project yet
  fs_lib_epic; echo "$T/dev/lib" > "$T/no-project"
  # When
  fs_go check acme/app
  # Then
  has log "project add $T/dev/lib" "$(cat "$T/t3.log")"
  eq ref acme/lib#5 "$(jq -r '.starts[0].ref' <<<"$out")"
}

t_fs_other_repo_thread_status() {
  # Given: acme/lib#5's thread t9 started in acme/lib's project, where T3 shows it waiting
  fs_lib_epic; fs_go check acme/app
  fs_go started acme/app acme/lib#5 ticket t9 link9; eq started 0 "$code"
  echo '[{"threadId":"t9","status":"waiting"}]' > "$T/t3-threads.lib.json"
  # When
  fs_go check acme/app
  # Then
  eq status waiting "$(jq -r '.issues[] | select(.ref == "acme/lib#5") | .thread_status' <<<"$out")"
}

t_fs_other_repo_unreadable_asks() {
  # Given: epic acme/app#70 with part acme/lib#5, and #71 an S ticket in the set; acme/lib will not read
  fs_setup; fs_lib
  fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":5,"state":"OPEN","repository":{"nameWithOwner":"acme/lib"}}]' "Order export"
  fs_issue 71 OPEN '["size/S"]'
  fs_start 70 71
  echo "HTTP 404: Could not resolve to a Repository" > "$FAKE_GH/graphql.lib.fail"
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  eq starts '["acme/app#71"]' "$(jq -c '[.starts[].ref]' <<<"$out")"
  eq card '{"mark":"you","action":"could not read acme/lib: HTTP 404: Could not resolve to a Repository"}' \
    "$(fs_board '.issues[] | select(.ref == "acme/lib#5") | {mark, action}')"
}

t_fs_other_repo_no_checkout_asks() {
  # Given: epic acme/app#70, whose part acme/lib#5 is an S ticket, and no checkout of acme/lib
  fs_lib_epic; rm -rf "$T/dev/lib"
  # When
  fs_go check acme/app
  # Then
  eq starts '[]' "$(jq -c .starts <<<"$out")"
  eq mark you "$(fs_board -r '.issues[] | select(.ref == "acme/lib#5") | .mark')"
  has action "no checkout of acme/lib under" "$(fs_board -r '.issues[] | select(.ref == "acme/lib#5") | .action')"
}

t_fs_other_repo_followup_joins() {
  # Given: a run of #42, since closed by acme/lib's PR 9, whose Follow-ups name #12, open in acme/lib
  local pr='{"number":9,"url":"https://github.com/acme/lib/pull/9","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":"## Follow-ups\n- #12: tidy\n"}'
  fs_setup; fs_lib; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"; FS_REPO=lib fs_issue 12 OPEN '["seed"]'
  # When
  fs_go check acme/app
  # Then
  eq joined '["acme/lib#12"]' "$(jq -c .joined <<<"$out")"
}

t_fs_other_repo_blocker_label() {
  # Given: a run of #42, size/S, blocked by open acme/lib#5
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":5,"state":"OPEN","repository":{"nameWithOwner":"acme/lib"}}]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq blocked_by '["acme/lib#5"]' "$(jq -c '.issues[0].blocked_by' <<<"$out")"
  eq action 'blocked by lib#5' "$(fs_card 42 | jq -r .action)"
}

# fs_lib_run [thread] [started_at]: a live run of acme/lib#5 that started
# 2026-11-01, or at the given time, with a started thread for #5 when the
# thread is not "".
fs_lib_run() {
  local f
  fs_go start acme/lib --name "#5" --thread f2 --env e1 5; eq "lib start exit" 0 "$code"
  f="$(ls -1d "$T"/orchestrate/acme-lib/*/ | sort | tail -1)state.json"
  jq -c --arg t "${1:-}" --arg at "${2:-2026-11-01T00:00:00Z}" '.started_at = $at
    | if $t == "" then . else .threads += [{ref: "acme/lib#5", stage: "ticket", thread: $t, status: "started", command: "ship"}] end' \
    "$f" > "$f.new" && mv "$f.new" "$f"
}

t_fs_owned_by_other_run() {
  # Given: a live acme/lib run with a thread for acme/lib#5, and a later acme/app run whose epic holds it
  fs_lib_epic; fs_lib_run t5
  # When
  fs_go check acme/app
  # Then
  eq starts '[]' "$(jq -c .starts <<<"$out")"
  has wait 'owned by [🧭 #5](t3-thread://v1/f2)' "$(jq -r '.issues[] | select(.ref == "acme/lib#5") | .wait' <<<"$out")"
}

t_fs_two_runs_one_start() {
  # Given: a live acme/lib run holding acme/lib#5 with no thread, and a later acme/app run whose epic holds it
  fs_lib_epic; fs_lib_run
  # When
  fs_go check acme/app; local app="$out"
  fs_go check acme/lib
  # Then
  eq "app starts" '[]' "$(jq -c .starts <<<"$app")"
  eq "lib starts" '["acme/lib#5"]' "$(jq -c '[.starts[].ref]' <<<"$out")"
}

t_fs_same_second_runs_one_owner() {
  # Given: a paused acme/app run whose epic holds acme/lib#5, after a check; an
  # acme/lib run of #5, started the same second, with no thread for it
  fs_lib_epic; fs_go timer acme/app pause; fs_go check acme/app
  fs_lib_run "" "$(fs_state -r .started_at)"
  # When
  fs_go check acme/lib
  # Then: acme/app sorts first, so the lib run waits on it
  eq starts '[]' "$(jq -c .starts <<<"$out")"
  has wait 'owned by [🧭 #70]' "$(jq -r '.issues[] | select(.ref == "acme/lib#5") | .wait' <<<"$out")"
}

t_fs_check_waits_for_claims_lock() {
  # Given: the run of epic acme/app#70 with part acme/lib#5; another run's check holds the claims lock
  local holder done=""
  fs_lib_epic
  # The check must really wait, so the fake no-op sleep goes.
  rm "$T/bin/sleep"
  /bin/sleep 30 & holder=$!
  mkdir "$T/orchestrate/.claims.lock"; echo "$holder" > "$T/orchestrate/.claims.lock/pid"
  # When
  ( fs_go check acme/app; echo "$code" > "$T/check.code"; printf '%s' "$out" > "$T/check.out" ) &
  # A check alone takes about a second here; it must still wait at 3.
  /bin/sleep 3
  [ -e "$T/check.code" ] || done=no
  rm -rf "$T/orchestrate/.claims.lock"; kill "$holder"
  wait
  # Then
  eq "waited" no "$done"
  eq exit 0 "$(cat "$T/check.code")"
  eq starts '["acme/lib#5"]' "$(jq -c '[.starts[].ref]' "$T/check.out")"
}

t_fs_ref_forms() {
  # Given: the run of epic acme/app#70 with part acme/lib#5
  fs_lib_epic; fs_go check acme/app
  # When
  fs_go change acme/app add acme/lib#6; eq "owner/repo#n" 0 "$code"
  fs_go change acme/app add lib#7; eq "repo#n" 0 "$code"
  fs_go change acme/app add 8
  # Then
  eq exit 0 "$code"
  eq set '["acme/lib#6","acme/lib#7","acme/app#8"]' "$(fs_state '.set[-3:]')"
}

t_fs_ref_any_case() {
  # Given: the run of epic acme/app#70, whose part acme/lib#5 joined by GitHub's spelling
  fs_lib_epic; fs_go check acme/app
  # When
  fs_go change acme/app remove Acme/Lib#5
  # Then
  eq exit 0 "$code"
  eq set '["acme/app#70"]' "$(fs_state .set)"
  eq removed '["acme/lib#5"]' "$(fs_state .removed)"
}

t_fs_ref_unknown_repo() {
  # Given: the run of epic acme/app#70 with part acme/lib#5
  fs_lib_epic; fs_go check acme/app
  # When
  fs_go change acme/app add zed#6
  # Then
  eq exit 1 "$code"
  eq stderr "stop: no single repo named zed in this run; say owner/zed#6" "$(tail -1 <<<"$err")"
}

t_fs_add_to_set() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go change acme/app add 43
  # Then
  eq exit 0 "$code"
  eq set '["acme/app#42","acme/app#43"]' "$(fs_state .set)"
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
  eq sets '{"set":["acme/app#70"],"removed":["acme/app#71"]}' "$(fs_state '{set, removed}')"
}

t_fs_ship_merge_one() {
  # Given: a run of #42, size/S, set to ship merge
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go change acme/app ship merge 42
  eq "ship exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"command":"ship","mode":"merge"' "$out"
  has stdout '"message":"/ship --merge #42"' "$out"
}

t_fs_ship_merge_all() {
  # Given: a run of #42 and #43; #42's ticket thread t42 started with no mode
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '["size/S"]'; fs_start 42 43; fs_record 42 ticket t42
  # When
  fs_go change acme/app ship merge all
  # Then
  eq exit 0 "$code"
  eq ship '{"acme/app#42":"","default":"merge"}' "$(fs_state .ship)"
}

t_fs_ship_started() {
  # Given: #42's ticket thread t42 started with no mode
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42
  # When
  fs_go change acme/app ship merge 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has started; it ships with /ship" "$err"
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
  has stdout "\"paths\":[\"$T/dev/app\"]" "$out"
  eq status done "$(fs_state -r .status)"
}

t_fs_done_starts_retro() {
  # Given: a run of #42, which went from bug (t1) to ticket (t2) and is now closed by merged PR 43
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["bug"]'; fs_start 42; fs_record 42 bug t1; fs_record 42 ticket t2
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  # When
  fs_go check acme/app
  # Then
  has retro '"thread_title":"retro: #42","message":"/retrospect run '"$(ls -1d "$T"/orchestrate/acme-app/*/ | sort | tail -1 | sed 's:/$::')"'"' "$out"
  lacks retro '"runtime_mode"' "$out"
}

t_fs_done_removed_no_retro() {
  # Given: a run of #42 and #44, #44 removed, and #42 closed by merged PR 43
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 42 OPEN '["bug"]'; fs_start 42 44; fs_go change acme/app remove 44
  fs_record 42 bug t1; fs_record 42 ticket t2
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":true' "$out"
  has stdout '"removed":["acme/app#44"]' "$out"
  eq line false "$(jq -c 'has("retro")' <<<"$out")"
}

t_fs_sync_gh_fails() {
  # Given: a run of #42, and gh cannot read the repo
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  printf 'HTTP 502: Bad Gateway\n' > "$FAKE_GH/repo-view.fail"
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: acme/app not updated: gh could not name the default branch: HTTP 502: Bad Gateway" "$out"
}

t_fs_sync_fast_forwards() {
  # Given: a run of #42; origin's main is one commit ahead of the checked-out main
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  local was; was="$(fs_short "$T/dev/app" main)"
  fs_push a.txt one
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main fast-forwarded $was..$(fs_short "$T/other" main)" "$out"
  eq main "$(git -C "$T/other" rev-parse main)" "$(git -C "$T/dev/app" rev-parse main)"
}

t_fs_sync_each_repo() {
  # Given: a run with threads in acme/app and acme/lib; each origin's main is one commit ahead
  fs_setup; fs_lib; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  git clone -q --bare "$T/dev/lib" "$T/remote-lib.git"
  git -C "$T/dev/lib" config url."$T/remote-lib.git".insteadOf https://github.com/acme/lib.git
  git -C "$T/dev/lib" fetch -q origin
  git clone -q "$T/remote-lib.git" "$T/other-lib"
  fs_set_state --arg app "$T/dev/app" --arg lib "$T/dev/lib" '.threads += [
    {ref: "acme/app#42", repo: "acme/app", path: $app, stage: "ticket", thread: "t1", status: "started"},
    {ref: "acme/lib#5", repo: "acme/lib", path: $lib, stage: "ticket", thread: "t2", status: "started"}]'
  local was_app was_lib
  was_app="$(fs_short "$T/dev/app" main)"; was_lib="$(fs_short "$T/dev/lib" main)"
  fs_push a.txt one
  printf 'two\n' > "$T/other-lib/b.txt"; git -C "$T/other-lib" add b.txt
  git -C "$T/other-lib" -c user.email="t""@""example.invalid" -c user.name=t commit -q -m two
  git -C "$T/other-lib" push -q origin main
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main fast-forwarded $was_app..$(fs_short "$T/other" main)
lib: main fast-forwarded $was_lib..$(fs_short "$T/other-lib" main)" "$out"
}

t_fs_sync_fetch_fails() {
  # Given: as above, and origin's URL now reaches no repo
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  local was; was="$(git -C "$T/dev/app" rev-parse main)"
  fs_push a.txt one
  git -C "$T/dev/app" config --unset url."$T/remote.git".insteadOf
  git -C "$T/dev/app" config url."$T/gone.git".insteadOf https://github.com/acme/app.git
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  has stdout "app: main not updated: fetch failed: " "$out"
  eq main "$was" "$(git -C "$T/dev/app" rev-parse main)"
}

t_fs_sync_up_to_date() {
  # Given: a run of #42; origin's main is the checked-out main
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main up to date at $(fs_short "$T/dev/app" main)" "$out"
}

t_fs_sync_own_commits() {
  # Given: a run of #42; origin's main has a.txt, and the local main has its own commit mine
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  fs_push a.txt one
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m mine
  local mine; mine="$(git -C "$T/dev/app" rev-parse main)"
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main not updated: it has commits origin/main lacks" "$out"
  eq main "$mine" "$(git -C "$T/dev/app" rev-parse main)"
}

t_fs_sync_edits_in_the_way() {
  # Given: a run of #42 synced to origin's a.txt "one"; origin then writes "two",
  # and the checkout has an edit "mine" to a.txt, not committed
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  fs_push a.txt one
  fs_go sync acme/app
  local one; one="$(git -C "$T/dev/app" rev-parse main)"
  fs_push a.txt two
  printf 'mine\n' > "$T/dev/app/a.txt"
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main not updated: error: Your local changes to the following files would be overwritten by merge:" "$out"
  eq edit mine "$(cat "$T/dev/app/a.txt")"
  eq main "$one" "$(git -C "$T/dev/app" rev-parse main)"
}

t_fs_sync_edits_in_the_way_autostash() {
  # Given: as in the edits-in-the-way case, with merge.autoStash on in the checkout
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  fs_push a.txt one
  fs_go sync acme/app
  local one; one="$(git -C "$T/dev/app" rev-parse main)"
  fs_push a.txt two
  printf 'mine\n' > "$T/dev/app/a.txt"
  git -C "$T/dev/app" config merge.autoStash true
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main not updated: error: Your local changes to the following files would be overwritten by merge:" "$out"
  eq main "$one" "$(git -C "$T/dev/app" rev-parse main)"
}

t_fs_sync_ignored_file_in_the_way() {
  # Given: a run of #42; the checkout ignores b.txt and holds its own b.txt,
  # and origin's main starts tracking a b.txt
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  echo b.txt >> "$T/dev/app/.git/info/exclude"
  printf 'mine\n' > "$T/dev/app/b.txt"
  local was; was="$(git -C "$T/dev/app" rev-parse main)"
  fs_push b.txt theirs
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  has stdout "app: main not updated: " "$out"
  eq file mine "$(cat "$T/dev/app/b.txt")"
  eq main "$was" "$(git -C "$T/dev/app" rev-parse main)"
}

t_fs_sync_narrow_fetch_refspec() {
  # Given: a run of #42; the checkout's fetch refspec names only another
  # branch, and origin's main is one commit ahead
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  git -C "$T/dev/app" config remote.origin.fetch '+refs/heads/release:refs/remotes/origin/release'
  local was; was="$(fs_short "$T/dev/app" main)"
  fs_push a.txt one
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main fast-forwarded $was..$(fs_short "$T/other" main)" "$out"
}

t_fs_sync_other_branch() {
  # Given: a run of #42; the checkout is on feat/x, and origin's main is one commit ahead
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_remote
  git -C "$T/dev/app" switch -q -c feat/x
  local was; was="$(fs_short "$T/dev/app" main)"
  fs_push a.txt one
  # When
  fs_go sync acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "app: main fast-forwarded $was..$(fs_short "$T/other" main)" "$out"
  eq branch feat/x "$(git -C "$T/dev/app" branch --show-current)"
  eq main "$(git -C "$T/other" rev-parse main)" "$(git -C "$T/dev/app" rev-parse main)"
}

# fs_done_epic: a done run of epic #70 "Order export", open, whose sub-issues
# #71 and #72 are closed, after the check that ended it.
fs_done_epic() {
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"CLOSED"},{"number":72,"state":"CLOSED"}]' "Order export"
  fs_issue 71 CLOSED '["size/S"]'; fs_issue 72 CLOSED '["size/S"]'; fs_start 70 71 72
  fs_go check acme/app
}

t_fs_close_epics_closes_done_epic() {
  # Given: a done run of epic #70, open, whose sub-issues #71 and #72 are closed
  fs_done_epic; printf '' > "$FAKE_GH/issue-close.json"
  # When
  fs_go close-epics acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "#70 closed" "$out"
  eq "close args" "issue close 70 --repo acme/app --reason completed" "$(cat "$FAKE_GH/issue-close.args")"
}

t_fs_close_epics_not_done() {
  # Given: a running run of epic #70, open, whose sub-issue #71 is open, after a check
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"OPEN"}]' "Order export"
  fs_issue 71 OPEN '["size/S"]'; fs_start 70 71
  fs_go check acme/app; printf '' > "$FAKE_GH/issue-close.json"
  # When
  fs_go close-epics acme/app
  # Then
  eq exit 1 "$code"
  eq stderr "stop: the run in acme/app is not done; close-epics runs only at its end" "$err"
  eq "close calls" no "$([ -e "$FAKE_GH/issue-close.calls" ] && echo yes || echo no)"
}

t_fs_close_epics_refused() {
  # Given: a done run of epic #70, open, whose sub-issues are closed; GitHub refuses the close
  fs_done_epic; printf 'GraphQL: Resource not accessible by integration\n' > "$FAKE_GH/issue-close.fail"
  # When
  fs_go close-epics acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "#70 not closed: GraphQL: Resource not accessible by integration" "$out"
}

t_fs_close_epics_sub_reopened() {
  # Given: a done run of epic #70; its sub-issue #71 opened again after the last check
  fs_done_epic; printf '' > "$FAKE_GH/issue-close.json"
  fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"OPEN"},{"number":72,"state":"CLOSED"}]' "Order export"
  # When
  fs_go close-epics acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "#70 not closed: #71 is still open" "$out"
  eq "close calls" no "$([ -e "$FAKE_GH/issue-close.calls" ] && echo yes || echo no)"
}

# fs_nested_epic: a run of epic #70 "Order export", whose open sub-issue is
# epic #71 "Inner", whose one sub-issue #72 is closed.
fs_nested_epic() {
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"OPEN"}]' "Order export"
  fs_issue 71 OPEN '[]' '[]' '[]' '[{"number":72,"state":"CLOSED"}]' "Inner"
  fs_issue 72 CLOSED '["size/S"]'; fs_start 70
}

t_fs_nested_epic_done() {
  # Given: epic #70 over epic #71 over closed #72
  fs_nested_epic
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":true' "$out"
}

t_fs_close_epics_inner_first() {
  # Given: the done run of epic #70 over epic #71 over closed #72; the
  # second read of the close shows #71 closed, as GitHub would after its close
  local n
  fs_nested_epic; fs_go check acme/app; printf '' > "$FAKE_GH/issue-close.json"
  n="$(cat "$FAKE_GH/graphql.calls")"
  cp "$FAKE_GH/graphql.json" "$T/graphql.keep"
  fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"CLOSED"}]' "Order export"
  fs_issue 71 CLOSED '[]' '[]' '[]' '[{"number":72,"state":"CLOSED"}]' "Inner"
  mv "$FAKE_GH/graphql.json" "$FAKE_GH/graphql.$((n + 2)).json"; mv "$T/graphql.keep" "$FAKE_GH/graphql.json"
  # When
  fs_go close-epics acme/app
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf '#71 closed\n#70 closed')" "$out"
}

t_fs_epic_done() {
  # Given: a run of epic #70, open, whose sub-issues #71 and #72 are closed
  fs_setup; fs_issue 70 OPEN '[]' '[]' '[]' '[{"number":71,"state":"CLOSED"},{"number":72,"state":"CLOSED"}]' "Order export"
  fs_issue 71 CLOSED '["size/S"]'; fs_issue 72 CLOSED '["size/S"]'; fs_start 70 71 72
  # When
  fs_go check acme/app
  # Then
  has stdout '"done":true' "$out"
  has stdout '"label":"#70","url":"https://github.com/acme/app/issues/70","title":"Order export","stage":"epic"' "$out"
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
  # Given: issue #42, size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'
  # When
  fs_start 42
  # Then
  eq timer '{"every":5,"fails":0}' "$(fs_state .timer)"
}

t_fs_interval_min_one() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go timer acme/app --every 0
  # Then
  eq exit 64 "$code"
  eq stderr "stop: check every takes 1 minute or more"$'\n'"usage: orchestrate.sh timer <owner/repo> --every <min> | pause | resume | stop" "$err"
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

t_fs_first_check_all_changed() {
  # Given: a run of #42, a manual task, never checked
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq check '{"changed":true,"issues":[{"number":42,"changed":true}]}' "$(jq -c '{changed, issues: [.issues[] | {number, changed}]}' <<<"$out")"
}

t_fs_second_check_quiet() {
  # Given: a run of unlabeled #42, answered skip, checked once
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 skip
  fs_go check acme/app
  # When
  fs_go check acme/app
  # Then
  eq check '{"changed":false,"issues":[false]}' "$(jq -c '{changed, issues: [.issues[] | .changed]}' <<<"$out")"
}

t_fs_status_change_marks_issue() {
  # Given: #42's ticket thread t42 running and checked, #43 unlabeled and
  # answered skip; then t42 waits for the user
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '["p1"]'; fs_start 42 43
  fs_go change acme/app answer 43 skip
  fs_record 42 ticket t42
  echo '[{"threadId":"t42","status":"running"}]' > "$T/t3-threads.json"
  fs_go check acme/app
  echo '[{"threadId":"t42","status":"waiting"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq check '{"changed":true,"issues":[{"number":42,"changed":true},{"number":43,"changed":false}]}' \
    "$(jq -c '{changed, issues: [.issues[] | {number, changed}]}' <<<"$out")"
}

t_fs_start_marks_changed() {
  # Given: a run of #42, size/S, checked while paused, then resumed
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go timer acme/app pause; fs_go check acme/app; fs_go timer acme/app resume
  # When
  fs_go check acme/app
  # Then
  eq check '{"changed":true,"starts":1,"issues":[true]}' "$(jq -c '{changed, starts: (.starts | length), issues: [.issues[] | .changed]}' <<<"$out")"
}

# fs_sends: the lines the fake t3 sent, or "none" when it sent nothing.
fs_sends() { if [ -e "$T/t3-sends.log" ]; then cat "$T/t3-sends.log"; else echo none; fi; }

t_fs_watch_quiet() {
  # Given: a run of unlabeled #42, answered skip
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 skip
  # When
  fs_go watch acme/app --once
  # Then
  eq exit 0 "$code"
  eq line '{"wake":[],"woke":false,"sent":[]}' "$out"
  eq sends none "$(fs_sends)"
}

t_fs_watch_claims_nothing() {
  # Given: a run of #42, size/S; the orchestrator thread f1 is running
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  echo '[{"threadId":"f1","status":"running"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq state '{"threads":[],"seen":null,"fails":0,"timed":true}' \
    "$(fs_state '{threads, seen, fails: .timer.fails, timed: (.timer.checked_at != null)}')"
}

t_fs_watch_board() {
  # Given: a run of #42, size/S; the orchestrator thread f1 is running
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  echo '[{"threadId":"f1","status":"running"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq board '[{"number":42,"mark":"blocked","action":"starts at the next check"}]' "$(fs_board '[.issues[] | {number, mark, action}]')"
}

t_fs_watch_paused() {
  # Given: a paused run of #42, size/S
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go timer acme/app pause
  # When
  fs_go watch acme/app --once
  # Then
  eq exit 3 "$code"
  eq stdout "" "$out"
  eq cards false "$(fs_board 'has("issues")')"
}

# fs_orchestrator <status>: T3 lists the orchestrator thread f1 with that status.
fs_orchestrator() { jq -cn --arg s "$1" '[{threadId: "f1", status: $s}]' > "$T/t3-threads.json"; }

t_fs_watch_wakes_start() {
  # Given: a run of #42, size/S; the orchestrator thread f1 finished its turn
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_orchestrator completed
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["start #42"],"woke":true,"sent":[]}' "$out"
  eq sends "thread send f1 /orchestrate check" "$(fs_sends)"
  eq threads '[]' "$(fs_state .threads)"
}

t_fs_watch_running_not_woken() {
  # Given: a run of #42, size/S; the orchestrator thread f1 is running
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_orchestrator running
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["start #42"],"woke":false,"sent":[]}' "$out"
  eq sends none "$(fs_sends)"
}

t_fs_watch_waiting_not_woken() {
  # Given: a run of #42, size/S; the orchestrator thread f1 waits for the user
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_orchestrator waiting
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["start #42"],"woke":false,"sent":[]}' "$out"
  eq sends none "$(fs_sends)"
}

t_fs_watch_wakes_propose() {
  # Given: a run of #44, unlabeled, with no proposal yet
  fs_setup; fs_issue 44 OPEN '[]'; fs_start 44
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["propose #44"],"woke":true,"sent":[]}' "$out"
}

t_fs_watch_wakes_done() {
  # Given: a run of #42, closed since the start
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_issue 42 CLOSED '["size/S"]'
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["done"],"woke":true,"sent":[]}' "$out"
  eq status '"running"' "$(fs_state .status)"
}

t_fs_watch_wake_retried() {
  # Given: a run of #42, size/S; a first watcher check whose wake T3 refused
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'connect ECONNREFUSED\n' > "$T/t3-send.fail"; fs_go watch acme/app --once; rm "$T/t3-send.fail"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["start #42"],"woke":true,"sent":[]}' "$out"
  eq sends "thread send f1 /orchestrate check" "$(fs_sends)"
}

t_fs_watch_fail_counts() {
  # Given: a run of #42, size/S; gh is logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go watch acme/app --once
  # Then
  eq exit 1 "$code"
  eq stderr "stop: check failed: HTTP 401: Bad credentials" "$err"
  eq state '{"threads":[],"fails":1}' "$(fs_state '{threads, fails: .timer.fails}')"
  eq sends none "$(fs_sends)"
}

t_fs_watch_third_fail_wakes() {
  # Given: a run of #42, size/S; gh is logged out, and two watcher checks failed
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  fs_go watch acme/app --once; fs_go watch acme/app --once
  # When
  fs_go watch acme/app --once; fs_go watch acme/app --once
  # Then
  eq sends "thread send f1 /orchestrate check" "$(fs_sends)"
  eq state '{"fails":4,"alerted":true}' "$(fs_state '{fails: .timer.fails, alerted: .timer.alerted}')"
}

t_fs_resume_clears_alert() {
  # Given: a stopped run of #42 after three failed checks that woke the thread
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  fs_set_state '.timer.fails = 3 | .timer.alerted = true'; fs_go timer acme/app stop
  # When
  fs_go resume acme/app --thread f1 --env e1
  # Then
  eq state '{"fails":0,"alerted":false}' "$(fs_state '{fails: .timer.fails, alerted: .timer.alerted}')"
}

t_fs_watch_good_clears() {
  # Given: a run of #42, a manual task, after two failed checks that woke the thread
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  fs_set_state '.timer.fails = 2 | .timer.alerted = true'
  # When
  fs_go watch acme/app --once
  # Then
  eq state '{"fails":0,"alerted":false}' "$(fs_state '{fails: .timer.fails, alerted: .timer.alerted}')"
}

# fs_real_wait: the fake sleep waits 30 seconds for a wait of a minute or
# more, as the watcher loop's, and returns at once for a shorter one.
fs_real_wait() {
  printf '#!/usr/bin/env bash\n[ "${1%%%%.*}" -lt 60 ] || exec /bin/sleep 30\n' > "$T/bin/sleep"
  chmod +x "$T/bin/sleep"
}

# fs_gone <pid>: yes once the process has ended, within 3 seconds, else no.
fs_gone() {
  local i
  for i in $(seq 30); do kill -0 "$1" 2>/dev/null || { echo yes; return; }; /bin/sleep 0.1; done
  echo no
}

t_fs_watch_starts() {
  # Given: a run of #42, a manual task; the loop's wait is real
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_real_wait
  # When
  fs_go watch acme/app
  # Then
  local pid; pid="$(jq -r .pid <<<"$out")"
  eq exit 0 "$code"
  eq alive yes "$(kill -0 "$pid" 2>/dev/null && echo yes || echo no)"
  eq state "$pid" "$(fs_state .timer.watcher.pid)"
  fs_go timer acme/app stop
}

t_fs_watch_replaces() {
  # Given: a run of #42 with a watcher
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_real_wait
  fs_go watch acme/app; local first; first="$(jq -r .pid <<<"$out")"
  # When
  fs_go watch acme/app
  # Then
  local second; second="$(jq -r .pid <<<"$out")"
  eq first yes "$(fs_gone "$first")"
  eq second yes "$(kill -0 "$second" 2>/dev/null && echo yes || echo no)"
  eq state "$second" "$(fs_state .timer.watcher.pid)"
  fs_go timer acme/app stop
}

t_fs_pause_ends_watcher() {
  # Given: a run of #42 with a watcher
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_real_wait
  fs_go watch acme/app; local pid; pid="$(jq -r .pid <<<"$out")"
  # When
  fs_go timer acme/app pause
  # Then
  eq gone yes "$(fs_gone "$pid")"
  eq state null "$(fs_state .timer.watcher)"
}

t_fs_stop_ends_watcher() {
  # Given: a run of #42 with a watcher
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_real_wait
  fs_go watch acme/app; local pid; pid="$(jq -r .pid <<<"$out")"
  # When
  fs_go timer acme/app stop
  # Then
  eq gone yes "$(fs_gone "$pid")"
  eq state null "$(fs_state .timer.watcher)"
}

t_fs_pause_spares_other() {
  # Given: a run of #42 whose watcher pid is a process that is no watcher
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  local other; /bin/sleep 30 & other=$!
  fs_set_state ".timer.watcher = {token: \"x\", pid: $other}"
  # When
  fs_go timer acme/app pause
  # Then
  eq alive yes "$(kill -0 "$other" 2>/dev/null && echo yes || echo no)"
  kill "$other"
}

t_fs_watch_old_token() {
  # Given: a run of #42, size/S, whose watcher has the token a
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_set_state '.timer.watcher = {token: "a", pid: null}'
  # When
  fs_go watch acme/app --once --token b
  # Then
  eq exit 3 "$code"
  eq stdout "" "$out"
  eq cards false "$(fs_board 'has("issues")')"
  eq sends none "$(fs_sends)"
}

t_fs_watch_loop_ends() {
  # Given: a paused run of #42 whose watcher has the token t
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_go timer acme/app pause
  fs_set_state '.timer.watcher = {token: "t", pid: null}'
  # When
  fs_go watch acme/app --loop "$(fs_run)" t
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_fs_watch_paused_stops() {
  # Given: a paused run of #42
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42; fs_go timer acme/app pause
  # When
  fs_go watch acme/app
  # Then
  eq exit 1 "$code"
  eq stderr "stop: the run in acme/app is paused; say resume" "$err"
}

t_fs_timer_no_task() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go timer acme/app --task s1
  # Then
  eq exit 64 "$code"
  eq stderr "usage: orchestrate.sh timer <owner/repo> --every <min> | pause | resume | stop" "$err"
}

t_fs_thread_kept() {
  # Given: a stopped run of #42 from the orchestrator thread f1
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  eq before '"f1"' "$(fs_state .thread)"
  fs_go timer acme/app stop
  # When
  fs_go resume acme/app --thread f2 --env e1
  # Then
  eq after '"f2"' "$(fs_state .thread)"
}

t_fs_lock_live_stops() {
  # Given: a run of #42 whose lock a live process holds (this shell; the
  # fake sleep returns at once)
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  mkdir "$(fs_run)/.lock"; echo $$ > "$(fs_run)/.lock/pid"
  # When
  fs_go change acme/app add 43
  # Then
  eq exit 1 "$code"
  eq stderr "stop: the run of acme/app is busy: another orchestrate.sh holds its lock" "$err"
  eq set '["acme/app#42"]' "$(fs_state .set)"
}

t_fs_lock_dead_taken() {
  # Given: a run of #42 whose lock a process that has ended holds
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  local dead; /bin/sleep 0 & dead=$!; wait "$dead"
  mkdir "$(fs_run)/.lock"; echo "$dead" > "$(fs_run)/.lock/pid"
  # When
  fs_go change acme/app add 43
  # Then
  eq exit 0 "$code"
  eq set '["acme/app#42","acme/app#43"]' "$(fs_state .set)"
  eq lock no "$([ -e "$(fs_run)/.lock" ] && echo yes || echo no)"
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
  eq stderr "stop: a live run in acme/app: [🧭 #42](t3-thread://v1/f1)" "$err"
  eq runs 1 "$(ls -1 "$T/orchestrate/acme-app" | wc -l | tr -d ' ')"
}

t_fs_resume_newest() {
  # Given: a stopped run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_go timer acme/app stop
  # When
  fs_go resume acme/app --thread f2 --env e1
  # Then
  eq exit 0 "$code"
  has stdout '"name":"#42","every":5}' "$out"
  eq state '{"status":"running","link":"[🧭 #42](t3-thread://v1/f2)"}' "$(fs_state '{status, link}')"
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
  has stdout '"propose":["acme/app#42"]' "$out"
  has stdout '"starts":[]' "$out"
}

t_fs_added_unlabeled_listed() {
  # Given: a run of #42 (size/S); #43, open, no label, added
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_issue 43 OPEN '[]'; fs_start 42; fs_go change acme/app add 43
  # When
  fs_go check acme/app
  # Then
  has stdout '"propose":["acme/app#43"]' "$out"
  has stdout '"message":"/ship #42"' "$out"
}

t_fs_proposed_route_word() {
  # Given: a run of #42, open, labelled only p1
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When: a word that is no route, then unsure twice
  fs_go proposed acme/app 42 to-epic
  eq "to-epic exit" 64 "$code"
  eq stderr "usage: orchestrate.sh proposed <owner/repo> <issue> grill|triage|ship|ready-pr|task|close|xxl|unsure [--size XS|S|M|L|XL]" "$err"
  fs_go proposed acme/app 42 unsure
  eq "first exit" 0 "$code"
  fs_go proposed acme/app 42 unsure
  eq "second exit" 0 "$code"
  eq proposals '{"acme/app#42":{"route":"unsure","answer":null}}' "$(fs_state .proposals)"
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
  eq stdout '{"ref":"acme/app#42","label":"#42","route":"ship","size":"M","model":"opus","effort":"high"}' "$out"
  eq proposals '{"acme/app#42":{"route":"ship","answer":null,"size":"M"}}' "$(fs_state .proposals)"
}

t_fs_proposed_use_wins() {
  # Given: a run of unlabeled #42, max effort for all
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  fs_go change acme/app use all --effort max
  # When
  fs_go proposed acme/app 42 grill
  # Then
  eq exit 0 "$code"
  eq stdout '{"ref":"acme/app#42","label":"#42","route":"grill","size":null,"model":"opus","effort":"max"}' "$out"
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

t_fs_proposed_xxl_no_size() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 xxl --size L
  # Then
  eq exit 1 "$code"
  eq stderr "stop: a xxl proposal takes no --size" "$err"
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

t_fs_proposed_bad_size() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 ship --size huge
  # Then
  eq exit 64 "$code"
  eq stderr "usage: orchestrate.sh proposed <owner/repo> <issue> grill|triage|ship|ready-pr|task|close|xxl|unsure [--size XS|S|M|L|XL]" "$err"
}

t_fs_use_bad_effort() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go change acme/app use 42 --effort huge
  # Then
  eq exit 64 "$code"
  eq stderr "stop: --effort must be low, medium, high, xhigh, or max, got: huge"$'\n'"usage: orchestrate.sh change <owner/repo> use <issue>|all [--model M] [--effort E]" "$err"
}

t_fs_ship_bad_mode() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go change acme/app ship full 42
  # Then
  eq exit 64 "$code"
  eq stderr "usage: orchestrate.sh change <owner/repo> ship review|ready|merge <issue>|all" "$err"
}

t_fs_done_retro_row() {
  # Given: a run of #42, closed by merged PR 43, with no use pick
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["bug"]'; fs_start 42; fs_record 42 bug t1; fs_record 42 ticket t2
  fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  # When
  fs_go check acme/app
  # Then
  has retro '"retro":{"model":"opus","effort":"high","path":' "$out"
}

t_fs_proposed_no_model() {
  # Given: a run of unlabeled #42
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 close
  # Then
  eq exit 0 "$code"
  eq stdout '{"ref":"acme/app#42","label":"#42","route":"close","size":null,"model":null,"effort":null}' "$out"
}

t_fs_proposed_decide_stop() {
  # Given: a run of unlabeled #42, no PR closes it
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  # When
  fs_go proposed acme/app 42 ready-pr
  # Then
  eq exit 0 "$code"
  eq stdout '{"ref":"acme/app#42","label":"#42","route":"ready-pr","size":null,"model":null,"effort":null,"why":"#42 has no open PR"}' "$out"
  eq route '"ready-pr"' "$(fs_state '.proposals["acme/app#42"].route')"
}

t_fs_answer_keeps_size() {
  # Given: #42 proposed ship at size S
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 ship --size S
  # When
  fs_go change acme/app answer 42 yes
  # Then
  eq exit 0 "$code"
  eq proposals '{"acme/app#42":{"route":"ship","answer":"ship","size":"S"}}' "$(fs_state .proposals)"
}

t_fs_ship_proposal_size_launches() {
  # Given: unlabeled #42, proposed ship at size S, answered yes
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 ship --size S; fs_go change acme/app answer 42 yes
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"command":"ship","mode":"","model":"opus","model_from":"default","effort":"medium","effort_from":"default","reason":"answer ship, size S"' "$out"
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
  has stdout '"message":"/grill #42"' "$out"
  has stdout '"stage":"unlabeled"' "$out"
  eq threads '[{"ref":"acme/app#42","stage":"unlabeled","status":"pending"}]' "$(fs_state '[.threads[] | {ref, stage, status}]')"
}

t_fs_ship_answer_starts() {
  # Given: unlabeled #42, answered ship at size S with no proposal
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 ship --size S
  eq "answer exit" 0 "$code"
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/ship #42"' "$out"
}

t_fs_ready_to_build_ships() {
  # Given: a run of #42, open, ready-to-build with no size label
  fs_setup; fs_issue 42 OPEN '["ready-to-build"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"message":"/ship #42"' "$out"
  has stdout '"effort":"medium"' "$out"
  has stdout '"stage":"ticket"' "$out"
}

t_fs_ship_answer_needs_size() {
  # Given: a run of unlabeled #42, proposed grill, so the proposal holds no size
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  # When
  fs_go change acme/app answer 42 ship
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has no size for /ship: size it from the code, then answer ship --size XS|S|M|L|XL" "$err"
}

t_fs_yes_writes_labels() {
  # Given: unlabeled #42 to #45, proposed grill, triage, ship at S, and task
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_issue 43 OPEN '[]'; fs_issue 44 OPEN '[]'; fs_issue 45 OPEN '[]'
  fs_start 42 43 44 45
  fs_go proposed acme/app 42 grill; fs_go proposed acme/app 43 triage
  fs_go proposed acme/app 44 ship --size S; fs_go proposed acme/app 45 task
  # When
  fs_go change acme/app answer all yes
  # Then
  eq exit 0 "$code"
  eq stdout "labeled #42 seed
labeled #43 bug
labeled #44 size/S
labeled #45 manual" "$out"
  eq "first edit" "issue edit 42 --repo acme/app --add-label seed" "$(sed -n 1p "$FAKE_GH/issue-edit.args")"
}

t_fs_no_label_answers() {
  # Given: unlabeled #42 to #45
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_issue 43 OPEN '[]'; fs_issue 44 OPEN '[]'; fs_issue 45 OPEN '[]'
  fs_start 42 43 44 45
  local a got=""
  for a in "42 close" "43 skip" "44 ready-pr" "45 xxl"; do
    # When
    # shellcheck disable=SC2086 # the issue and the answer, as two words
    fs_go change acme/app answer $a
    got="$got[$code:$out]"
  done
  # Then
  eq answers "[0:][0:][0:][0:]" "$got"
  eq "edit calls" no "$([ -e "$FAKE_GH/issue-edit.calls" ] && echo yes || echo no)"
}

t_fs_refused_label_starts() {
  # Given: unlabeled #42, proposed grill; GitHub refuses the label
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  printf 'HTTP 403: Resource not accessible by integration\n' > "$FAKE_GH/issue-edit.fail"
  # When
  fs_go change acme/app answer 42 yes
  eq "answer exit" 0 "$code"
  eq "answer stdout" "not labeled #42: HTTP 403: Resource not accessible by integration" "$out"
  fs_go check acme/app
  # Then
  has stdout '"message":"/grill #42"' "$out"
}

t_fs_ship_answer_size_starts() {
  # Given: unlabeled #42, proposed grill
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  # When
  fs_go change acme/app answer 42 ship --size M
  eq "answer stdout" "labeled #42 size/M" "$out"
  eq proposal '{"route":"grill","answer":"ship","size":"M"}' "$(fs_state '.proposals["acme/app#42"]')"
  fs_go check acme/app
  # Then
  has stdout '"message":"/ship #42"' "$out"
  has stdout '"effort":"high"' "$out"
}

t_fs_second_answer_labels_again() {
  # Given: unlabeled #42, proposed grill, answered yes once
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill; fs_go change acme/app answer 42 yes
  # When
  fs_go change acme/app answer 42 yes
  # Then
  eq exit 0 "$code"
  eq stdout "labeled #42 seed" "$out"
  eq "edit calls" 2 "$(cat "$FAKE_GH/issue-edit.calls")"
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
  eq answers '{"acme/app#42":"grill","acme/app#43":"close","acme/app#44":null}' "$(fs_state '.proposals | map_values(.answer)')"
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
  has stdout '"blocked_by":["acme/app#41"]' "$out"
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
  fs_go timer acme/app stop; fs_go resume acme/app --thread f2 --env e1
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
  has stdout '"message":"/ship #42"' "$out"
}

t_fs_ship_started_answer() {
  # Given: unlabeled #42 answered ship and set to ready; its thread t42 started
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go change acme/app answer 42 ship --size S
  fs_go change acme/app ship ready 42; fs_record 42 unlabeled t42
  # When
  fs_go change acme/app ship merge 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has started; it ships with /ship --ready" "$err"
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
  eq exit 64 "$code"
  eq stderr "usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>..." "$err"
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

t_fs_bug_old_pr_chip() {
  # Given: a run from 2026-10-28T12:00:00Z; #42 labelled bug with open PR 43 from the day before
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-27T09:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["bug"]' '[]' "[$pr]"; fs_prs "$pr"; fs_start 42; fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  eq card '{"stage":"pr","chip":"bug"}' "$(fs_board '.issues[] | select(.number == 42) | {stage, chip}')"
}

# fs_thread <id> <status> [updated]: T3 lists one thread, made at 12:10, with
# its last update at <updated> when given.
fs_thread() {
  jq -cn --arg id "$1" --arg s "$2" --arg up "${3:-}" \
    '[{threadId: $id, status: $s, createdAt: "2026-10-28T12:10:00Z"} + (if $up == "" then {} else {updatedAt: $up} end)]' > "$T/t3-threads.json"
}

# ago <s>: the time <s> seconds before now, as T3 writes it, with milliseconds.
ago() { jq -nr --argjson s "$1" 'now - $s | strftime("%Y-%m-%dT%H:%M:%S.000Z")'; }

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

t_fs_board_paused_agent() {
  # Given: #42's ticket thread t42 completed its turn 2 minutes ago, with no new stage
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42; fs_thread t42 completed "$(ago 120)"
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"agent","action":"/ship"}' "$(fs_card 42)"
}

t_fs_board_quiet_yours() {
  # Given: #42's ticket thread t42 completed its turn 10 minutes ago, with no new stage
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42; fs_thread t42 completed "$(ago 600)"
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"No change: say restart #42"}' "$(fs_card 42)"
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

t_fs_waiting_task_no_turn() {
  # Given: #42 manual and waiting, whose task thread started; #43 manual
  fs_setup; fs_issue 42 OPEN '["manual","waiting"]'; fs_issue 43 OPEN '["manual"]'; fs_start 42 43
  fs_record 42 task t42
  # When
  fs_go check acme/app
  # Then
  has stdout '"message":"/complete-task --ready #43"' "$out"
  eq row '{"stage":"waiting","skill":null}' "$(jq -c '.issues[] | select(.number == 42) | {stage, skill}' <<<"$out")"
}

t_fs_board_waiting_task() {
  # Given: #42, manual and waiting
  fs_setup; fs_issue 42 OPEN '["manual","waiting"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Waits outside: say resume #42"}' "$(fs_card 42)"
}

t_fs_board_task_just_finished() {
  # Given: #42 manual, whose task thread t42 completed its turn 2 minutes ago
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  fs_record 42 task t42; fs_thread t42 completed "$(ago 120)"
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Open the thread: it waits for you"}' "$(fs_card 42)"
}

t_fs_board_ready_task() {
  # Given: #42 manual, whose task thread t42 started and completed its turn
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  fs_record 42 task t42; fs_thread t42 completed
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"you","action":"Open the thread: it waits for you"}' "$(fs_card 42)"
}

t_fs_board_task_starts() {
  # Given: #42, a manual task with no blocker
  fs_setup; fs_issue 42 OPEN '["manual"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"agent","action":"starting /complete-task"}' "$(fs_card 42)"
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
  # Given: #42's ship thread t42 runs since 12:10
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42 ship; fs_thread t42 running
  # When
  fs_go check acme/app
  # Then
  eq card '{"mark":"agent","action":"/ship","since":"2026-10-28T12:10:00Z"}' "$(fs_board '.issues[0] | {mark, action, since}')"
}

t_fs_board_claimed_starting() {
  # Given: #42, size/S, no thread yet
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go check acme/app
  # Then
  eq card '{"column":"build","mark":"agent","action":"starting /ship"}' "$(fs_card 42)"
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
  # Given: in Build, #42 blocked by open #9, #43 a ticket about to start, #44 a
  # ticket whose launch failed
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[{"number":9,"state":"OPEN"}]'; fs_issue 44 OPEN '["size/S"]'; fs_issue 43 OPEN '["size/S"]'
  fs_start 42 43 44
  fs_set_state '.threads += [{number: 44, stage: "ticket", thread: null, link: null, status: "failed", why: "no reply"}]'
  # When
  fs_go check acme/app
  # Then
  eq order '[44,43,42]' "$(fs_board '[.issues[] | .number]')"
}

t_fs_board_extra_chips() {
  # Given: #42 closed by merged PR 43, whose Follow-ups name #50, an open seed; #44 removed; #45 set to ship merge
  local pr='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"MERGED","createdAt":"2026-10-28T13:00:00Z","body":"## Follow-ups\n\n#50: retry the export\n"}'
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 45 OPEN '["size/S"]'; fs_issue 42 CLOSED '["size/S"]' '[]' "[$pr]"
  fs_issue 50 OPEN '["seed"]' '[]' '[]' '[]' "Retry the export"; fs_start 42 44 45
  fs_go change acme/app remove 44; fs_go change acme/app ship merge 45
  # When
  fs_go check acme/app
  # Then
  eq chips '[{"number":44,"removed":true,"made":false,"ship_mode":""},{"number":45,"removed":false,"made":false,"ship_mode":"merge"},{"number":50,"removed":false,"made":true,"ship_mode":""}]' \
    "$(fs_board '[.issues[] | select(.removed or .made or .ship_mode != "") | {number, removed, made, ship_mode}] | sort_by(.number)')"
}

t_fs_removed_starts_nothing() {
  # Given: a run of #42 and #44, both size/S, then #44 removed
  fs_setup; fs_issue 44 OPEN '["size/S"]'; fs_issue 42 OPEN '["size/S"]'; fs_start 42 44; fs_go change acme/app remove 44
  # When
  fs_go check acme/app
  # Then
  eq started '["acme/app#42"]' "$(fs_state '[.threads[] | .ref]')"
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
  fs_go check acme/app; local before; before="$(fs_board .issues)"
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app
  # Then
  eq cards "$before" "$(fs_board .issues)"
}

t_fs_failed_check_board_timer() {
  # Given: a run of #42 checked once, then gh logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go check acme/app
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app
  # Then
  eq board '{"status":"running","fails":1,"why":"HTTP 401: Bad credentials","must_act":false,"cards":1}' \
    "$(fs_board '{status, fails: .timer.fails, why: .timer.why, must_act: .timer.must_act, cards: (.issues | length)}')"
}

t_fs_third_failure_board_must_act() {
  # Given: a run of #42, never checked; gh is logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go check acme/app; fs_go check acme/app; fs_go check acme/app
  # Then
  eq board '{"fails":3,"must_act":true}' "$(fs_board '{fails: .timer.fails, must_act: .timer.must_act}')"
}

t_fs_watch_fail_board_timer() {
  # Given: a run of #42; gh is logged out
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  printf 'HTTP 401: Bad credentials\n' > "$FAKE_GH/graphql.fail"
  # When
  fs_go watch acme/app --once
  # Then
  eq board '{"fails":1,"why":"HTTP 401: Bad credentials"}' "$(fs_board '{fails: .timer.fails, why: .timer.why}')"
}

t_fs_pause_board_status() {
  # Given: a run of #42, checked once
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go check acme/app
  # When
  fs_go timer acme/app pause
  # Then
  eq board '{"status":"paused","cards":1}' "$(fs_board '{status, cards: (.issues | length)}')"
}

t_fs_board_run_shape() {
  # Given: a run of #42, checked once
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_go check acme/app
  # When
  local keys='[keys, (.timer | keys)]'
  # Then
  eq keys '[["checked_at","issues","name","repo","status","timer"],["checked_at","every","fails","must_act","why"]] same' \
    "$(fs_board "$keys") $([ "$(jq -c "$keys" "$here/fixtures/board/board.json")" = "$(fs_board "$keys")" ] && echo same)"
}

t_fs_board_journey() {
  # Given: #42 went from bug (t1, completed, 12:10) to ticket (t2, running, 12:40)
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  fs_record 42 bug t1 triage 2026-10-28T12:10:00Z; fs_record 42 ticket t2 ship 2026-10-28T12:40:00Z
  printf '[{"threadId":"t1","status":"completed","createdAt":"2026-10-28T12:10:00Z"},{"threadId":"t2","status":"running","createdAt":"2026-10-28T12:40:00Z"}]\n' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq journey '["joined","bug","ticket"] {"thread_url":"t3code://threads/e1/t2","status":"running"}' \
    "$(fs_board '.issues[0].journey | map(.stage // .step)') $(fs_board '.issues[0].journey[2] | {thread_url, status}')"
}

t_fs_board_fixture_shape() {
  # Given: a run of #42, size/S, whose thread t42 runs, checked
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 ticket t42 ship; fs_thread t42 running
  fs_go check acme/app
  # When
  local fixture; fixture="$(jq -c '.issues[0] | keys' "$here/fixtures/board/board.json")"
  # Then
  eq keys "$fixture" "$(fs_board '.issues[0] | keys')"
}

# fs_page <board.json>: the board page run on a fake page with that board,
# its {fetched, banner, hdot, nums} line in out.
fs_page() {
  T="${T:-$(mktemp -d)}"
  run node "$here/page.cjs" "$here/../assets/board.html" "$1"
  eq "page exit" 0 "$code"
}

t_fs_page_reads_board_only() {
  # Given: the failing board fixture
  # When
  fs_page "$here/fixtures/board/board-failing.json"
  # Then
  eq fetched '["board.json"]' "$(jq -c .fetched <<<"$out")"
}

t_fs_page_shows_label() {
  # Given: the board fixture, whose lib#5 issue lives in another repo
  # When
  fs_page "$here/fixtures/board/board.json"
  # Then
  has nums '"lib#5"' "$(jq -c .nums <<<"$out")"
  has nums '"#72"' "$(jq -c .nums <<<"$out")"
}

t_fs_page_must_act_banner() {
  # Given: a board whose check failed once, flagged for the user to act
  T="$(mktemp -d)"
  jq '.timer = {fails: 1, why: "bad", checked_at: null, every: 5, must_act: true}' "$here/fixtures/board/board.json" > "$T/board.json"
  # When
  fs_page "$T/board.json"
  # Then
  eq page '{"hdot":"dot bad","keeps":true}' "$(jq -c '{hdot, keeps: (.banner | startswith("<b>Checks keep failing.</b>"))}' <<<"$out")"
}

t_fs_page_no_flag_warns() {
  # Given: the same, with 4 failed checks and no flag
  T="$(mktemp -d)"
  jq '.timer = {fails: 4, why: "bad", checked_at: null, every: 5, must_act: false}' "$here/fixtures/board/board.json" > "$T/board.json"
  # When
  fs_page "$T/board.json"
  # Then
  eq page '{"hdot":"dot warn","warns":true}' "$(jq -c '{hdot, warns: (.banner | startswith("<b>Check failing.</b>"))}' <<<"$out")"
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

# fs_settle_run: a run of #42, size/S now, whose triage thread t42 finished
# turn r1 and is not settled.
fs_settle_run() {
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 bug t42 triage
  echo '[{"threadId":"t42","status":"completed","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
}

# fs_settle_of <thread> <jq>: that jq on the settle verdict of the thread's record.
fs_settle_of() { fs_state --arg t "$1" "[.threads[] | select(.thread == \$t) | .settle | $2]"; }

t_fs_settle_triage_listed() {
  # Given: #42 moved from bug to ticket; its triage thread t42 finished and is not settled
  fs_settle_run
  # When
  fs_go check acme/app
  # Then
  eq line '{"settles":[{"ref":"acme/app#42","label":"#42","stage":"bug","command":"triage","thread":"t42","link":"[i42](t3-thread://v1/t42)","status":"completed","run":"r1","now":"ticket"}],"changed":true}' \
    "$(jq -c '{settles, changed}' <<<"$out")"
}

t_fs_settle_grill_listed() {
  # Given: #44 moved from seed to ticket; its grill thread t44 finished turn r7
  fs_setup; fs_issue 44 OPEN '["size/M"]'; fs_start 44; fs_record 44 seed t44 grill
  echo '[{"threadId":"t44","status":"completed","settled":false,"latestRunId":"r7"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq settles '[{"ref":"acme/app#44","command":"grill","run":"r7","now":"ticket"}]' "$(jq -c '[.settles[] | {ref, command, run, now}]' <<<"$out")"
}

t_fs_settle_not_listed() {
  # Given: #42 is still a bug; t44 runs; t46 waits; #48's thread is /ship; t50 is settled; #52's thread is /ready-pr
  fs_setup
  fs_issue 42 OPEN '["bug"]'; fs_issue 44 OPEN '["size/S"]'; fs_issue 46 OPEN '["size/S"]'
  fs_issue 48 CLOSED '["size/S"]'; fs_issue 50 OPEN '["size/S"]'; fs_issue 52 OPEN '["size/S"]'
  fs_start 42 44 46 48 50 52
  fs_record 42 bug t42 triage; fs_record 44 bug t44 triage; fs_record 46 seed t46 grill
  fs_record 48 ticket t48 ship; fs_record 50 bug t50 triage; fs_record 52 pr t52 ready-pr
  echo '[{"threadId":"t42","status":"completed","settled":false,"latestRunId":"r1"},{"threadId":"t44","status":"running","settled":false,"latestRunId":"r1"},{"threadId":"t46","status":"waiting","settled":false,"latestRunId":"r1"},{"threadId":"t48","status":"completed","settled":false,"latestRunId":"r1"},{"threadId":"t50","status":"completed","settled":true,"latestRunId":"r1"},{"threadId":"t52","status":"completed","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq settles '[]' "$(jq -c .settles <<<"$out")"
}

t_fs_settle_failed_listed() {
  # Given: #42 moved from bug to ticket; its triage thread t42 failed
  fs_settle_run
  echo '[{"threadId":"t42","status":"failed","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq settles '[{"ref":"acme/app#42","status":"failed"}]' "$(jq -c '[.settles[] | {ref, status}]' <<<"$out")"
}

t_fs_settle_paused() {
  # Given: the run of fs_settle_run, paused
  fs_settle_run; fs_go timer acme/app pause
  # When
  fs_go check acme/app
  # Then
  eq settles '[]' "$(jq -c .settles <<<"$out")"
}

t_fs_settle_once() {
  # Given: the run settled t42 at r1; the user unsettled it and wrote once more (r2)
  fs_settle_run; fs_go settled acme/app t42 r1
  echo '[{"threadId":"t42","status":"completed","settled":false,"latestRunId":"r2"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq settles '[]' "$(jq -c .settles <<<"$out")"
  eq verdict '[{"verdict":"settled","run":"r1","why":null}]' "$(fs_settle_of t42 '{verdict, run, why}')"
}

t_fs_settle_kept_new_turn() {
  # Given: t42 kept at r1, #42's ship thread t43 runs, and a check after the verdict
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 bug t42 triage; fs_record 42 ticket t43 ship
  echo '[{"threadId":"t42","status":"completed","settled":false,"latestRunId":"r1"},{"threadId":"t43","status":"running","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
  fs_go check acme/app
  fs_go settled acme/app t42 r1 --kept "asks which label"
  fs_go check acme/app
  eq "check at r1" '{"settles":[],"changed":false}' "$(jq -c '{settles, changed}' <<<"$out")"
  echo '[{"threadId":"t42","status":"completed","settled":false,"latestRunId":"r2"},{"threadId":"t43","status":"running","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
  # When
  fs_go check acme/app
  # Then
  eq line '{"runs":["r2"],"changed":true,"issues":[false]}' "$(jq -c '{runs: [.settles[] | .run], changed, issues: [.issues[] | .changed]}' <<<"$out")"
  eq verdict '[{"verdict":"kept","run":"r1","why":"asks which label"}]' "$(fs_settle_of t42 '{verdict, run, why}')"
}

t_fs_settled_twice() {
  # Given: the run settled t42 at r1
  fs_settle_run; fs_go settled acme/app t42 r1
  # When
  fs_go settled acme/app t42 r1
  # Then
  eq exit 0 "$code"
  eq verdict '[{"verdict":"settled","run":"r1"}]' "$(fs_settle_of t42 '{verdict, run}')"
}

t_fs_settled_refuses_ship() {
  # Given: #42's thread t42 started with /ship, not /triage
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 bug t42 ship
  echo '[{"threadId":"t42","status":"completed","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
  # When
  fs_go settled acme/app t42 r1
  # Then
  eq exit 1 "$code"
  eq stderr "stop: t42 is no grill or triage thread of this run" "$(printf '%s\n' "$err" | tail -1)"
  eq verdicts false "$(fs_state '[.threads[] | .settle] | map(. != null) | any')"
}

t_fs_watch_wakes_settle() {
  # Given: #42 went from bug (t1 finished, not settled) to ticket (t2 runs); f1 finished its turn
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42; fs_record 42 bug t1 triage; fs_record 42 ticket t2 ship
  echo '[{"threadId":"f1","status":"completed"},{"threadId":"t1","status":"completed","settled":false,"latestRunId":"r1"},{"threadId":"t2","status":"running","settled":false,"latestRunId":"r1"}]' > "$T/t3-threads.json"
  # When
  fs_go watch acme/app --once
  # Then
  eq line '{"wake":["settle #42"],"woke":true,"sent":[]}' "$out"
  eq sends "thread send f1 /orchestrate check" "$(fs_sends)"
}

cases=(
  "start writes the run and its set|t_fs_start_writes_run"
  "an old run's bare numbers become refs|t_fs_old_state_converted"
  "a free ticket starts ship|t_fs_ticket_starts_ship"
  "a second check starts nothing|t_fs_second_check_starts_nothing"
  "a recorded thread is not started again|t_fs_recorded_thread_not_again"
  "a seed starts grill|t_fs_seed_starts_grill"
  "a bug starts triage|t_fs_bug_starts_triage"
  "a PR from before the run starts ready-pr|t_fs_old_pr_starts_ready_pr"
  "a PR the run opened starts nothing new|t_fs_new_pr_starts_nothing"
  "a task starts complete-task, ready first|t_fs_task_starts_complete_task"
  "a second task waits for the turn|t_fs_second_task_waits"
  "a task in another live run holds the turn|t_fs_other_run_holds_turn"
  "a run whose watcher is gone holds no turn|t_fs_dead_watcher_no_turn"
  "a stopped run holds no turn|t_fs_stopped_run_no_turn"
  "a broken state file in another run holds no turn|t_fs_broken_run_no_turn"
  "a failed task launch frees the turn|t_fs_failed_task_launch_frees_turn"
  "a closed task frees the turn|t_fs_closed_task_frees_turn"
  "a resumed task waits while a later task holds the turn|t_fs_later_task_holds_turn"
  "a removed task frees the turn|t_fs_removed_task_frees_turn"
  "a watcher check claims no turn|t_fs_watch_claims_no_turn"
  "a watcher check frees a closed task's turn|t_fs_watch_frees_closed_turn"
  "an unlabeled issue waits|t_fs_unlabeled_waits"
  "a closed seed is done|t_fs_closed_seed_done"
  "an open blocker holds the issue|t_fs_open_blocker_holds"
  "closed blockers free the issue|t_fs_closed_blockers_free"
  "a bug turned ticket starts ship|t_fs_bug_turned_ticket"
  "restart starts a fresh thread|t_fs_restart_fresh_thread"
  "a failed launch is not started again|t_fs_failed_launch_not_again"
  "an epic in the set brings its open sub-issues|t_fs_epic_brings_subs"
  "a follow-up in a PR body joins|t_fs_followup_joins"
  "an epic part in another repo starts there|t_fs_other_repo_part_starts"
  "a repo folder with no T3 project is added|t_fs_other_repo_adds_project"
  "a thread in another repo's project shows its status|t_fs_other_repo_thread_status"
  "a repo the run cannot read asks you and the rest goes on|t_fs_other_repo_unreadable_asks"
  "a repo not on the Mac asks you|t_fs_other_repo_no_checkout_asks"
  "a follow-up in another repo's PR joins as that repo's issue|t_fs_other_repo_followup_joins"
  "an issue another live run owns waits with its link|t_fs_owned_by_other_run"
  "two runs that hold one issue start it once|t_fs_two_runs_one_start"
  "two runs started in the same second have one owner|t_fs_same_second_runs_one_owner"
  "a check waits while another run's check holds the claims lock|t_fs_check_waits_for_claims_lock"
  "commands take #n, repo#n, and owner/repo#n|t_fs_ref_forms"
  "an issue word names a run's repo in any case|t_fs_ref_any_case"
  "repo#n of a repo the run does not have stops|t_fs_ref_unknown_repo"
  "a blocker in another repo shows as repo#n|t_fs_other_repo_blocker_label"
  "add puts an issue in the set|t_fs_add_to_set"
  "a removed issue never rejoins|t_fs_removed_never_rejoins"
  "ship merge for one issue|t_fs_ship_merge_one"
  "change ship refuses a bad mode|t_fs_ship_bad_mode"
  "change use refuses a bad effort|t_fs_use_bad_effort"
  "ship merge for all leaves started issues|t_fs_ship_merge_all"
  "a started issue keeps its ship mode|t_fs_ship_started"
  "an override for one issue wins over all|t_fs_override_one_wins"
  "a failed gh call starts nothing|t_fs_gh_fail_starts_nothing"
  "T3 not answering starts nothing|t_fs_t3_fail_starts_nothing"
  "the third failure in a row asks the user to act|t_fs_third_failure_asks"
  "the check writes nothing to GitHub|t_fs_check_writes_nothing"
  "two open PRs make the issue wait|t_fs_two_prs_waits"
  "all closed ends the run with a summary|t_fs_all_closed_done"
  "an epic with closed sub-issues is done|t_fs_epic_done"
  "a done run prints the retro thread line|t_fs_done_starts_retro"
  "the retro gets the analysis row|t_fs_done_retro_row"
  "a done run with a removed issue prints no retro line|t_fs_done_removed_no_retro"
  "sync fast-forwards the checked-out default branch|t_fs_sync_fast_forwards"
  "sync fast-forwards each repo the run worked in|t_fs_sync_each_repo"
  "sync reports a failed fetch and exits 0|t_fs_sync_fetch_fails"
  "sync names gh's line when the default branch is unreadable|t_fs_sync_gh_fails"
  "sync leaves an up-to-date default branch|t_fs_sync_up_to_date"
  "sync leaves a default branch with its own commits|t_fs_sync_own_commits"
  "sync leaves a default branch whose edits are in the way|t_fs_sync_edits_in_the_way"
  "sync moves the default branch under another checked-out branch|t_fs_sync_other_branch"
  "sync leaves edits in the way with merge.autoStash on|t_fs_sync_edits_in_the_way_autostash"
  "sync leaves an ignored file in the way|t_fs_sync_ignored_file_in_the_way"
  "sync moves main when the fetch refspec leaves it out|t_fs_sync_narrow_fetch_refspec"
  "close-epics closes the open epic of a done run|t_fs_close_epics_closes_done_epic"
  "close-epics stops on a run that is not done|t_fs_close_epics_not_done"
  "close-epics reports a refused close and exits 0|t_fs_close_epics_refused"
  "close-epics leaves an epic whose sub-issue opened again|t_fs_close_epics_sub_reopened"
  "an epic whose child epic is done ends the run|t_fs_nested_epic_done"
  "close-epics closes an inner epic before its parent|t_fs_close_epics_inner_first"
  "an open manual task keeps the run open|t_fs_manual_keeps_open"
  "an unmerged PR keeps the run open|t_fs_unmerged_pr_keeps_open"
  "start sets a 5 minute timer|t_fs_timer_five_min"
  "the interval takes 1 minute or more|t_fs_interval_min_one"
  "a paused run starts nothing|t_fs_paused_starts_nothing"
  "a first check marks every issue changed|t_fs_first_check_all_changed"
  "a second check with nothing new is quiet|t_fs_second_check_quiet"
  "a thread that changes status marks only its issue|t_fs_status_change_marks_issue"
  "a start marks its issue changed|t_fs_start_marks_changed"
  "a quiet watcher check sends nothing|t_fs_watch_quiet"
  "a watcher check claims nothing and records the time|t_fs_watch_claims_nothing"
  "a watcher check writes the board|t_fs_watch_board"
  "a watcher check of a paused run does nothing|t_fs_watch_paused"
  "a thread to start wakes the orchestrator|t_fs_watch_wakes_start"
  "a running orchestrator is not woken|t_fs_watch_running_not_woken"
  "a waiting orchestrator is not woken|t_fs_watch_waiting_not_woken"
  "a proposal to make wakes the orchestrator|t_fs_watch_wakes_propose"
  "a done run wakes the orchestrator|t_fs_watch_wakes_done"
  "a failed wake is tried at the next watcher check|t_fs_watch_wake_retried"
  "a failed watcher check counts it|t_fs_watch_fail_counts"
  "the third failed watcher check wakes the orchestrator once|t_fs_watch_third_fail_wakes"
  "a good watcher check clears the failures|t_fs_watch_good_clears"
  "start and resume keep the orchestrator thread|t_fs_thread_kept"
  "watch starts one watcher and records it|t_fs_watch_starts"
  "watch again replaces the old watcher|t_fs_watch_replaces"
  "pause ends the watcher|t_fs_pause_ends_watcher"
  "stop ends the watcher|t_fs_stop_ends_watcher"
  "pause leaves a process that is not a watcher alone|t_fs_pause_spares_other"
  "a watcher check with an old token does nothing|t_fs_watch_old_token"
  "the watcher loop ends when the run is not running|t_fs_watch_loop_ends"
  "watch on a paused run stops|t_fs_watch_paused_stops"
  "timer takes no task|t_fs_timer_no_task"
  "a command waits for a live lock, then stops|t_fs_lock_live_stops"
  "a dead holder's lock is taken over|t_fs_lock_dead_taken"
  "stop keeps the state file|t_fs_stop_keeps_state"
  "a live run stops a second start|t_fs_live_run_stops_start"
  "resume takes the newest run that is not done|t_fs_resume_newest"
  "resume clears the failure alert|t_fs_resume_clears_alert"
  "a set with no open issue stops|t_fs_no_open_issue_stops"
  "outside T3 Code stops|t_fs_outside_t3_stops"
  "an unlabeled issue is listed to propose|t_fs_unlabeled_listed"
  "an added unlabeled issue is listed to propose|t_fs_added_unlabeled_listed"
  "proposed takes only a route word|t_fs_proposed_route_word"
  "proposed for an issue outside the set stops|t_fs_proposed_outside_set"
  "proposed prints the model and effort|t_fs_proposed_prints_row"
  "proposed takes the use pick|t_fs_proposed_use_wins"
  "a ship proposal needs a size|t_fs_proposed_ship_needs_size"
  "proposed refuses a bad size|t_fs_proposed_bad_size"
  "a task proposal takes no size|t_fs_proposed_task_no_size"
  "an xxl proposal takes no size|t_fs_proposed_xxl_no_size"
  "an XXL issue starts nothing and asks you to cut it|t_fs_xxl_starts_nothing"
  "an xxl proposal answered yes starts nothing|t_fs_xxl_answer_starts_nothing"
  "a cut XXL issue brings its sub-issues|t_fs_cut_xxl_brings_subs"
  "a close proposal has no model|t_fs_proposed_no_model"
  "a decide stop keeps the proposal and says why|t_fs_proposed_decide_stop"
  "an answer keeps the size|t_fs_answer_keeps_size"
  "a ship proposal launches with its size|t_fs_ship_proposal_size_launches"
  "a size label wins over the proposal's size|t_fs_label_wins_proposal_size"
  "a grill answer starts grill|t_fs_grill_answer_starts"
  "a ship answer starts ship|t_fs_ship_answer_starts"
  "a ready-to-build ticket with no size ships|t_fs_ready_to_build_ships"
  "a ship answer with no size stops|t_fs_ship_answer_needs_size"
  "a yes writes the label that fits|t_fs_yes_writes_labels"
  "close, skip, ready-pr, and xxl write no label|t_fs_no_label_answers"
  "a refused label write still starts|t_fs_refused_label_starts"
  "a ship answer records its size and starts|t_fs_ship_answer_size_starts"
  "a second answer writes the label again|t_fs_second_answer_labels_again"
  "all yes takes every sure proposal|t_fs_all_yes"
  "yes on an unsure proposal stops|t_fs_yes_on_unsure"
  "an answered issue waits for its blocker|t_fs_answered_waits_blocker"
  "a close answer starts nothing and writes nothing|t_fs_close_answer"
  "answers survive stop and resume|t_fs_answers_survive_resume"
  "a label wins over an answer|t_fs_label_wins_answer"
  "a started ship answer keeps its ship mode|t_fs_ship_started_answer"
  "the board puts each issue in its column|t_fs_board_columns"
  "a second check leaves one board file|t_fs_board_one_file"
  "start copies the board page into the run|t_fs_start_copies_page"
  "start without an env id stops|t_fs_start_needs_env"
  "the board chip is the kind and the size|t_fs_board_chips"
  "a bug with an old PR is at pr with a bug chip|t_fs_bug_old_pr_chip"
  "a waiting thread is yours|t_fs_board_waiting_yours"
  "a failed thread is yours|t_fs_board_failed_yours"
  "an interrupted thread is yours|t_fs_board_interrupted_yours"
  "a completed thread with no new stage is yours|t_fs_board_no_change_yours"
  "a paused thread is the agent's|t_fs_board_paused_agent"
  "a thread quiet for 10 minutes is yours|t_fs_board_quiet_yours"
  "a failed launch is yours|t_fs_board_launch_failed_yours"
  "a free task is starting|t_fs_board_task_starts"
  "a waiting task holds no turn|t_fs_waiting_task_no_turn"
  "a waiting task waits for resume|t_fs_board_waiting_task"
  "a finished task thread waits for you|t_fs_board_ready_task"
  "a task thread that just finished waits for you|t_fs_board_task_just_finished"
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
  "the board marks removed, made by run, and a set ship mode|t_fs_board_extra_chips"
  "a removed issue starts nothing|t_fs_removed_starts_nothing"
  "a good check records its time|t_fs_check_records_time"
  "a failed check records why|t_fs_failed_check_why"
  "a failed check keeps the last board|t_fs_failed_check_keeps_board"
  "a failed check shows on the board|t_fs_failed_check_board_timer"
  "the third failed check tells the board the user must act|t_fs_third_failure_board_must_act"
  "a failed watcher check shows on the board|t_fs_watch_fail_board_timer"
  "a pause shows on the board with no check|t_fs_pause_board_status"
  "the board holds the run part in the fixture's shape|t_fs_board_run_shape"
  "the journey lists each stage and its thread|t_fs_board_journey"
  "the walk fixture has the board's shape|t_fs_board_fixture_shape"
  "the board page fetches only board.json|t_fs_page_reads_board_only"
  "the board page shows each issue's label|t_fs_page_shows_label"
  "the board page says checks keep failing when the board flags it|t_fs_page_must_act_banner"
  "the board page only warns when the board does not flag it|t_fs_page_no_flag_warns"
  "the page ships no mockup data|t_fs_page_no_mockup_data"
  "resume copies the board page again|t_fs_resume_copies_page"
  "two runs get two different pages|t_fs_two_runs_two_pages"
  "a conflicting PR of a finished thread gets /ready-pr|t_fs_conflict_listed"
  "a conflict is sent once per head|t_fs_conflict_once_per_head"
  "a new head that conflicts again is sent again|t_fs_conflict_new_head"
  "a thread that is not finished gets no conflict|t_fs_conflict_busy_thread"
  "a PR with no conflict is not sent|t_fs_conflict_none"
  "a paused run sends no conflict|t_fs_conflict_paused"
  "one PR of two issues is sent once|t_fs_conflict_shared_pr"
  "a shared PR goes only to its first issue's thread|t_fs_conflict_shared_owner"
  "a thread gets one conflict per check|t_fs_conflict_one_per_thread"
  "an issue that starts a thread sends no conflict|t_fs_conflict_new_stage"
  "a check sends no conflict|t_fs_check_no_conflict"
  "a failed /ready-pr send is not sent again|t_fs_conflict_send_failed"
  "a finished triage thread whose issue moved on is listed to settle|t_fs_settle_triage_listed"
  "a finished grill thread whose issue moved on is listed to settle|t_fs_settle_grill_listed"
  "a thread not finished or not moved on is not listed|t_fs_settle_not_listed"
  "a failed thread whose issue moved on is listed|t_fs_settle_failed_listed"
  "a paused run lists nothing to settle|t_fs_settle_paused"
  "a settled thread is not listed again|t_fs_settle_once"
  "a kept thread is listed again only after a new turn|t_fs_settle_kept_new_turn"
  "settled twice keeps one verdict|t_fs_settled_twice"
  "settled refuses a thread that is not grill or triage|t_fs_settled_refuses_ship"
  "the watcher wakes the orchestrator to settle|t_fs_watch_wakes_settle"
)
