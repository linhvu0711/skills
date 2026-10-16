# trail.sh: the cases for this skill's trail.py. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

trail() { run python3 "$here/../scripts/trail.py" "$@"; }

# commit_app <day> <message> [<body>]: commit app.py with that author date.
commit_app() {
  git add app.py
  if [ -n "${3:-}" ]; then
    GIT_AUTHOR_DATE="$1T10:00:00" git commit -qm "$2" -m "$3"
  else
    GIT_AUTHOR_DATE="$1T10:00:00" git commit -qm "$2"
  fi
}

# two_commits: app.py made on 2026-09-01 and its line 2 changed on
# 2026-10-01. Sets new and old to the first 7 characters of each commit.
two_commits() {
  printf 'a = 1\nids = []\nb = 2\n' > app.py; commit_app 2026-09-01 "add app"
  printf 'a = 1\nids = set()\nb = 2\n' > app.py
  commit_app 2026-10-01 "use a set for the ids" "Order does not matter here."
  new="$(git rev-parse HEAD | cut -c1-7)"; old="$(git rev-parse HEAD~1 | cut -c1-7)"
}

repo_view() { echo '{"nameWithOwner":"o/r"}' > "$FAKE_GH/repo-view.json"; }

no_pr='{"data":{"repository":{"object":{"associatedPullRequests":{"nodes":[]}}}}}'

t_trail_commit_pr_issue() {
  repo; fake_gh; two_commits; repo_view
  cat > "$FAKE_GH/graphql.1.json" <<'EOF'
{"data":{"repository":{"object":{"associatedPullRequests":{"nodes":[{"number":12,"title":"Use a set for ids","url":"https://github.com/o/r/pull/12","body":"Lookups were slow.","closingIssuesReferences":{"nodes":[{"number":7,"title":"Lookups are slow","url":"https://github.com/o/r/issues/7","body":"The ids list has 50k entries."}]},"reviews":{"nodes":[{"author":{"login":"bob"},"state":"APPROVED","body":"","comments":{"nodes":[{"path":"app.py","body":"A set keeps lookups fast."},{"path":"other.py","body":"nit"}]}}]},"comments":{"nodes":[]}}]}}}}}
EOF
  echo "$no_pr" > "$FAKE_GH/graphql.2.json"
  trail app.py:2
  eq exit 0 "$code"
  eq stdout "commit $new 2026-10-01 t: use a set for the ids
  Order does not matter here.
  PR #12 Use a set for ids https://github.com/o/r/pull/12
    body: Lookups were slow.
    review comment @bob on app.py: A set keeps lookups fast.
    issue #7 Lookups are slow https://github.com/o/r/issues/7
      body: The ids list has 50k entries.
commit $old 2026-09-01 t: add app
  no PR found" "$out"
}

t_trail_no_file() {
  repo; fake_gh
  trail nope.py:3
  eq exit 2 "$code"
  eq stdout "No such code: nope.py:3" "$out"
  eq "repo-view calls" "" "$(cat "$FAKE_GH/repo-view.calls" 2>/dev/null)"
}

t_trail_past_end() {
  repo; fake_gh
  printf 'a = 1\nids = []\nb = 2\n' > app.py; commit_app 2026-09-01 "add app"
  trail app.py:40
  eq exit 2 "$code"
  eq stdout "No such code: app.py:40" "$out"
}

t_trail_not_committed() {
  repo; fake_gh
  printf 'a = 1\nids = []\nb = 2\n' > app.py; commit_app 2026-09-01 "add app"
  printf 'c = 3\n' >> app.py
  trail app.py:4
  eq exit 0 "$code"
  eq stdout "No commits: app.py:4 is not committed yet." "$out"
  eq "repo-view calls" "" "$(cat "$FAKE_GH/repo-view.calls" 2>/dev/null)"
}

t_trail_changed_not_committed() {
  repo; fake_gh; two_commits
  printf 'a = 1\nids = {}\nb = 2\n' > app.py
  trail app.py:2
  eq exit 0 "$code"
  eq stdout "No commits: app.py:2 is not committed yet." "$out"
  eq "repo-view calls" "" "$(cat "$FAKE_GH/repo-view.calls" 2>/dev/null)"
}

