# kickoff.sh: the cases for this skill's kickoff.sh: route, thread, and
# label, the T3 check, and the project add, seen through the fake gh and a
# fake t3. The repo's test.sh sources this file after test-lib.sh and runs
# its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The kickoff script.
K="$here/../scripts/kickoff.sh"

# kt_setup <project>: a fresh temp folder T, the fake gh, one checkout of
# acme/app at $T/dev/app, and a fake t3 first on PATH. t3 logs each call as
# one line in $T/t3.log. <project> is `found` (the checkout is a T3 project),
# `missing` (it is one once `project add` ran), or `broken` (`project add`
# fails with boom). GitHub holds the issues of kt_issues.
kt_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"acme/app"}\n' > "$FAKE_GH/repo-view.json"
  kt_issues > "$FAKE_GH/graphql.app.json"
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

# kt_issue <n> <title> <labels> [parent] [subs] [prs]: one issue as GitHub's
# GraphQL gives it. <labels> is a comma list, [parent] a number, [subs] a
# comma list of open sub-issue numbers, [prs] a comma list of open PR URLs.
kt_issue() {
  jq -cn --argjson n "$1" --arg t "$2" --arg l "$3" --arg p "${4:-}" --arg s "${5:-}" --arg r "${6:-}" '
    def list: if . == "" then [] else split(",") end;
    {number: $n, title: $t, state: "OPEN", url: "https://github.com/acme/app/issues/\($n)",
     parent: (if $p == "" then null else {number: ($p | tonumber), repository: {nameWithOwner: "acme/app"}} end),
     labels: {nodes: [$l | list | .[] | {name: .}]},
     subIssues: {nodes: [$s | list | .[] | {number: tonumber, title: "", state: "OPEN", repository: {nameWithOwner: "acme/app"}}]},
     closedByPullRequestsReferences: {nodes: [$r | list | .[] | {url: ., state: "OPEN"}]}}'
}

# kt_issues: the repo's issues, keyed as kickoff.sh asks for them.
# #12 and #14 are tickets of epic #70; #42 a bug, #43 has open PR #80, #44
# is size S, #18 size M, #15 and #17 bugs, #16 has no label, and #71 a
# closed epic with open ticket #12. Epic #72 holds #44 and acme/lib#42;
# #46 and #47 are size S tickets of acme/lib#9.
kt_issues() {
  jq -cn \
    --argjson i12 "$(kt_issue 12 "Add CSV" size/S 70)" \
    --argjson i14 "$(kt_issue 14 "Add JSON" size/M 70)" \
    --argjson i70 "$(kt_issue 70 "Order export" "" "" 12,14)" \
    --argjson i42 "$(kt_issue 42 "Login fails" bug)" \
    --argjson i43 "$(kt_issue 43 "Fix export" "" "" "" https://github.com/acme/app/pull/80)" \
    --argjson i44 "$(kt_issue 44 "Export orders" size/S)" \
    --argjson i18 "$(kt_issue 18 "Export XML" size/M)" \
    --argjson i15 "$(kt_issue 15 "Slow page" bug)" \
    --argjson i17 "$(kt_issue 17 "Bad link" bug)" \
    --argjson i16 "$(kt_issue 16 "Old idea" "")" \
    --argjson i71 "$(kt_issue 71 "Old export" "" "" 12 | jq -c '.state = "CLOSED"')" \
    --argjson i72 "$(kt_issue 72 "Shared login" "" "" 44 | jq -c '.subIssues.nodes += [{number: 42, title: "Lib login", state: "OPEN", repository: {nameWithOwner: "acme/lib"}}]')" \
    --argjson i46 "$(kt_issue 46 "Lib CSV" size/S 9 | jq -c '.parent.repository.nameWithOwner = "acme/lib"')" \
    --argjson i47 "$(kt_issue 47 "Lib JSON" size/S 9 | jq -c '.parent.repository.nameWithOwner = "acme/lib"')" \
    '{data: {repository: {i12: $i12, i14: $i14, i70: $i70, i42: $i42, i43: $i43, i44: $i44, i18: $i18, i15: $i15, i17: $i17, i16: $i16, i71: $i71, i72: $i72, i46: $i46, i47: $i47}}}'
}

