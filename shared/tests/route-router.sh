# route-router.sh: the cases for the shared core's route/router.sh, the
# Router that run-in-t3 and the orchestrator ask for each issue's step. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The Router.
RT="$here/../route/router.sh"

# PR nodes as GitHub gives them.
pr80='{"url":"https://github.com/acme/app/pull/80","state":"OPEN"}'
pr81='{"url":"https://github.com/acme/app/pull/81","state":"OPEN"}'

# rr_go <labels-json> [state] [subs-json] [prs-json] [-- flags...]: the
# Router on issue #42 of acme/app with these labels, open, with no
# sub-issues and no PRs unless given.
rr_go() {
  local pos=() json
  while [ $# -gt 0 ] && [ "$1" != -- ]; do pos+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  local labels="${pos[0]}" state="${pos[1]:-OPEN}" subs="${pos[2]:-[]}" prs="${pos[3]:-[]}"
  json="$(jq -cn --argjson l "$labels" --arg s "$state" --argjson u "$subs" --argjson p "$prs" \
    '{number: 42, state: $s, labels: {nodes: [$l[] | {name: .}]}, subIssues: {nodes: $u},
      closedByPullRequestsReferences: {nodes: $p}}')"
  T="$(cd "$(mktemp -d)" && pwd -P)"
  run bash "$RT" "$@" <<<"$json"
}

t_rr_closed_first() {
  # Given: a closed seed
  # When
  rr_go '["seed"]' CLOSED
  # Then
  eq exit 0 "$code"
  eq stdout '{"stage":"done","step":null,"stop":false,"model":null,"model_from":null,"effort":null,"effort_from":null,"reason":"closed","pr":null}' "$out"
}

t_rr_epic() {
  # Given: an L ticket with an open sub-issue
  # When
  rr_go '["size/L"]' OPEN '[{"number":43,"state":"OPEN"}]'
  # Then
  has stdout '"stage":"epic","step":null' "$out"
  has stdout '"reason":"has sub-issues: the caller routes its open ones"' "$out"
}

t_rr_waiting_task() {
  # Given: a task that waits outside
  # When
  rr_go '["manual","waiting"]'
  # Then
  has stdout '"stage":"waiting","step":null' "$out"
  has stdout '"reason":"a task that waits outside"' "$out"
}

t_rr_task() {
  # Given: a task
  # When
  rr_go '["manual"]'
  # Then
  eq stdout '{"stage":"task","step":"complete-task","stop":false,"model":"opus","model_from":"default","effort":"medium","effort_from":"default","reason":"manual","pr":null}' "$out"
}

t_rr_pr_beats_bug() {
  # Given: a bug with one open PR and one merged PR
  # When
  rr_go '["bug"]' OPEN '[]' "[$pr80,{\"url\":\"https://github.com/acme/app/pull/79\",\"state\":\"MERGED\"}]"
  # Then
  eq stdout '{"stage":"pr","step":"ready-pr","stop":false,"model":"opus","model_from":"default","effort":"medium","effort_from":"default","reason":"open PR https://github.com/acme/app/pull/80","pr":"https://github.com/acme/app/pull/80"}' "$out"
}

t_rr_two_prs() {
  # Given: an S ticket with two open PRs
  # When
  rr_go '["size/S"]' OPEN '[]' "[$pr80,$pr81]"
  # Then
  has stdout '"stage":"pr","step":null,"stop":true' "$out"
  has stdout '"reason":"#42 has 2 open PRs: https://github.com/acme/app/pull/80 https://github.com/acme/app/pull/81"' "$out"
}

t_rr_bug() {
  # Given: a bug with a size label
  # When
  rr_go '["bug","size/S"]'
  # Then
  has stdout '"stage":"bug","step":"triage","stop":false,"model":"opus","model_from":"default","effort":"high"' "$out"
  has stdout '"reason":"bug"' "$out"
}

t_rr_seed() {
  # Given: a seed, its label in capitals
  # When
  rr_go '["Seed"]'
  # Then
  has stdout '"stage":"seed","step":"grill"' "$out"
  has stdout '"effort":"high"' "$out"
}

t_rr_xxl_before_ship() {
  # Given: an XXL label beside ready-to-build
  # When
  rr_go '["size/XXL","ready-to-build"]'
  # Then
  eq stdout '{"stage":"too-big","step":null,"stop":false,"model":null,"model_from":null,"effort":null,"effort_from":null,"reason":"XXL: cut it with /file-epic","pr":null}' "$out"
}

