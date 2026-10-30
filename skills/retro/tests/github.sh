# github.sh: the cases for retro's scripts/github.py. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
G="$here/../scripts/github.py"

# gh_dir: fake_gh, and an empty transcripts folder D.
gh_dir() { fake_gh; D="$T/transcripts"; mkdir -p "$D"; }

# nums <key>: the numbers in the JSON on stdout under <key>, space-joined.
nums() { printf '%s' "$out" | python3 -c 'import json,sys; print(" ".join(str(r["number"]) for r in json.load(sys.stdin)[sys.argv[1]]))' "$1"; }

t_gh_list_skips_touched_pr() {
  # Given: PRs 43 (head feat/a) and 44 (head feat/b); a transcript names PR 43's URL
  gh_dir
  printf '%s' '[{"number":43,"url":"https://github.com/acme/app/pull/43","title":"A","headRefName":"feat/a","closingIssuesReferences":[]},{"number":44,"url":"https://github.com/acme/app/pull/44","title":"B","headRefName":"feat/b","closingIssuesReferences":[]}]' > "$FAKE_GH/pr-list..json"
  printf '[]' > "$FAKE_GH/issue-list.json"
  printf 'opened https://github.com/acme/app/pull/43 for review\n' > "$D/1-main.md"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --since 2026-10-01
  # Then
  eq exit 0 "$code"
  eq read_prs "44" "$(nums read_prs)"
  has touched '{"kind": "pr", "number": 43, "by": "1-main.md"}' "$out"
}

t_gh_list_run_issues() {
  # Given: issue 42 is closed by PR 45; no transcript names either
  gh_dir
  printf '%s' '{"number":42,"url":"https://github.com/acme/app/issues/42","title":"Export","closedByPullRequestsReferences":[{"number":45,"url":"https://github.com/acme/app/pull/45","title":"Export CSV","headRefName":"feat/42-export"}]}' > "$FAKE_GH/issue-view.json"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --issues 42
  # Then
  eq exit 0 "$code"
  eq read_prs "45" "$(nums read_prs)"
  eq read_issues "" "$(nums read_issues)"
}

t_gh_list_stops_on_gh_failure() {
  # Given: gh fails with HTTP 401
  gh_dir; printf 'HTTP 401\n' > "$FAKE_GH/pr-list.fail"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --since 2026-10-01
  # Then
  eq exit 1 "$code"
  eq stderr "stop: gh could not list acme/app: HTTP 401" "$err"
}

t_gh_pr_bundle() {
  # Given: PR 44 with a review, an unresolved thread on a.py:3, and a failed check whose run log ends in an assert
  gh_dir
  cat > "$FAKE_GH/graphql.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"number":44,"title":"B","url":"https://github.com/acme/app/pull/44","body":"adds b","headRefName":"feat/b",
 "closingIssuesReferences":{"nodes":[]},
 "reviews":{"nodes":[{"author":{"login":"ann"},"state":"CHANGES_REQUESTED","body":"please add a test"}]},
 "comments":{"nodes":[]},
 "reviewThreads":{"nodes":[{"isResolved":false,"path":"a.py","line":3,"comments":{"nodes":[{"author":{"login":"ann"},"body":"name this better"}]}}]},
 "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[{"__typename":"CheckRun","name":"test","conclusion":"FAILURE","detailsUrl":"https://github.com/acme/app/actions/runs/9/job/1"}]}}}}]}}}}}
JSON
  printf 'test\tRun tests\tE   assert 1 == 2\n' > "$FAKE_GH/run-view.json"
  # When
  run python3 "$G" pr acme/app 44
  # Then
  eq exit 0 "$code"
  has review "please add a test" "$out"
  has thread "- a.py:3 (unresolved)" "$out"
  has comment "name this better" "$out"
  has log "E   assert 1 == 2" "$out"
}

cases=(
  "list skips a PR a transcript names|t_gh_list_skips_touched_pr"
  "list takes the PRs that close the run's issues|t_gh_list_run_issues"
  "gh failure stops with a stop line|t_gh_list_stops_on_gh_failure"
  "pr bundle holds reviews, threads, and the failed log|t_gh_pr_bundle"
)