# kt_go [outside|off-path] <args...>: kickoff from T, with the search root
# and the repo map inside T; inside T3 Code unless `outside` is given.
# `off-path` moves the fake t3 out of PATH and drops every PATH folder that
# holds a t3, so only T3CODE_CLI_PATH names it and the real T3 app is never
# reached.
kt_go() {
  local t3="T3CODE_CLI_PATH=$T/bin/t3" path="$PATH" dir
  if [ "${1:-}" = outside ]; then t3="KT_OUTSIDE=1"; shift; fi
  if [ "${1:-}" = off-path ]; then
    shift
    mkdir -p "$T/t3home"; mv "$T/bin/t3" "$T/t3home/t3"; t3="T3CODE_CLI_PATH=$T/t3home/t3"
    path=""
    while IFS= read -r dir; do
      [ -x "$dir/t3" ] || path="${path:+$path:}$dir"
    done < <(tr ':' '\n' <<<"$PATH")
  fi
  cd "$T"
  run env -u T3CODE_CLI_PATH PATH="$path" "$t3" KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" bash "$K" "$@"
}

# kt_thread <step> <effort> <reason> <message> <title> <project>: the thread
# line for the checkout at $T/dev/app.
kt_thread() {
  jq -cn --arg step "$1" --arg effort "$2" --arg reason "$3" --arg message "$4" --arg title "$5" --arg project "$6" --arg path "$T/dev/app" \
    '{step: $step, model: "opus", model_from: "default", effort: $effort, effort_from: "default", reason: $reason,
      path: $path, slash_command: "/\($step)", message: $message, thread_title: $title, project: $project}'
}

t_kt_route_steps() {
  # Given: #42 a bug, #43 with open PR #80, #44 size S
  kt_setup found
  # When
  kt_go route acme/app 42 43 44
  # Then
  eq exit 0 "$code"
  eq stdout '{"number":42,"title":"Login fails","parent":null,"stage":"bug","step":"triage","stop":false,"model":"opus","model_from":"default","effort":"high","effort_from":"default","reason":"bug","pr":null}
{"number":43,"title":"Fix export","parent":null,"stage":"pr","step":"ready-pr","stop":false,"model":"opus","model_from":"default","effort":"medium","effort_from":"default","reason":"open PR https://github.com/acme/app/pull/80","pr":"https://github.com/acme/app/pull/80"}
{"number":44,"title":"Export orders","parent":null,"stage":"ticket","step":"ship","stop":false,"model":"opus","model_from":"default","effort":"medium","effort_from":"default","reason":"size S","pr":null}' "$out"
}

t_kt_bug_thread() {
  # Given: #42 a bug
  kt_setup found
  # When
  kt_go thread acme/app triage 42
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_thread triage high bug "/triage #42" "#42 Login fails" found)" "$out"
}

t_kt_pr_thread() {
  # Given: #43 with open PR #80
  kt_setup found
  # When
  kt_go thread acme/app ready-pr 43
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_thread ready-pr medium "open PR https://github.com/acme/app/pull/80" "/ready-pr #80" "#43 Fix export" found)" "$out"
}

t_kt_ship_thread() {
  # Given: #44 size S
  kt_setup found
  # When
  kt_go thread acme/app ship 44
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_thread ship medium "size S" "/ship #44" "#44 Export orders" found)" "$out"
}

