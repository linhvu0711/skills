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

# ko_view <call> <number> <labels-json> [<sub-issues-json>]: the answer to the
# fake gh's nth `issue view`.
ko_view() {
  printf '{"number":%s,"title":"Ticket %s","labels":%s,"subIssues":{"nodes":%s},"state":"OPEN"}\n' "$2" "$2" "$3" "${4:-[]}" > "$FAKE_GH/issue-view.$1.json"
}

t_ko_set_biggest() {
  ko_herdr
  ko_view 1 42 '[{"name":"size/S"}]'
  ko_view 2 43 '[{"name":"size/M"}]'
  ko_go https://github.com/acme/app/issues/42 '#43'
  has start "$(ko_start opus medium i42-43)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42-43 /plan-up https://github.com/acme/app/issues/42 #43" "$(cat "$T/herdr.log")"
  has report " · size M of 2 tickets · " "$out"
}

t_ko_run_all_ready() {
  ko_herdr
  ko_view 1 70 '[]' '[{"number":71,"state":"OPEN"},{"number":73,"state":"OPEN"}]'
  ko_view 2 71 '[{"name":"ready-to-build"},{"name":"size/XS"}]'
  ko_view 3 73 '[{"name":"ready-to-build"},{"name":"size/S"}]'
  ko_go https://github.com/acme/app/issues/70 '#71' '#73'
  has start "$(ko_start sonnet high i71-73)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i71-73 /ship https://github.com/acme/app/issues/70 #71 #73" "$(cat "$T/herdr.log")"
}

t_ko_epic_open_not_manual() {
  ko_herdr
  ko_view 1 70 '[]' '[{"number":71,"state":"OPEN"},{"number":72,"state":"CLOSED"},{"number":74,"state":"OPEN"}]'
  ko_view 2 71 '[{"name":"size/S"}]'
  ko_view 3 74 '[{"name":"manual"}]'
  ko_go https://github.com/acme/app/issues/70
  has start "$(ko_start opus medium i70)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i70 /ship https://github.com/acme/app/issues/70" "$(cat "$T/herdr.log")"
  eq "issue view calls" 3 "$(cat "$FAKE_GH/issue-view.calls")"
}

t_ko_epic_none_open() {
  ko_herdr
  ko_view 1 70 '[]' '[{"number":71,"state":"CLOSED"}]'
  ko_go https://github.com/acme/app/issues/70
  eq exit 1 "$code"
  eq stderr "stop: #70 has no open ticket for an agent" "$err"
  [ ! -e "$T/herdr.log" ] || eq "herdr calls" "" "$(cat "$T/herdr.log")"
}

t_ko_guessed_size() {
  ko_herdr; ko_issue '[]'
  ko_go --size 42=S https://github.com/acme/app/issues/42
  has start "$(ko_start opus medium)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /ship https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
  has report " · size S, guessed · " "$out"
}

t_ko_guessed_smaller() {
  ko_herdr
  ko_view 1 42 '[{"name":"size/M"}]'
  ko_view 2 43 '[]'
  ko_go --size 43=S https://github.com/acme/app/issues/42 '#43'
  has report " · size M of 2 tickets, 1 guessed · " "$out"
}

t_ko_bad_size() {
  ko_herdr; ko_issue '[]'
  ko_go --size 42=huge https://github.com/acme/app/issues/42
  eq exit 1 "$code"
  eq stderr "stop: --size takes <n>=XS|S|M|L|XL, got: 42=huge" "$err"
  [ ! -e "$T/herdr.log" ] || eq "herdr calls" "" "$(cat "$T/herdr.log")"
}

t_ko_overrides() {
  ko_herdr; ko_issue '[{"name":"ready-to-build"},{"name":"size/XS"}]'
  ko_go --model haiku --effort low --command plan-up https://github.com/acme/app/issues/42
  has start "$(ko_start haiku low)" "$(cat "$T/herdr.log")"
  has prompt "agent prompt i42 /plan-up https://github.com/acme/app/issues/42" "$(cat "$T/herdr.log")"
  has report " · /plan-up · model haiku (set) · effort low (set) · ready-to-build · " "$out"
}

t_ko_bad_command() {
  ko_herdr; ko_issue '[{"name":"size/S"}]'
  ko_go --command deploy https://github.com/acme/app/issues/42
  eq exit 1 "$code"
  eq stderr "stop: --command must be ship or plan-up, got: deploy" "$err"
  [ ! -e "$FAKE_GH/issue-view.calls" ] || eq "issue view calls" "" "$(cat "$FAKE_GH/issue-view.calls")"
}

t_ko_bad_effort() {
  ko_herdr; ko_issue '[{"name":"size/S"}]'
  ko_go --effort huge https://github.com/acme/app/issues/42
  eq exit 1 "$code"
  eq stderr "stop: --effort must be low, medium, high, xhigh, or max, got: huge" "$err"
}

t_ko_on_name() {
  ko_herdr; ko_issue '[{"name":"size/M"}]'
  printf '{"headRefName":"feat/79-teams"}\n' > "$FAKE_GH/pr-view.json"
  ko_go https://github.com/acme/app/issues/42 on https://github.com/acme/app/pull/80
  has rename "pane rename w1:p2 i42-on-80" "$(cat "$T/herdr.log")"
  has start "$(ko_start opus medium i42-on-80)" "$(cat "$T/herdr.log")"
}

t_ko_no_dry_run() {
  ko_herdr; ko_issue '[{"name":"size/S"}]'
  ko_go --dry-run https://github.com/acme/app/issues/42
  eq exit 1 "$code"
  eq stderr "stop: unexpected argument: --dry-run" "$err"
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
  "a set takes its biggest ticket|t_ko_set_biggest"
  "a run all ready-to-build goes to sonnet|t_ko_run_all_ready"
  "an epic counts open tickets, not manual|t_ko_epic_open_not_manual"
  "an epic with no open ticket stops|t_ko_epic_none_open"
  "a guessed size counts|t_ko_guessed_size"
  "a guessed smaller ticket is in the report|t_ko_guessed_smaller"
  "a bad size stops|t_ko_bad_size"
  "overrides win and the report says set|t_ko_overrides"
  "a bad command stops|t_ko_bad_command"
  "a bad effort stops|t_ko_bad_effort"
  "the pane is named by numbers|t_ko_on_name"
  "dry-run is gone|t_ko_no_dry_run"
)
