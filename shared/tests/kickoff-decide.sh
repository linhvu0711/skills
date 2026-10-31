# kickoff-decide.sh: the cases for the shared core's kickoff/decide.sh, the
# half of kickoff that both kickoff-herdr and kickoff-t3 run. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The decide script.
D="$here/../kickoff/decide.sh"

# kd_setup <labels-json>: a fresh temp folder T and the fake gh, whose
# `issue view` is a plain issue #42 "Export orders" with these labels and
# whose `repo view` names main as the default branch and acme/app as the
# repo, so gh in the checkout sees the issue's repo.
kd_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"number":42,"title":"Export orders","labels":%s,"subIssues":{"nodes":[]},"state":"OPEN"}\n' "$1" > "$FAKE_GH/issue-view.json"
  printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"acme/app"}\n' > "$FAKE_GH/repo-view.json"
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
  eq stdout "{\"number\":42,\"title\":\"Export orders\",\"form\":\"issue\",\"args\":\"#42\",\"command\":\"ship\",\"command_from\":\"default\",\"mode\":\"\",\"model\":\"opus\",\"model_from\":\"default\",\"effort\":\"high\",\"effort_from\":\"default\",\"reason\":\"size L\",\"base\":\"main\",\"path\":\"$T/dev/app\",\"label\":\"i42\",\"heading\":\"#42\",\"message\":\"/ship #42\"}" "$out"
}

t_kd_size_rows() {
  # Given: #42 with each label set in turn, one checkout of acme/app
  local labels want got=""
  for labels in '[{"name":"ready-to-build"},{"name":"size/XS"}]' '[{"name":"size/S"}]' '[{"name":"size/M"}]' \
      '[{"name":"size/L"}]' '[{"name":"size/XL"}]' '[]'; do
    kd_setup "$labels"; kd_clone "$T/dev/app"
    # When
    kd_run https://github.com/acme/app/issues/42
    eq "exit for $labels" 0 "$code"
    got="$got$(jq -r '"\(.model) \(.effort) \(.command)"' <<<"$out");"
  done
  # Then
  want="opus medium ship;opus medium ship;opus high ship;opus high ship;opus xhigh ship;opus xhigh ship;"
  eq rows "$want" "$got"
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
  printf '{"number":42,"title":"Export orders","form":"issue","args":"%s","command":"%s","command_from":"set","mode":"","model":"opus","model_from":"default","effort":"%s","effort_from":"default","reason":"%s","base":"main","path":"%s","label":"i42","heading":"#42","message":"/%s %s"}' \
    "${4:-#42}" "$1" "$2" "$3" "$T/dev/app" "$1" "${4:-#42}"
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
  eq stderr "stop: --command must be ship, plan-up, triage, grill, or ready-pr, got: deploy" "$err"
  eq stdout "" "$out"
}

t_kd_overrides_command_row() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command triage --model sonnet --effort low https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  has stdout '"command":"triage","command_from":"set","mode":"","model":"sonnet","model_from":"set","effort":"low","effort_from":"set"' "$out"
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
  eq stdout "$(kd_line ready-pr medium "command ready-pr" '#43')" "$out"
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

t_kd_mode_in_message() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command ship --mode merge https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  eq mode+message 'merge /ship --merge #42' "$(jq -r '"\(.mode) \(.message)"' <<<"$out")"
  eq command_from set "$(jq -r .command_from <<<"$out")"
}

t_kd_no_mode_message() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run https://github.com/acme/app/issues/42
  # Then
  eq exit 0 "$code"
  eq mode+message '|/ship #42' "$(jq -r '"\(.mode)|\(.message)"' <<<"$out")"
}

t_kd_mode_needs_ship() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --command grill --mode merge https://github.com/acme/app/issues/42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: --mode goes only with --command ship" "$err"
  eq stdout "" "$out"
}

t_kd_bad_mode() {
  # Given: #42 size/S, one checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  # When
  kd_run --mode full https://github.com/acme/app/issues/42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: --mode must be review, ready, or merge, got: full" "$err"
}

