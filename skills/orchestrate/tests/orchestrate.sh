# orchestrate.sh: the cases for this skill's orchestrate.sh, the check script and the
# one writer of a run's state file, seen through the fake gh and a fake t3.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

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

# fs_prs <node>...: the GraphQL answer for #42's closing PRs, kept in
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

t_fs_new_pr_keeps_two_prs_wait() {
  # Given: #42 has an open PR from before the run and one from after it
  local a='{"number":43,"url":"https://github.com/acme/app/pull/43","state":"OPEN","createdAt":"2026-10-27T09:00:00Z","body":""}'
  local b='{"number":44,"url":"https://github.com/acme/app/pull/44","state":"OPEN","createdAt":"2026-10-28T13:00:00Z","body":""}'
  fs_setup; fs_issue 42 OPEN '["size/S"]' '[]' "[$a,$b]"; fs_prs "$a" "$b"; fs_start 42; fs_at 2026-10-28T12:00:00Z
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"starts":[]' "$out"
  has stdout '"wait":"#42 has 2 open PRs: https://github.com/acme/app/pull/43 https://github.com/acme/app/pull/44"' "$out"
}

t_fs_sizeless_ship_answer_proposes() {
  # Given: unlabeled #42 answered ship with no size, as a run before sizes were needed saved it
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42
  local st; st="$(fs_run)/state.json"
  jq '.proposals["acme/app#42"] = {route: null, answer: "ship"}' "$st" > "$st.new" && mv "$st.new" "$st"
  # When
  fs_go check acme/app
  # Then
  eq exit 0 "$code"
  has stdout '"propose":["acme/app#42"]' "$out"
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

t_fs_stop_keeps_state() {
  # Given: a run of #42
  fs_setup; fs_issue 42 OPEN '["size/S"]'; fs_start 42
  # When
  fs_go timer acme/app stop
  # Then
  eq exit 0 "$code"
  eq status stopped "$(fs_state -r .status)"
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

t_fs_answer_keeps_size() {
  # Given: #42 proposed ship at size S
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 ship --size S
  # When
  fs_go change acme/app answer 42 yes
  # Then
  eq exit 0 "$code"
  eq proposals '{"acme/app#42":{"route":"ship","answer":"ship","size":"S","labeled":"size/S"}}' "$(fs_state .proposals)"
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

t_fs_ship_answer_size_starts() {
  # Given: unlabeled #42, proposed grill
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  # When
  fs_go change acme/app answer 42 ship --size M
  eq "answer stdout" "labeled #42 size/M" "$out"
  eq proposal '{"route":"grill","answer":"ship","size":"M","labeled":"size/M"}' "$(fs_state '.proposals["acme/app#42"]')"
  fs_go check acme/app
  # Then
  has stdout '"message":"/ship #42"' "$out"
  has stdout '"effort":"high"' "$out"
}

t_fs_routed_issue_not_labeled() {
  # Given: unlabeled #42 proposed grill; then a teammate labels it size/M
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  fs_issue 42 OPEN '["size/M"]'
  # When
  fs_go change acme/app answer all yes
  # Then
  eq exit 0 "$code"
  eq stdout "not labeled #42: its labels route it: size M" "$out"
  eq "edit calls" no "$([ -e "$FAKE_GH/issue-edit.calls" ] && echo yes || echo no)"
}

t_fs_changed_answer_swaps_label() {
  # Given: unlabeled #42 answered grill, so GitHub gave it seed
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill; fs_go change acme/app answer 42 yes
  fs_issue 42 OPEN '["p1","seed"]'
  # When
  fs_go change acme/app answer 42 ship --size M
  # Then
  eq exit 0 "$code"
  eq stdout "labeled #42 size/M, took off seed" "$out"
  eq "second edit" "issue edit 42 --repo acme/app --add-label size/M --remove-label seed" "$(sed -n 2p "$FAKE_GH/issue-edit.args")"
}

t_fs_teammate_label_stays() {
  # Given: #42 proposed grill; a teammate labels it seed before the yes
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill
  fs_issue 42 OPEN '["p1","seed"]'; fs_go change acme/app answer 42 yes
  # When
  fs_go change acme/app answer 42 ship --size M
  # Then
  eq exit 0 "$code"
  eq stdout "not labeled #42: its labels route it: seed" "$out"
  eq "edit calls" no "$([ -e "$FAKE_GH/issue-edit.calls" ] && echo yes || echo no)"
}

t_fs_removed_label_not_owned() {
  # Given: #42 answered grill, so it got seed; seed came off on GitHub, the
  # user skipped it, and a teammate put seed back
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 grill; fs_go change acme/app answer 42 yes
  fs_issue 42 OPEN '["p1"]'; fs_go change acme/app answer 42 skip
  fs_issue 42 OPEN '["p1","seed"]'
  # When
  fs_go change acme/app answer 42 triage
  # Then
  eq exit 0 "$code"
  eq stdout "not labeled #42: its labels route it: seed" "$out"
  eq "edit calls" 1 "$(cat "$FAKE_GH/issue-edit.calls")"
}

t_fs_missing_label_made() {
  # Given: unlabeled #42 proposed task, in a repo with no manual label
  fs_setup; fs_issue 42 OPEN '["p1"]'; fs_start 42; fs_go proposed acme/app 42 task
  printf "failed to update https://github.com/acme/app/issues/42: 'manual' not found\n" > "$FAKE_GH/issue-edit.1.fail"
  echo https://github.com/acme/app/labels/manual > "$FAKE_GH/label-create.json"
  # When
  fs_go change acme/app answer 42 yes
  # Then
  eq exit 0 "$code"
  eq stdout "labeled #42 manual (made the label)" "$out"
  eq "label create" "label create manual --repo acme/app --color 6E7781 --description Work in a platform outside the repo; /complete-task drives it" "$(cat "$FAKE_GH/label-create.args")"
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
  "a broken state file in another run holds no turn|t_fs_broken_run_no_turn"
  "a failed task launch frees the turn|t_fs_failed_task_launch_frees_turn"
  "a closed task frees the turn|t_fs_closed_task_frees_turn"
  "an unlabeled issue waits|t_fs_unlabeled_waits"
  "a closed seed is done|t_fs_closed_seed_done"
  "an open blocker holds the issue|t_fs_open_blocker_holds"
  "closed blockers free the issue|t_fs_closed_blockers_free"
  "restart starts a fresh thread|t_fs_restart_fresh_thread"
  "a failed launch is not started again|t_fs_failed_launch_not_again"
  "an epic in the set brings its open sub-issues|t_fs_epic_brings_subs"
  "a follow-up in a PR body joins|t_fs_followup_joins"
  "an epic part in another repo starts there|t_fs_other_repo_part_starts"
  "a repo folder with no T3 project is added|t_fs_other_repo_adds_project"
  "an issue another live run owns waits with its link|t_fs_owned_by_other_run"
  "two runs that hold one issue start it once|t_fs_two_runs_one_start"
  "two runs started in the same second have one owner|t_fs_same_second_runs_one_owner"
  "a check waits while another run's check holds the claims lock|t_fs_check_waits_for_claims_lock"
  "an issue word names a run's repo in any case|t_fs_ref_any_case"
  "add puts an issue in the set|t_fs_add_to_set"
  "a removed issue never rejoins|t_fs_removed_never_rejoins"
  "ship merge for one issue|t_fs_ship_merge_one"
  "ship merge for all leaves started issues|t_fs_ship_merge_all"
  "a failed gh call starts nothing|t_fs_gh_fail_starts_nothing"
  "T3 not answering starts nothing|t_fs_t3_fail_starts_nothing"
  "the check writes nothing to GitHub|t_fs_check_writes_nothing"
  "two open PRs make the issue wait|t_fs_two_prs_waits"
  "all closed ends the run with a summary|t_fs_all_closed_done"
  "an epic with closed sub-issues is done|t_fs_epic_done"
  "sync fast-forwards the checked-out default branch|t_fs_sync_fast_forwards"
  "sync fast-forwards each repo the run worked in|t_fs_sync_each_repo"
  "sync leaves a default branch with its own commits|t_fs_sync_own_commits"
  "sync leaves a default branch whose edits are in the way|t_fs_sync_edits_in_the_way"
  "sync moves the default branch under another checked-out branch|t_fs_sync_other_branch"
  "sync leaves edits in the way with merge.autoStash on|t_fs_sync_edits_in_the_way_autostash"
  "sync leaves an ignored file in the way|t_fs_sync_ignored_file_in_the_way"
  "sync moves main when the fetch refspec leaves it out|t_fs_sync_narrow_fetch_refspec"
  "close-epics closes the open epic of a done run|t_fs_close_epics_closes_done_epic"
  "close-epics stops on a run that is not done|t_fs_close_epics_not_done"
  "close-epics leaves an epic whose sub-issue opened again|t_fs_close_epics_sub_reopened"
  "an epic whose child epic is done ends the run|t_fs_nested_epic_done"
  "close-epics closes an inner epic before its parent|t_fs_close_epics_inner_first"
  "a paused run starts nothing|t_fs_paused_starts_nothing"
  "a quiet watcher check sends nothing|t_fs_watch_quiet"
  "a watcher check claims nothing and records the time|t_fs_watch_claims_nothing"
  "a thread to start wakes the orchestrator|t_fs_watch_wakes_start"
  "a running orchestrator is not woken|t_fs_watch_running_not_woken"
  "the third failed watcher check wakes the orchestrator once|t_fs_watch_third_fail_wakes"
  "start and resume keep the orchestrator thread|t_fs_thread_kept"
  "watch starts one watcher and records it|t_fs_watch_starts"
  "pause ends the watcher|t_fs_pause_ends_watcher"
  "stop ends the watcher|t_fs_stop_ends_watcher"
  "the watcher loop ends when the run is not running|t_fs_watch_loop_ends"
  "stop keeps the state file|t_fs_stop_keeps_state"
  "resume takes the newest run that is not done|t_fs_resume_newest"
  "resume clears the failure alert|t_fs_resume_clears_alert"
  "an unlabeled issue is listed to propose|t_fs_unlabeled_listed"
  "an added unlabeled issue is listed to propose|t_fs_added_unlabeled_listed"
  "proposed prints the model and effort|t_fs_proposed_prints_row"
  "proposed takes the use pick|t_fs_proposed_use_wins"
  "an XXL issue starts nothing and asks you to cut it|t_fs_xxl_starts_nothing"
  "an answer keeps the size|t_fs_answer_keeps_size"
  "a ship proposal launches with its size|t_fs_ship_proposal_size_launches"
  "a size label wins over the proposal's size|t_fs_label_wins_proposal_size"
  "a grill answer starts grill|t_fs_grill_answer_starts"
  "a ship answer starts ship|t_fs_ship_answer_starts"
  "a ready-to-build ticket with no size ships|t_fs_ready_to_build_ships"
  "a yes writes the label that fits|t_fs_yes_writes_labels"
  "close, skip, ready-pr, and xxl write no label|t_fs_no_label_answers"
  "a ship answer records its size and starts|t_fs_ship_answer_size_starts"
  "an issue its labels route gets no label|t_fs_routed_issue_not_labeled"
  "a changed answer swaps the label|t_fs_changed_answer_swaps_label"
  "a missing label is made, then added|t_fs_missing_label_made"
  "a teammate's label stays when the answer changes|t_fs_teammate_label_stays"
  "a label gone from the issue is no longer the run's|t_fs_removed_label_not_owned"
  "a new PR keeps the two-PR wait|t_fs_new_pr_keeps_two_prs_wait"
  "a sizeless ship answer is proposed again|t_fs_sizeless_ship_answer_proposes"
  "all yes takes every sure proposal|t_fs_all_yes"
  "an answered issue waits for its blocker|t_fs_answered_waits_blocker"
  "a close answer starts nothing and writes nothing|t_fs_close_answer"
  "answers survive stop and resume|t_fs_answers_survive_resume"
  "a second check leaves one board file|t_fs_board_one_file"
  "start copies the board page into the run|t_fs_start_copies_page"
  "a failed read of removed issues fails no check|t_fs_removed_read_fails"
  "a deleted removed issue has no card|t_fs_removed_deleted"
  "a removed issue starts nothing|t_fs_removed_starts_nothing"
  "a good check records its time|t_fs_check_records_time"
  "resume copies the board page again|t_fs_resume_copies_page"
  "two runs get two different pages|t_fs_two_runs_two_pages"
  "a conflicting PR of a finished thread gets /ready-pr|t_fs_conflict_listed"
  "a conflict is sent once per head|t_fs_conflict_once_per_head"
  "a new head that conflicts again is sent again|t_fs_conflict_new_head"
  "a PR with no conflict is not sent|t_fs_conflict_none"
  "one PR of two issues is sent once|t_fs_conflict_shared_pr"
  "a shared PR goes only to its first issue's thread|t_fs_conflict_shared_owner"
  "a thread gets one conflict per check|t_fs_conflict_one_per_thread"
  "a check sends no conflict|t_fs_check_no_conflict"
  "a finished triage thread whose issue moved on is listed to settle|t_fs_settle_triage_listed"
  "a finished grill thread whose issue moved on is listed to settle|t_fs_settle_grill_listed"
  "a settled thread is not listed again|t_fs_settle_once"
  "the watcher wakes the orchestrator to settle|t_fs_watch_wakes_settle"
)