t_kt_gh_fails() {
  # Given: GitHub answers the issue read with HTTP 502
  kt_setup found
  rm "$FAKE_GH/graphql.app.json"; echo "HTTP 502" > "$FAKE_GH/graphql.app.fail"
  # When
  kt_go route acme/app 42
  # Then
  eq exit 2 "$code"
  eq "last stderr line" "stop: gh could not read acme/app: HTTP 502" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

t_kt_no_checkout() {
  # Given: #44 size S, and no checkout of acme/app
  kt_setup found
  rm -rf "$T/dev/app"; mkdir -p "$T/dev"
  # When
  kt_go thread acme/app ship 44
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: no checkout of acme/app under $T/dev. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
  [ ! -e "$T/t3.log" ] || lacks "t3 calls" "project add" "$(cat "$T/t3.log")"
}

t_kt_outside_t3() {
  # Given: #42 a bug, T3CODE_CLI_PATH not set
  kt_setup found
  # When
  kt_go outside route acme/app 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside T3 Code" "$err"
  [ ! -e "$FAKE_GH/graphql.calls" ] || eq "graphql calls" "" "$(cat "$FAKE_GH/graphql.calls")"
}

t_kt_adds_project_once() {
  # Given: #44 size S, the checkout is not a T3 project yet
  kt_setup missing
  # When: the thread line is made twice
  kt_go thread acme/app ship 44; first="$out"
  kt_go thread acme/app ship 44
  # Then
  eq "project add calls" "project add $T/dev/app" "$(grep '^project add' "$T/t3.log")"
  eq "run 1" "$(kt_thread ship medium "size S" "/ship #44" "#44 Export orders" added)" "$first"
  eq "run 2" "$(kt_thread ship medium "size S" "/ship #44" "#44 Export orders" found)" "$out"
}

t_kt_t3_off_path() {
  # Given: #44 size S, not a T3 project yet, and no t3 on PATH; only
  # T3CODE_CLI_PATH names the t3 command
  kt_setup missing
  # When
  kt_go off-path thread acme/app ship 44
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_thread ship medium "size S" "/ship #44" "#44 Export orders" added)" "$out"
}

