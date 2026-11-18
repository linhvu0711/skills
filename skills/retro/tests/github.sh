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
  printf '%s' '{"number":42,"url":"https://github.com/acme/app/issues/42","title":"Export","closedByPullRequestsReferences":[{"number":45,"url":"https://github.com/acme/app/pull/45"}]}' > "$FAKE_GH/issue-view.json"
  printf '%s' '{"number":45,"url":"https://github.com/acme/app/pull/45","title":"Export CSV","headRefName":"feat/42-export"}' > "$FAKE_GH/pr-view.json"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --issues 42
  # Then
  eq exit 0 "$code"
  eq read_prs "45" "$(nums read_prs)"
  eq read_issues "" "$(nums read_issues)"
}

t_gh_list_run_branch_touches() {
  # Given: issue 42 is closed by PR 45 on branch feat/42-export, which a transcript names
  gh_dir
  printf '%s' '{"number":42,"url":"https://github.com/acme/app/issues/42","title":"Export","closedByPullRequestsReferences":[{"number":45,"url":"https://github.com/acme/app/pull/45"}]}' > "$FAKE_GH/issue-view.json"
  printf '%s' '{"number":45,"url":"https://github.com/acme/app/pull/45","title":"Export CSV","headRefName":"feat/42-export"}' > "$FAKE_GH/pr-view.json"
  printf 'git push -u origin feat/42-export\n' > "$D/1-main.md"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --issues 42
  # Then
  has touched '{"kind": "pr", "number": 45, "by": "1-main.md"}' "$out"
}

t_gh_pr_bundle_log_unreadable() {
  # Given: PR 44 with a failed check whose run log gh cannot read
  gh_dir
  cat > "$FAKE_GH/graphql.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"number":44,"title":"B","url":"https://github.com/acme/app/pull/44","body":"adds b","headRefName":"feat/b",
 "closingIssuesReferences":{"nodes":[]},"reviews":{"nodes":[{"author":{"login":"ann"},"state":"COMMENTED","body":"please add a test"}]},
 "comments":{"nodes":[]},"reviewThreads":{"nodes":[]},
 "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[{"__typename":"CheckRun","name":"test","conclusion":"FAILURE","detailsUrl":"https://github.com/acme/app/actions/runs/9/job/1"}]}}}}]}}}}}
JSON
  printf 'HTTP 410: logs expired\n' > "$FAKE_GH/run-view.fail"
  # When
  run python3 "$G" pr acme/app 44
  # Then
  eq exit 0 "$code"
  has review "please add a test" "$out"
  has log "log not readable: HTTP 410: logs expired" "$out"
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

t_gh_list_run_pr_unreadable() {
  # Given: issue 42 is closed by PR 7, which gh cannot read
  gh_dir
  printf '%s' '{"number":42,"url":"https://github.com/acme/app/issues/42","title":"Export","closedByPullRequestsReferences":[{"number":7,"url":"https://github.com/acme/app/pull/7"}]}' > "$FAKE_GH/issue-view.json"
  printf 'GraphQL: Could not resolve to a PullRequest\n' > "$FAKE_GH/pr-view.fail"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --issues 42
  # Then
  eq exit 0 "$code"
  has skipped '"skipped": [{"url": "https://github.com/acme/app/pull/7", "why": "GraphQL: Could not resolve to a PullRequest"}]' "$out"
}

t_gh_list_run_pr_other_repo() {
  # Given: issue 42 is closed by PR 7 of another repo
  gh_dir
  printf '%s' '{"number":42,"url":"https://github.com/acme/app/issues/42","title":"Export","closedByPullRequestsReferences":[{"number":7,"url":"https://github.com/acme/lib/pull/7"}]}' > "$FAKE_GH/issue-view.json"
  # When
  run python3 "$G" list acme/app --transcripts "$D" --issues 42
  # Then
  has skipped '"skipped": [{"url": "https://github.com/acme/lib/pull/7", "why": "in another repo"}]' "$out"
}

# home_dirs: in a fresh T, a skills repo and a shop repo, each with an HTTPS
# GitHub origin, and the shop linking one skill of the skills repo.
home_dirs() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q "$T/skills"; git -C "$T/skills" remote add origin https://github.com/acme/skills.git
  mkdir -p "$T/skills/skills/plan-up"; : > "$T/skills/skills/plan-up/SKILL.md"
  git init -q "$T/shop"; git -C "$T/shop" remote add origin https://github.com/acme/shop.git
  : > "$T/shop/AGENTS.md"
  mkdir -p "$T/shop/.claude/skills"; ln -s "$T/skills/skills/plan-up" "$T/shop/.claude/skills/plan-up"
}

