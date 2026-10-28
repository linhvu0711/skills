# kickoff-decide.sh: the cases for the shared core's kickoff/decide.sh, the
# half of kickoff that both kickoff-herdr and kickoff-t3 run. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The decide script.
D="$here/../kickoff/decide.sh"

# kd_setup <labels-json>: a fresh temp folder T and the fake gh, whose
# `issue view` is a plain issue #42 "Export orders" with these labels and
# whose `repo view` names main as the default branch.
kd_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"number":42,"title":"Export orders","labels":%s,"subIssues":{"nodes":[]},"state":"OPEN"}\n' "$1" > "$FAKE_GH/issue-view.json"
  printf '{"defaultBranchRef":{"name":"main"}}\n' > "$FAKE_GH/repo-view.json"
}

# kd_clone <dir>: a main checkout at <dir> whose origin is acme/app on GitHub.
kd_clone() {
  git init -q -b main "$1"
  git -C "$1" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$1" remote add origin https://github.com/acme/app.git
}

# kd_run <args...>: decide.sh from T, with the search root and the repo map
# inside T.
kd_run() {
  cd "$T"
  run env KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" bash "$D" "$@"
}

t_kd_json_line() {
  # Given: #42 "Export orders", size/L, one checkout of acme/app
  kd_setup '[{"name":"size/L"}]'; kd_clone "$T/dev/app"
  # When
  kd_run https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  eq stdout "{\"number\":42,\"title\":\"Export orders\",\"form\":\"issue\",\"args\":\"https://github.com/acme/app/issues/42\",\"command\":\"plan-up\",\"command_from\":\"default\",\"model\":\"opus\",\"model_from\":\"default\",\"effort\":\"high\",\"effort_from\":\"default\",\"reason\":\"size L\",\"base\":\"main\",\"path\":\"$T/dev/app\",\"label\":\"i42\"}" "$out"
}

t_kd_stops_no_checkout() {
  # Given: #42 size/S, no checkout under $T/dev
  kd_setup '[{"name":"size/S"}]'; mkdir -p "$T/dev"
  # When
  kd_run https://github.com/acme/app/issues/42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: no checkout of acme/app under $T/dev. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$err"
  eq stdout "" "$out"
}

# kd_line <command> <effort> <reason> [<args>]: the JSON line decide prints
# for #42 under --command <command>, on model opus.
kd_line() {
  printf '{"number":42,"title":"Export orders","form":"issue","args":"%s","command":"%s","command_from":"set","model":"opus","model_from":"default","effort":"%s","effort_from":"default","reason":"%s","base":"main","path":"%s","label":"i42"}' \
    "${4:-https://github.com/acme/app/issues/42}" "$1" "$2" "$3" "$T/dev/app"
}

t_kd_triage_row() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command triage https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  eq stdout "$(kd_line triage high "command triage")" "$out"
}

t_kd_grill_row() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command grill https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  eq stdout "$(kd_line grill high "command grill")" "$out"
}

t_kd_bad_command() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command deploy https://github.com/acme/app/issues/42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: --command must be ship-ready, ship-full, plan-up, triage, grill, or ready-pr, got: deploy" "$err"
  eq stdout "" "$out"
}

t_kd_overrides_command_row() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command triage --model sonnet --effort low https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  has stdout '"command":"triage","command_from":"set","model":"sonnet","model_from":"set","effort":"low","effort_from":"set"' "$out"
}

# kd_prs <node>...: the GraphQL answer for #42's closing PRs, one
# `{"url":…,"state":…}` node per argument.
kd_prs() {
  printf '{"data":{"repository":{"issue":{"closedByPullRequestsReferences":{"nodes":[%s]}}}}}\n' \
    "$(IFS=,; printf '%s' "$*")" > "$FAKE_GH/graphql.json"
}

t_kd_ready_pr_row() {
  # Given: #42 size/L, one merged and one open PR close it
  kd_setup '[{"name":"size/L"}]'; kd_clone "$T/dev/app"
  kd_prs '{"url":"https://github.com/acme/app/pull/40","state":"MERGED"}' '{"url":"https://github.com/acme/app/pull/43","state":"OPEN"}'
  # When
  kd_run --command ready-pr https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  eq stdout "$(kd_line ready-pr medium "command ready-pr" https://github.com/acme/app/pull/43)" "$out"
}

t_kd_ready_pr_no_pr() {
  # Given: #42 size/S, only a merged PR closes it
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  kd_prs '{"url":"https://github.com/acme/app/pull/40","state":"MERGED"}'
  # When
  kd_run --command ready-pr https://github.com/acme/app/issues/42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has no open PR" "$err"
  eq stdout "" "$out"
}

t_kd_ready_pr_two_prs() {
  # Given: #42 size/S, two open PRs close it
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  kd_prs '{"url":"https://github.com/acme/app/pull/43","state":"OPEN"}' '{"url":"https://github.com/acme/app/pull/44","state":"OPEN"}'
  # When
  kd_run --command ready-pr https://github.com/acme/app/issues/42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #42 has 2 open PRs: https://github.com/acme/app/pull/43 https://github.com/acme/app/pull/44" "$err"
  eq stdout "" "$out"
}

cases=(
  "decide prints the row as one JSON line|t_kd_json_line"
  "decide stops before any launch|t_kd_stops_no_checkout"
  "triage takes the opus high row|t_kd_triage_row"
  "grill takes the opus high row|t_kd_grill_row"
  "a bad command names the six values|t_kd_bad_command"
  "model and effort win over a command row|t_kd_overrides_command_row"
  "ready-pr takes the opus medium row and the open PR|t_kd_ready_pr_row"
  "ready-pr with no open PR stops|t_kd_ready_pr_no_pr"
  "ready-pr with two open PRs stops|t_kd_ready_pr_two_prs"
)
