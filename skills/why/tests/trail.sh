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

cases=(
  "trail names each commit, its PR, the review comment on the file, and the issue it closes|t_trail_commit_pr_issue"
)
