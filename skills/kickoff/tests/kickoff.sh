# kickoff.sh: the cases for this skill's kickoff.sh, its checkout lookup only.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

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

cases=(
  "kickoff stops when no checkout is found|t_ko_no_checkout"
  "kickoff stops on two checkouts|t_ko_two_checkouts"
  "kickoff writes the one checkout it finds to the map|t_ko_writes_map"
)
