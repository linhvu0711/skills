# factory.sh: the cases for this skill's factory.sh, the check script and the
# one writer of a run's state file, seen through the fake gh and a fake t3.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The factory script.
F="$here/../scripts/factory.sh"

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

# fs_go <args...>: factory.sh from T, inside T3 Code, with the search root,
# the repo map, and the factory home inside T.
fs_go() {
  cd "$T"
  run env T3CODE_CLI_PATH="$T/bin/t3" KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" \
    FACTORY_HOME="$T/factory" bash "$F" "$@"
}

# fs_start <n>...: a run of these issues, named after the first.
fs_start() {
  fs_go start acme/app --name "#$1" --link "[factory: #$1](t3-thread://v1/f1)" "$@"
  eq "start exit" 0 "$code"
}

# fs_state <jq>: the jq filter on the newest run's state file.
fs_state() { jq -c "$1" "$(ls -1d "$T"/factory/acme-app/*/ | sort | tail -1)state.json"; }

t_fs_start_writes_run() {
  # Given: #42 "Export orders", open, size/L
  fs_setup; fs_issue 42 OPEN '["size/L"]'
  # When
  fs_go start acme/app --name "#42" --link "[factory: #42](t3-thread://v1/f1)" 42
  # Then
  eq exit 0 "$code"
  eq runs 1 "$(ls -1 "$T/factory/acme-app" | wc -l | tr -d ' ')"
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

cases=(
  "start writes the run and its set|t_fs_start_writes_run"
  "a free ticket starts ship-ready|t_fs_ticket_starts_ship_ready"
  "a second check starts nothing|t_fs_second_check_starts_nothing"
  "a recorded thread is not started again|t_fs_recorded_thread_not_again"
)