t_kd_heading_forms() {
  # Given: #42 size/S with no sub-issues, PR #80 on feat/79-teams, one
  # checkout of acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  printf '{"headRefName":"feat/79-teams"}\n' > "$FAKE_GH/pr-view.json"
  # When: a set of two, a set too long for one heading, on a PR, a named label
  kd_run https://github.com/acme/app/issues/42 '#43'
  eq "set exit" 0 "$code"
  eq "set" '#42 #43 i42-43' "$(jq -r '"\(.heading) \(.label)"' <<<"$out")"
  kd_run https://github.com/acme/app/issues/42 '#1001' '#1002' '#1003' '#1004' '#1005' '#1006'
  eq "long exit" 0 "$code"
  eq "long" '#42 #1001 #1002 #1003 #1004 +2' "$(jq -r .heading <<<"$out")"
  kd_run https://github.com/acme/app/issues/42 on https://github.com/acme/app/pull/80
  eq "on exit" 0 "$code"
  eq "on" '#42 on #80 i42-on-80' "$(jq -r '"\(.heading) \(.label)"' <<<"$out")"
  kd_run --label exports https://github.com/acme/app/issues/42
  eq "named exit" 0 "$code"
  eq "named" 'exports exports' "$(jq -r '"\(.heading) \(.label)"' <<<"$out")"
}

t_kd_message_numbers() {
  # Given: #42 size/S with no sub-issues, PR #80 on feat/79-teams, one
  # checkout of acme/app whose gh sees acme/app
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  printf '{"headRefName":"feat/79-teams"}\n' > "$FAKE_GH/pr-view.json"
  # When: a set with #43, a set with a bare 43, a layer on PR 80
  kd_run https://github.com/acme/app/issues/42 '#43'
  eq "set exit" 0 "$code"
  eq "set" '/ship #42 #43' "$(jq -r .message <<<"$out")"
  kd_run https://github.com/acme/app/issues/42 43
  eq "bare exit" 0 "$code"
  eq "bare" '/ship #42 #43' "$(jq -r .message <<<"$out")"
  kd_run https://github.com/acme/app/issues/42 on https://github.com/acme/app/pull/80
  eq "on exit" 0 "$code"
  # Then
  eq "on" '/ship #42 on #80' "$(jq -r .message <<<"$out")"
}

t_kd_message_keeps_urls() {
  # Given: #42 size/S, one checkout of acme/app whose gh sees another repo,
  # as a fork clone with an upstream remote can
  kd_setup '[{"name":"size/S"}]'; kd_clone "$T/dev/app"
  printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"upstream/app"}\n' > "$FAKE_GH/repo-view.json"
  # When
  kd_run https://github.com/acme/app/issues/42 '#43'
  # Then
  eq exit 0 "$code"
  eq message '/ship https://github.com/acme/app/issues/42 #43' "$(jq -r .message <<<"$out")"
}

cases=(
  "decide prints the row as one JSON line|t_kd_json_line"
  "the message names the target by number|t_kd_message_numbers"
  "the message keeps URLs when gh in the checkout names another repo|t_kd_message_keeps_urls"
  "the heading is # and the numbers, the label i and the numbers|t_kd_heading_forms"
  "each size takes its row|t_kd_size_rows"
  "decide stops before any launch|t_kd_stops_no_checkout"
  "triage takes the opus high row|t_kd_triage_row"
  "grill takes the opus high row|t_kd_grill_row"
  "a bad command names the five values|t_kd_bad_command"
  "mode merge goes in the message|t_kd_mode_in_message"
  "no mode, no option in the message|t_kd_no_mode_message"
  "mode needs ship|t_kd_mode_needs_ship"
  "a bad mode names the three values|t_kd_bad_mode"
  "model and effort win over a command row|t_kd_overrides_command_row"
  "ready-pr takes the opus medium row and the open PR|t_kd_ready_pr_row"
  "ready-pr with no open PR stops|t_kd_ready_pr_no_pr"
  "ready-pr with two open PRs stops|t_kd_ready_pr_two_prs"
)
