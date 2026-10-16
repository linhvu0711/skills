# sessions-live-tags.sh: the cases for the shared core's sessions/live_tags.py.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
L="$here/../sessions/live_tags.py"

# brief <line>...: a brief file at $T/brief.md, one argument per line.
brief() { printf '%s\n' "$@" > "$T/brief.md"; }

t_lt_tags() {
  repo; fake_gh
  git branch feat/50-x
  printf '{"number":42,"state":"MERGED"}' > "$FAKE_GH/pr-view.1.json"
  printf '{"number":45,"state":"OPEN"}' > "$FAKE_GH/pr-view.2.json"
  printf '{"number":47,"state":"CLOSED"}' > "$FAKE_GH/pr-view.3.json"
  printf '[{"number":51,"state":"OPEN"}]' > "$FAKE_GH/pr-list.feat_51-y.json"
  brief "# State brief" "**Goal:** g" "**PRs and branches:**" \
    "- PR #42 · export CSV" "- PR #45 · date fix" "- PR #47 · old try" \
    "- branch feat/50-x · notes" "- branch feat/51-y · spike" "**Next step:** n"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq brief "# State brief
**Goal:** g
**PRs and branches:**
- [merged #42] PR #42 · export CSV
- [open PR #45] PR #45 · date fix
- [closed #47] PR #47 · old try
- [branch only] branch feat/50-x · notes
- [open PR #51] branch feat/51-y · spike
**Next step:** n" "$out"
}

t_lt_branch_gone() {
  repo; fake_gh
  printf 'gh: Branch not found (HTTP 404)\n' > "$FAKE_GH/branch.fail"
  printf '{"login":"me"}' > "$FAKE_GH/user.json"
  brief "**PRs and branches:**" "- branch feat/60-z · old"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq bullet "- [branch gone] branch feat/60-z · old" "$(printf '%s\n' "$out" | sed -n 2p)"
}

t_lt_origin_only() {
  repo; fake_gh
  printf '{"name":"feat/70-r"}' > "$FAKE_GH/branch.json"
  brief "**PRs and branches:**" "- branch feat/70-r · pushed elsewhere"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq bullet "- [branch only] branch feat/70-r · pushed elsewhere" "$(printf '%s\n' "$out" | sed -n 2p)"
}

t_lt_missing_pr() {
  repo; fake_gh
  printf 'GraphQL: Could not resolve to a PullRequest with the number of 999.\n' > "$FAKE_GH/pr-view.1.fail"
  printf '{"number":45,"state":"OPEN"}' > "$FAKE_GH/pr-view.2.json"
  printf '{"login":"me"}' > "$FAKE_GH/user.json"
  brief "**PRs and branches:**" "- PR #999 · gone" "- PR #45 · date fix"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq bullets "- [state unknown] PR #999 · gone
- [open PR #45] PR #45 · date fix" "$(printf '%s\n' "$out" | sed -n '2,$p')"
}

t_lt_gh_down() {
  repo; fake_gh
  git branch feat/50-x
  printf 'error connecting to api.github.com\n' > "$FAKE_GH/pr-view.fail"
  printf 'error connecting to api.github.com\n' > "$FAKE_GH/user.fail"
  brief "**PRs and branches:**" "- PR #42 · export CSV" "- PR #45 · date fix" "- branch feat/50-x · notes"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq bullets "- [state unknown] PR #42 · export CSV
- [state unknown] PR #45 · date fix
- [state unknown] branch feat/50-x · notes" "$(printf '%s\n' "$out" | sed -n '2,$p')"
  has stderr "live tags: gh failed: error connecting to api.github.com" "$err"
  eq calls 1 "$(cat "$FAKE_GH/pr-view.calls")"
  eq pr-list "no" "$([ -e "$FAKE_GH/pr-list.calls" ] && echo yes || echo no)"
}

t_lt_logged_out() {
  repo; fake_gh
  printf 'To get started with GitHub CLI, please run:  gh auth login\n' > "$FAKE_GH/pr-view.fail"
  printf 'To get started with GitHub CLI, please run:  gh auth login\n' > "$FAKE_GH/user.fail"
  brief "**PRs and branches:**" "- PR #42 · export CSV"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq bullet "- [state unknown] PR #42 · export CSV" "$(printf '%s\n' "$out" | sed -n 2p)"
  has stderr "live tags: gh failed: To get started with GitHub CLI, please run:  gh auth login" "$err"
}

t_lt_no_section() {
  repo; fake_gh
  brief "# State brief" "**Goal:** g" "**Done:** none" "**Next step:** n"
  run python3 "$L" "$T/brief.md"
  eq exit 0 "$code"
  eq brief "$(cat "$T/brief.md")" "$out"
  eq pr-view "no" "$([ -e "$FAKE_GH/pr-view.calls" ] && echo yes || echo no)"
}

cases=(
  "tags each PR and branch from gh and git|t_lt_tags"
  "a branch with no PR, here or on GitHub, is gone|t_lt_branch_gone"
  "a branch with no PR that is only on GitHub is branch only|t_lt_origin_only"
  "a PR gh cannot find is state unknown, and later PRs still get tags|t_lt_missing_pr"
  "gh cannot be reached: every PR is state unknown|t_lt_gh_down"
  "gh not logged in: every PR is state unknown|t_lt_logged_out"
  "a brief with no PRs and branches section comes back unchanged|t_lt_no_section"
)
