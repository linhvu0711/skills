# kickoff.sh: the cases for this skill's kickoff.sh: its checkout lookup, and
# the model, effort, command, and pane name it picks, seen through a fake
# herdr. The repo's test.sh sources this file after test-lib.sh and runs its
# cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The kickoff script.
K="$here/../scripts/kickoff.sh"

# ko_setup: a fresh temp folder T and the fake gh, whose `issue view` is a
# plain issue #42 and whose `repo view` names main as the default branch.
ko_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"number":42,"title":"Export orders","labels":[],"subIssues":{"nodes":[]},"state":"OPEN"}\n' > "$FAKE_GH/issue-view.json"
  printf '{"defaultBranchRef":{"name":"main"}}\n' > "$FAKE_GH/repo-view.json"
}

# ko_clone <dir>: a main checkout at <dir> whose origin is acme/app on GitHub.
ko_clone() {
  git init -q -b main "$1"
  git -C "$1" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$1" remote add origin https://github.com/acme/app.git
}

# ko_run: kickoff on issue #42 of acme/app from T, with the search root and
# the repo map inside T, and outside herdr, so it stops before any pane.
ko_run() {
  cd "$T"
  run env -u HERDR_ENV KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" bash "$K" https://github.com/acme/app/issues/42
}

# ko_herdr: ko_setup, one checkout of acme/app, and a fake herdr first on
# PATH. herdr logs each call as one line in $T/herdr.log and answers a
# workspace with no tabs, so kickoff makes a new tab w1:t2 with pane w1:p2;
# an agent is working once prompted.
ko_herdr() {
  ko_setup; ko_clone "$T/dev/app"
  cat > "$T/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane list") echo '{"result":{"panes":[]}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w1:p2"},"tab":{"tab_id":"w1:t2"}}}' ;;
  "agent get") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "pane rename"|"agent start"|"agent prompt") echo '{}' ;;
  *) printf 'fake herdr: no route for %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$T/bin/herdr"
  export FAKE_HERDR_LOG="$T/herdr.log"
}

# ko_issue <labels-json>: issue #42 "Export orders", no sub-issues, with these
# labels, as in '[{"name":"size/S"}]'.
ko_issue() {
  printf '{"number":42,"title":"Export orders","labels":%s,"subIssues":{"nodes":[]},"state":"OPEN"}\n' "$1" > "$FAKE_GH/issue-view.json"
}

# ko_go <args...>: kickoff from T inside herdr, as workspace w1, tab w1:t1.
ko_go() {
  cd "$T"
  run env HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" bash "$K" "$@"
}

# ko_start <model> <effort> [<name>]: the agent start line kickoff sends, for
# the agent i42 unless a name is given.
ko_start() {
  printf 'agent start %s --kind claude --pane w1:p2 --timeout 60000 -- --model %s --effort %s --permission-mode auto' "${3:-i42}" "$1" "$2"
}

t_ko_no_checkout() {
  ko_setup; mkdir -p "$T/dev"
  ko_run
  eq stderr "stop: no checkout of acme/app under $T/dev. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ko_two_checkouts() {
  ko_setup; ko_clone "$T/dev/a/app"; ko_clone "$T/dev/b/app"
  ko_run
  eq stderr "stop: several checkouts of acme/app: $T/dev/a/app $T/dev/b/app. Add the right one to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ko_writes_map() {
  ko_setup; ko_clone "$T/dev/app"
  ko_run
  eq map "$(printf 'acme/app\t%s' "$T/dev/app")" "$(cat "$T/map.tsv")"
}

t_ko_ready_sonnet_ship() {
  ko_herdr; ko_issue '[{"name":"ready-to-build"},{"name":"size/XS"}]'
  ko_go https://github.com/acme/app/issues/42
  eq exit 0 "$code"
  has start "$(ko_start sonnet high)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /ship https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
}

t_ko_small_opus_ship() {
  ko_herdr; ko_issue '[{"name":"size/S"}]'
  ko_go https://github.com/acme/app/issues/42
  has start "$(ko_start opus medium)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /ship https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
}

t_ko_medium_opus_plan() {
  ko_herdr; ko_issue '[{"name":"Size: Medium"}]'
  ko_go https://github.com/acme/app/issues/42
  has start "$(ko_start opus medium)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /plan-up https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
}

t_ko_large_opus_high_plan() {
  ko_herdr; ko_issue '[{"name":"size/L"}]'
  ko_go https://github.com/acme/app/issues/42
  has start "$(ko_start opus high)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /plan-up https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
  eq stdout "#42 Export orders → w1/w1:t2/w1:p2 · /plan-up · model opus (default) · effort high (default) · size L · base main · new tab w1:t2" "$out"
}

t_ko_no_size_opus_high_plan() {
  ko_herdr; ko_issue '[]'
  ko_go https://github.com/acme/app/issues/42
  has start "$(ko_start opus high)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /plan-up https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
  has report " · no size · " "$out"
}

cases=(
  "kickoff stops when no checkout is found|t_ko_no_checkout"
  "kickoff stops on two checkouts|t_ko_two_checkouts"
  "kickoff writes the one checkout it finds to the map|t_ko_writes_map"
  "ready-to-build goes to sonnet high /ship|t_ko_ready_sonnet_ship"
  "size S goes to opus medium /ship|t_ko_small_opus_ship"
  "size M goes to opus medium /plan-up|t_ko_medium_opus_plan"
  "size L goes to opus high /plan-up|t_ko_large_opus_high_plan"
  "no size goes to opus high /plan-up|t_ko_no_size_opus_high_plan"
)
