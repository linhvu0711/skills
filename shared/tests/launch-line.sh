# launch-line.sh: the cases for the shared core's launch/line.sh, which
# gives a thread's folder and first message. The repo's test.sh sources this
# file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

LL="$here/../launch/line.sh"

# ll_setup [repo]: a fresh temp folder T with the test repo at $T/repo, and
# the fake gh, whose `repo view` names main as the default branch and
# <repo>, acme/app unless given, as the repo gh sees in the checkout.
ll_setup() {
  repo
  fake_gh
  jq -cn --arg r "${1:-acme/app}" '{defaultBranchRef: {name: "main"}, nameWithOwner: $r}' > "$FAKE_GH/repo-view.json"
}

# ll_clone: make the test repo a checkout of acme/app on GitHub.
ll_clone() { git -C "$R" remote add origin https://github.com/acme/app.git; }

# ll_run <args...>: line.sh from T, with T as the search root and the repo
# map inside T.
ll_run() {
  cd "$T"
  run env KICKOFF_DEV_ROOT="$T" KICKOFF_REPO_MAP="$T/map.tsv" bash "$LL" "$@"
}

t_ll_ship_mode() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 ship --mode merge
  # Then
  eq exit 0 "$code"
  eq stdout "{\"path\":\"$T/repo\",\"command\":\"ship\",\"mode\":\"merge\",\"slash_command\":\"/ship --merge\",\"message\":\"/ship --merge #42\"}" "$out"
}

t_ll_ready_pr() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 ready-pr --pr https://github.com/acme/app/pull/80
  # Then
  eq exit 0 "$code"
  has stdout '"message":"/ready-pr #80"' "$out"
}

t_ll_complete_task() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 complete-task
  # Then
  has stdout '"slash_command":"/complete-task --ready","message":"/complete-task --ready #42"' "$out"
}

t_ll_fork_url() {
  # Given: a checkout of acme/app; gh there names upstream/app
  ll_setup upstream/app; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 grill
  # Then
  has stdout '"message":"/grill https://github.com/acme/app/issues/42"' "$out"
}

t_ll_no_checkout() {
  # Given: no checkout of acme/app under $T
  ll_setup
  # When
  ll_run https://github.com/acme/app/issues/42 ship
  # Then
  eq exit 1 "$code"
  eq stderr "stop: no checkout of acme/app under $T. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ll_mode_only_ship() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 grill --mode merge
  # Then
  eq exit 64 "$code"
  eq "stderr line 1" "stop: --mode goes only with ship" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_ll_ship_run() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/70 ship '#12' '#14'
  # Then
  eq exit 0 "$code"
  eq stdout "{\"path\":\"$T/repo\",\"command\":\"ship\",\"mode\":\"\",\"slash_command\":\"/ship\",\"message\":\"/ship #70 #12 #14\"}" "$out"
}

t_ll_ship_on() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 ship on https://github.com/acme/app/pull/80
  # Then
  eq exit 0 "$code"
  eq stdout "{\"path\":\"$T/repo\",\"command\":\"ship\",\"mode\":\"\",\"slash_command\":\"/ship\",\"message\":\"/ship #42 on #80\"}" "$out"
}

t_ll_more_only_ship() {
  # Given: a checkout of acme/app; gh names acme/app
  ll_setup; ll_clone
  # When
  ll_run https://github.com/acme/app/issues/42 triage '#14'
  # Then
  eq exit 64 "$code"
  eq "stderr line 1" "stop: #n and on go only with ship" "$(printf '%s\n' "$err" | sed -n 1p)"
}

cases=(
  "ship takes the run's tickets|t_ll_ship_run"
  "ship on a stack names the PR|t_ll_ship_on"
  "more tickets go only with ship|t_ll_more_only_ship"
  "ship with a mode names the issue by number|t_ll_ship_mode"
  "ready-pr names the PR|t_ll_ready_pr"
  "complete-task waits for go|t_ll_complete_task"
  "a fork clone keeps the URL|t_ll_fork_url"
  "no checkout stops|t_ll_no_checkout"
  "a mode goes only with ship|t_ll_mode_only_ship"
)