t_trail_moved_by_insert() {
  repo; fake_gh; two_commits; repo_view; echo "$no_pr" > "$FAKE_GH/graphql.json"
  printf 'a = 1\nx = 0\nids = set()\nb = 2\n' > app.py
  trail app.py:3
  eq exit 0 "$code"
  eq subjects "use a set for the ids
add app" "$(subjects)"
}

t_trail_part_not_committed() {
  repo; fake_gh; two_commits; repo_view; echo "$no_pr" > "$FAKE_GH/graphql.json"
  printf 'a = 1\nids = set()\nb = 3\n' > app.py
  trail app.py:2-3
  eq exit 0 "$code"
  eq "line 1" "Not committed yet: app.py:3" "$(printf '%s\n' "$out" | head -1)"
  eq subjects "use a set for the ids
add app" "$(subjects)"
}

t_trail_gh_unreachable() {
  repo; fake_gh; two_commits
  echo "error connecting to api.github.com" > "$FAKE_GH/repo-view.fail"
  trail app.py:2
  eq exit 0 "$code"
  eq stdout "commit $new 2026-10-01 t: use a set for the ids
  Order does not matter here.
commit $old 2026-09-01 t: add app
GitHub: not reached: error connecting to api.github.com. Commits from $new on are git only." "$out"
  eq "graphql calls" "" "$(cat "$FAKE_GH/graphql.calls" 2>/dev/null)"
}

t_trail_same_pr_once() {
  repo; fake_gh; two_commits; repo_view
  pr='{"data":{"repository":{"object":{"associatedPullRequests":{"nodes":[{"number":12,"title":"Use a set for ids","url":"https://github.com/o/r/pull/12","body":"","closingIssuesReferences":{"nodes":[]},"reviews":{"nodes":[]},"comments":{"nodes":[]}}]}}}}}'
  echo "$pr" > "$FAKE_GH/graphql.json"
  trail app.py:2
  eq exit 0 "$code"
  eq stdout "commit $new 2026-10-01 t: use a set for the ids
  Order does not matter here.
  PR #12 Use a set for ids https://github.com/o/r/pull/12
commit $old 2026-09-01 t: add app
  PR #12 (as above)" "$out"
}

# subjects: the subject of each `commit` line of the output, one per line.
subjects() { printf '%s\n' "$out" | grep '^commit ' | sed 's/^[^:]*: //'; }

t_trail_whole_file_renames() {
  repo; fake_gh; repo_view; echo "$no_pr" > "$FAKE_GH/graphql.json"
  printf 'a = 1\n' > old.py; git add old.py; git commit -qm "add old"
  git mv old.py app.py; git commit -qm "rename to app"
  printf 'b = 2\n' >> app.py; git commit -qam "edit app"
  trail app.py
  eq exit 0 "$code"
  eq subjects "edit app
rename to app
add old" "$(subjects)"
}

t_trail_keeps_newest_and_oldest() {
  repo; fake_gh; repo_view; echo "$no_pr" > "$FAKE_GH/graphql.json"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf 'v = %s\n' "$i" > app.py; git add app.py; git commit -qm "c$i"
  done
  trail app.py:1
  eq exit 0 "$code"
  eq subjects "c12
c11
c10
c9
c8
c7
c6
c5
c4
c1" "$(subjects)"
  eq "after c4" "skipped 2 commits" "$(printf '%s\n' "$out" | grep -A2 ': c4$' | tail -1)"
  eq "graphql calls" 10 "$(cat "$FAKE_GH/graphql.calls")"
}

cases=(
  "trail names each commit, its PR, the review comment on the file, and the issue it closes|t_trail_commit_pr_issue"
  "trail: a second commit of the same PR points at the first|t_trail_same_pr_once"
  "trail: a whole file follows its renames|t_trail_whole_file_renames"
  "trail: more than 10 commits keeps the 9 newest and the oldest|t_trail_keeps_newest_and_oldest"
  "trail: a file that does not exist|t_trail_no_file"
  "trail: a line past the end of the file|t_trail_past_end"
  "trail: a line not committed yet has no history|t_trail_not_committed"
  "trail: a changed line not committed yet has no history|t_trail_changed_not_committed"
  "trail: a line moved by an uncommitted insert keeps its history|t_trail_moved_by_insert"
  "trail: a range with an uncommitted line traces the rest|t_trail_part_not_committed"
  "trail: gh cannot be reached: git only|t_trail_gh_unreachable"
)
