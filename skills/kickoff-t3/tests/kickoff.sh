# kickoff.sh: the cases for this skill's kickoff.sh: the T3 check, the
# project add, and the launch line it prints, seen through a fake t3. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The kickoff script.
K="$here/../scripts/kickoff.sh"

# kt_setup <project>: a fresh temp folder T, the fake gh with issue #42
# "Export orders" labelled size/L, one checkout of acme/app at $T/dev/app,
# and a fake t3 first on PATH. t3 logs each call as one line in $T/t3.log.
# <project> is `found` (the checkout is a T3 project), `missing` (it is one
# once `project add` ran), or `broken` (`project add` fails with boom).
kt_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"number":42,"title":"Export orders","labels":[{"name":"size/L"}],"subIssues":{"nodes":[]},"state":"OPEN"}\n' > "$FAKE_GH/issue-view.json"
  printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"acme/app"}\n' > "$FAKE_GH/repo-view.json"
  git init -q -b main "$T/dev/app"
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/dev/app" remote add origin https://github.com/acme/app.git
  [ "$1" != found ] || touch "$T/t3.project"
  cat > "$T/bin/t3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_T3_DIR/t3.log"
case "$1 $2" in
  "thread list") [ -e "$FAKE_T3_DIR/t3.project" ] || { echo "No T3 Code project matches '$4'." >&2; exit 1; }; echo '[]' ;;
  "project add") [ "$FAKE_T3_MODE" != broken ] || { echo boom >&2; exit 1; }; touch "$FAKE_T3_DIR/t3.project" ;;
  *) printf 'fake t3: no route for %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$T/bin/t3"
  export FAKE_T3_DIR="$T" FAKE_T3_MODE="$1"
}

# kt_go [outside|off-path]: kickoff on issue #42 of acme/app from T, with the
# search root and the repo map inside T; inside T3 Code unless `outside` is
# given. `off-path` moves the fake t3 out of PATH and drops every PATH folder
# that holds a t3, so only T3CODE_CLI_PATH names it and the real T3 app is
# never reached.
kt_go() {
  local t3="T3CODE_CLI_PATH=$T/bin/t3" path="$PATH" dir
  [ "${1:-}" != outside ] || t3="KT_OUTSIDE=1"
  if [ "${1:-}" = off-path ]; then
    mkdir -p "$T/t3home"; mv "$T/bin/t3" "$T/t3home/t3"; t3="T3CODE_CLI_PATH=$T/t3home/t3"
    path=""
    while IFS= read -r dir; do
      [ -x "$dir/t3" ] || path="${path:+$path:}$dir"
    done < <(tr ':' '\n' <<<"$PATH")
  fi
  cd "$T"
  run env -u T3CODE_CLI_PATH PATH="$path" "$t3" KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" bash "$K" https://github.com/acme/app/issues/42
}

# kt_line <project>: the launch line kickoff prints for #42 when the project
# was found or added.
kt_line() {
  printf '{"number":42,"title":"Export orders","form":"issue","args":"#42","command":"ship","command_from":"default","mode":"","model":"opus","model_from":"default","effort":"high","effort_from":"default","reason":"size L","base":"main","path":"%s","label":"i42","heading":"#42","message":"/ship #42","thread_title":"#42 Export orders","runtime_mode":"auto","project":"%s"}' "$T/dev/app" "$1"
}

t_kt_launch_line() {
  # Given: #42 size/L, the checkout is a T3 project, inside T3 Code
  kt_setup found
  # When
  kt_go
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_line found)" "$out"
}

t_kt_t3_off_path() {
  # Given: #42 size/L, not a T3 project yet, and no t3 on PATH; only
  # T3CODE_CLI_PATH names the t3 command
  kt_setup missing
  # When
  kt_go off-path
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_line added)" "$out"
}

t_kt_adds_project_once() {
  # Given: #42 size/L, the checkout is not a T3 project yet
  kt_setup missing
  # When: kickoff runs twice
  kt_go; first="$out"
  kt_go
  # Then
  eq "project add calls" "project add $T/dev/app" "$(grep '^project add' "$T/t3.log")"
  eq "run 1" "$(kt_line added)" "$first"
  eq "run 2" "$(kt_line found)" "$out"
}

t_kt_outside_t3() {
  # Given: #42 size/L, T3CODE_CLI_PATH not set
  kt_setup found
  # When
  kt_go outside
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside T3 Code" "$err"
  [ ! -e "$T/t3.log" ] || eq "t3 calls" "" "$(cat "$T/t3.log")"
  [ ! -e "$FAKE_GH/issue-view.calls" ] || eq "issue view calls" "" "$(cat "$FAKE_GH/issue-view.calls")"
}

t_kt_project_add_fails() {
  # Given: #42 size/L, not a T3 project, and `t3 project add` fails with boom
  kt_setup broken
  # When
  kt_go
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: could not add $T/dev/app as a T3 project: boom" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

cases=(
  "the launch line holds the row|t_kt_launch_line"
  "a repo with no project is added once|t_kt_adds_project_once"
  "outside T3 it stops|t_kt_outside_t3"
  "it runs the t3 that T3CODE_CLI_PATH names|t_kt_t3_off_path"
  "a project add that fails stops|t_kt_project_add_fails"
)
