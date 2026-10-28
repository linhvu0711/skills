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

cases=(
  "decide prints the row as one JSON line|t_kd_json_line"
  "decide stops before any launch|t_kd_stops_no_checkout"
)