t_rr_ship_efforts() {
  # Given: five tickets, XS to XL
  local lab lines=""
  for lab in size/XS size/S "Size: Medium" size/L size/XL; do
    # When
    rr_go "$(jq -cn --arg l "$lab" '[$l]')"
    lines="$lines${lines:+ · }$(jq -r '"\(.step) \(.effort) \(.reason)"' <<<"$out")"
  done
  # Then
  eq lines "ship medium size XS · ship medium size S · ship high size M · ship high size L · ship xhigh size XL" "$lines"
}

t_rr_ready_to_build() {
  # Given: an L ticket that is ready-to-build
  # When
  rr_go '["ready-to-build","size/L"]'
  # Then
  has stdout '"stage":"ticket","step":"ship"' "$out"
  has stdout '"effort":"medium"' "$out"
  has stdout '"reason":"ready-to-build"' "$out"
}

t_rr_unlabeled() {
  # Given: no label that picks a step
  # When
  rr_go '["p1"]'
  # Then
  eq stdout '{"stage":"unlabeled","step":null,"stop":false,"model":null,"model_from":null,"effort":null,"effort_from":null,"reason":"no label picks a step: propose one","pr":null}' "$out"
}

t_rr_answer_routes() {
  # Given: an unlabeled issue answered ship at size M
  # When
  rr_go '["p1"]' -- --answer ship --size m
  # Then
  has stdout '"stage":"unlabeled","step":"ship"' "$out"
  has stdout '"effort":"high"' "$out"
  has stdout '"reason":"answer ship, size M"' "$out"
}

t_rr_label_beats_answer() {
  # Given: a bug answered ship
  # When
  rr_go '["bug"]' -- --answer ship --size S
  # Then
  has stdout '"stage":"bug","step":"triage"' "$out"
}

t_rr_ready_pr_answer_no_pr() {
  # Given: an unlabeled issue answered ready-pr, with no PR
  # When
  rr_go '["p1"]' -- --answer ready-pr
  # Then
  has stdout '"stage":"unlabeled","step":null,"stop":true' "$out"
  has stdout '"reason":"#42 has no open PR"' "$out"
}

t_rr_close_answer() {
  # Given: an unlabeled issue answered close
  # When
  rr_go '["p1"]' -- --answer close
  # Then
  has stdout '"stage":"unlabeled","step":null,"stop":false' "$out"
  has stdout '"reason":"answer close: yours to close"' "$out"
}

t_rr_named_model_effort() {
  # Given: an S ticket, a model and an effort named
  # When
  rr_go '["size/S"]' -- --model sonnet --effort xhigh
  # Then
  has stdout '"model":"sonnet","model_from":"set","effort":"xhigh","effort_from":"set"' "$out"
}

t_rr_ship_answer_needs_size() {
  # Given: an unlabeled issue answered ship with no size
  # When
  rr_go '["p1"]' -- --answer ship
  # Then
  eq exit 64 "$code"
  eq "stderr line 1" "stop: --answer ship needs --size XS|S|M|L|XL" "$(printf '%s\n' "$err" | sed -n 1p)"
}

cases=(
  "closed comes first|t_rr_closed_first"
  "an epic gets no step|t_rr_epic"
  "a waiting task gets no step|t_rr_waiting_task"
  "a task starts complete-task|t_rr_task"
  "one open PR beats the bug label|t_rr_pr_beats_bug"
  "two open PRs give no step|t_rr_two_prs"
  "a bug starts triage|t_rr_bug"
  "a seed starts grill|t_rr_seed"
  "XXL is caught before ship|t_rr_xxl_before_ship"
  "ship effort by size|t_rr_ship_efforts"
  "ready-to-build ships at medium|t_rr_ready_to_build"
  "no label needs a proposal|t_rr_unlabeled"
  "an answer routes an unlabeled issue|t_rr_answer_routes"
  "a label beats the answer|t_rr_label_beats_answer"
  "a ready-pr answer with no PR gets no step|t_rr_ready_pr_answer_no_pr"
  "a close answer starts nothing|t_rr_close_answer"
  "a named model and effort win|t_rr_named_model_effort"
  "a ship answer needs a size|t_rr_ship_answer_needs_size"
)