t_gh_home_linked_skill() {
  # Given: the shop links plan-up from the skills repo
  home_dirs
  # When
  run python3 "$G" home "$T/shop/.claude/skills/plan-up/SKILL.md"
  # Then
  has stdout '"home": "acme/skills", "file": "skills/plan-up/SKILL.md"' "$out"
}

t_gh_home_project_file() {
  # Given: a file of the shop itself
  home_dirs
  # When
  run python3 "$G" home "$T/shop/AGENTS.md"
  # Then
  has stdout '"home": "acme/shop", "file": "AGENTS.md"' "$out"
}

t_gh_home_new_file() {
  # Given: no docs folder in the shop yet
  home_dirs
  # When
  run python3 "$G" home "$T/shop/docs/guide.md"
  # Then
  has stdout '"home": "acme/shop", "file": "docs/guide.md"' "$out"
}

t_gh_home_outside_git() {
  # Given: a plain folder in no git repo
  home_dirs; mkdir -p "$T/loose"; : > "$T/loose/notes.md"
  # When
  run python3 "$G" home "$T/loose/notes.md"
  # Then
  has stdout '"unknown": "in no git repo"' "$out"
}

t_gh_home_no_remote() {
  # Given: a git repo with no remote
  home_dirs; git init -q "$T/local"; : > "$T/local/README.md"
  # When
  run python3 "$G" home "$T/local/README.md"
  # Then
  has stdout '"unknown": "no GitHub remote"' "$out"
}

t_gh_latest_prints_file() {
  # Given: the file on the default branch reads "line one"
  fake_gh; printf 'line one' > "$FAKE_GH/repo.json"
  # When
  run python3 "$G" latest acme/skills skills/plan-up/SKILL.md
  # Then
  eq stdout '{"file": "skills/plan-up/SKILL.md", "text": "line one\n"}' "$out"
}

t_gh_latest_missing() {
  # Given: the case above, but GitHub has no such file
  fake_gh; printf 'line one' > "$FAKE_GH/repo.json"
  printf 'gh: Not Found (HTTP 404)\n' > "$FAKE_GH/repo.fail"
  # When
  run python3 "$G" latest acme/skills skills/plan-up/SKILL.md
  # Then
  eq stdout '{"file": "skills/plan-up/SKILL.md", "missing": true}' "$out"
}

t_gh_latest_stops() {
  # Given: the case above, but gh is not allowed to read it
  fake_gh; printf 'line one' > "$FAKE_GH/repo.json"
  printf 'HTTP 401\n' > "$FAKE_GH/repo.fail"
  # When
  run python3 "$G" latest acme/skills skills/plan-up/SKILL.md
  # Then
  eq stderr "stop: gh could not read skills/plan-up/SKILL.md on acme/skills: HTTP 401" "$err"
}

cases=(
  "list skips a PR a transcript names|t_gh_list_skips_touched_pr"
  "list takes the PRs that close the run's issues|t_gh_list_run_issues"
  "gh failure stops with a stop line|t_gh_list_stops_on_gh_failure"
  "pr bundle holds reviews, threads, and the failed log|t_gh_pr_bundle"
  "list finds a run's PR touched by its branch|t_gh_list_run_branch_touches"
  "pr bundle keeps going when a failed log cannot be read|t_gh_pr_bundle_log_unreadable"
  "list skips a run's PR gh cannot read|t_gh_list_run_pr_unreadable"
  "list skips a run's PR from another repo|t_gh_list_run_pr_other_repo"
  "home of a linked skill file is the skills repo|t_gh_home_linked_skill"
  "home of a project file is the project|t_gh_home_project_file"
  "home of a new file is its folder's repo|t_gh_home_new_file"
  "home unknown outside git|t_gh_home_outside_git"
  "home unknown with no GitHub remote|t_gh_home_no_remote"
  "latest prints the file on the default branch|t_gh_latest_prints_file"
  "latest says missing for a file not on the default branch|t_gh_latest_missing"
  "latest stops when gh cannot read|t_gh_latest_stops"
)