t_kt_project_add_fails() {
  # Given: #44 size S, not a T3 project, and `t3 project add` fails with boom
  kt_setup broken
  # When
  kt_go thread acme/app ship 44
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: could not add $T/dev/app as a T3 project: boom" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

t_kt_runs_by_path() {
  # Given: #42 a bug, T3CODE_CLI_PATH not set
  kt_setup found
  # When: the script runs by path, with no bash in front, as SKILL.md runs it
  cd "$T"
  run env -u T3CODE_CLI_PATH "$K" route acme/app 42
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside T3 Code" "$err"
}

t_kt_highest_effort() {
  # Given: #44 size S and #18 size M, with no parent
  kt_setup found
  # When
  kt_go thread acme/app ship 44 18
  # Then
  eq exit 0 "$code"
  eq stdout "$(kt_thread ship high "size M of 2 tickets" "/ship #44 #18" "#44 #18 Export orders" found)" "$out"
}

t_kt_run_of_epic() {
  # Given: #12 and #14, both tickets of epic #70
  kt_setup found
  # When
  kt_go thread acme/app ship 12 14
  # Then
  eq exit 0 "$code"
  eq message "/ship #70 #12 #14" "$(jq -r .message <<<"$out")"
}

t_kt_whole_epic() {
  # Given: epic #70 with open tickets #12 (size S) and #14 (size M)
  kt_setup found
  # When
  kt_go thread acme/app ship 70
  # Then
  eq exit 0 "$code"
  eq line "/ship #70|size M of 2 tickets|#70 Order export" "$(jq -r '[.message, .reason, .thread_title] | join("|")' <<<"$out")"
}

t_kt_route_epic() {
  # Given: epic #70 with open tickets #12 and #14
  kt_setup found
  # When
  kt_go route acme/app 70
  # Then
  eq exit 0 "$code"
  eq lines '70|epic||null
12|ticket|ship|70
14|ticket|ship|70' "$(jq -r '[.number, .stage, (.step // ""), .parent] | map(tostring) | join("|")' <<<"$out")"
}

t_kt_route_closed_epic() {
  # Given: closed epic #71 with open ticket #12
  kt_setup found
  # When
  kt_go route acme/app 71
  # Then
  eq exit 0 "$code"
  eq lines '71|done|' "$(jq -r '[.number, .stage, (.step // "")] | map(tostring) | join("|")' <<<"$out")"
}

t_kt_thread_closed_epic() {
  # Given: closed epic #71 with open ticket #12
  kt_setup found
  # When
  kt_go thread acme/app ship 71
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: #71 is closed" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

t_kt_route_other_repo_child() {
  # Given: epic #72 holds #44 (size S; its own data names no parent) and
  # acme/lib#42; acme/app#42 is a bug
  kt_setup found
  # When
  kt_go route acme/app 72
  # Then
  eq exit 0 "$code"
  eq lines '72|epic||null|has sub-issues: the caller routes its open ones
44|ticket|ship|null|size S
42|null||72|in acme/lib: start it from there' "$(jq -r '[.number, .stage, (.step // ""), .parent, .reason] | map(tostring) | join("|")' <<<"$out")"
}

t_kt_thread_other_repo_child() {
  # Given: epic #72 holds #44 (size S) and acme/lib#42
  kt_setup found
  # When
  kt_go thread acme/app ship 72
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: #72 has tickets in other repos: name its tickets in acme/app" "$(printf '%s\n' "$err" | tail -1)"
}

t_kt_other_repo_parent() {
  # Given: #46 and #47, size S tickets of acme/lib#9
  kt_setup found
  # When
  kt_go thread acme/app ship 46 47
  # Then
  eq exit 0 "$code"
  eq message "/ship #46 #47" "$(jq -r .message <<<"$out")"
}

t_kt_stack_on_open_pr() {
  # Given: #44 size S, and PR #80 open
  kt_setup found
  echo '{"state":"OPEN","url":"https://github.com/acme/app/pull/80"}' > "$FAKE_GH/pr-view.json"
  # When
  kt_go thread acme/app --on 80 ship 44
  # Then
  eq exit 0 "$code"
  eq line "/ship #44 on #80|#44 on #80 Export orders" "$(jq -r '[.message, .thread_title] | join("|")' <<<"$out")"
}

t_kt_stack_on_merged_pr() {
  # Given: #44 size S, and PR #80 merged
  kt_setup found
  echo '{"state":"MERGED","url":"https://github.com/acme/app/pull/80"}' > "$FAKE_GH/pr-view.json"
  # When
  kt_go thread acme/app --on 80 ship 44
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: PR #80 is merged, not open: nothing to stack on" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

t_kt_stack_pr_unreadable() {
  # Given: #44 size S, and GitHub cannot find PR #999
  kt_setup found
  echo "no pull requests found" > "$FAKE_GH/pr-view.fail"
  # When
  kt_go thread acme/app --on 999 ship 44
  # Then
  eq exit 2 "$code"
  eq "last stderr line" "stop: gh could not read PR #999 in acme/app: no pull requests found" "$(printf '%s\n' "$err" | tail -1)"
}

t_kt_bug_in_ship() {
  # Given: #44 size S, #15 a bug
  kt_setup found
  # When
  kt_go thread acme/app ship 44 15
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: #15 goes to /triage, not /ship" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

t_kt_only_ship_many() {
  # Given: #15 and #17, both bugs
  kt_setup found
  # When
  kt_go thread acme/app triage 15 17
  # Then
  eq exit 64 "$code"
  eq "stderr line 1" "stop: only ship takes several issues" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_kt_answer_effort() {
  # Given: #16 with no label
  kt_setup found
  # When
  kt_go route acme/app --answer 16=ship --size 16=M 16
  # Then
  eq exit 0 "$code"
  eq stdout '{"number":16,"title":"Old idea","parent":null,"stage":"unlabeled","step":"ship","stop":false,"model":"opus","model_from":"default","effort":"high","effort_from":"default","reason":"answer ship, size M","pr":null}' "$out"
}

t_kt_unlabeled_no_thread() {
  # Given: #16 with no label, and no answer
  kt_setup found
  # When
  kt_go thread acme/app ship 16
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: #16 has no step: no label picks a step: propose one" "$(printf '%s\n' "$err" | tail -1)"
  eq stdout "" "$out"
}

t_kt_label_once() {
  # Given: #16 with no label; after the edit GitHub shows it labeled bug
  kt_setup found
  rm "$FAKE_GH/graphql.app.json"
  kt_issues > "$FAKE_GH/graphql.1.json"
  jq -cn --argjson i "$(kt_issue 16 "Old idea" bug)" '{data: {repository: {i16: $i}}}' > "$FAKE_GH/graphql.2.json"
  : > "$FAKE_GH/issue-edit.json"
  # When: the yes is written twice
  kt_go label acme/app 16 triage; first="$out"
  kt_go label acme/app 16 triage
  # Then
  eq "run 1" "labeled #16 bug" "$first"
  eq "run 2" "labeled #16 bug" "$out"
  eq "issue edit args" "issue edit 16 --repo acme/app --add-label bug" "$(cat "$FAKE_GH/issue-edit.args")"
}

t_kt_label_routed() {
  # Given: #42 already labeled bug
  kt_setup found
  # When
  kt_go label acme/app 42 grill
  # Then
  eq exit 0 "$code"
  eq stdout "not labeled #42: its labels route it: bug" "$out"
  [ ! -e "$FAKE_GH/issue-edit.calls" ] || eq "issue edit calls" "" "$(cat "$FAKE_GH/issue-edit.calls")"
}

cases=(
  "route gives each issue its step|t_kt_route_steps"
  "a bug thread is triage at high|t_kt_bug_thread"
  "a PR thread names the PR|t_kt_pr_thread"
  "a size S thread is ship at medium|t_kt_ship_thread"
  "a ship thread takes the highest effort|t_kt_highest_effort"
  "tickets of one epic go as a run|t_kt_run_of_epic"
  "a whole epic is one ship thread|t_kt_whole_epic"
  "route opens an epic|t_kt_route_epic"
  "route keeps a closed epic shut|t_kt_route_closed_epic"
  "a closed epic gets no thread|t_kt_thread_closed_epic"
  "route gives a child in another repo no step|t_kt_route_other_repo_child"
  "an epic with a child in another repo stops|t_kt_thread_other_repo_child"
  "a parent in another repo makes no run|t_kt_other_repo_parent"
  "a stack on an open PR names it|t_kt_stack_on_open_pr"
  "a stack on a merged PR stops|t_kt_stack_on_merged_pr"
  "a stack PR gh cannot read stops|t_kt_stack_pr_unreadable"
  "a bug in a ship thread stops|t_kt_bug_in_ship"
  "only ship takes several issues|t_kt_only_ship_many"
  "an answer gives the proposal its effort|t_kt_answer_effort"
  "an unlabeled issue gets no thread line|t_kt_unlabeled_no_thread"
  "a yes writes its label once|t_kt_label_once"
  "a yes on a routed issue writes nothing|t_kt_label_routed"
  "an unreadable GitHub stops|t_kt_gh_fails"
  "no checkout stops the thread line|t_kt_no_checkout"
  "outside T3 it stops|t_kt_outside_t3"
  "a repo with no project is added once|t_kt_adds_project_once"
  "it runs the t3 that T3CODE_CLI_PATH names|t_kt_t3_off_path"
  "a project add that fails stops|t_kt_project_add_fails"
  "kickoff runs by path|t_kt_runs_by_path"
)
