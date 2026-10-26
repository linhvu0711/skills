# merge.sh: the cases for this skill's merge.sh. The repo's test.sh sources
# this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

merge="$here/../scripts/merge.sh"
head_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
merged_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# view <state> [head] [merge-commit]: PR 43 as `gh pr view --json` prints it.
view() {
  local mc=null; [ -n "${3:-}" ] && mc="{\"oid\":\"$3\"}"
  printf '{"url":"https://github.com/o/r/pull/43","state":"%s","headRefOid":"%s","mergeCommit":%s}\n' "$1" "${2:-$head_sha}" "$mc"
}

# methods <merge> <squash> <rebase>: the repo's merge settings, true or false.
methods() {
  printf '{"allow_merge_commit":%s,"allow_squash_merge":%s,"allow_rebase_merge":%s}\n' "$1" "$2" "$3" > "$FAKE_GH/repo.json"
}

# open_then_merged: PR 43 open at head_sha, then merged as merged_sha. gh pr merge
# prints nothing.
open_then_merged() {
  : > "$FAKE_GH/pr-merge.json"
  view OPEN > "$FAKE_GH/pr-view.1.json"
  view MERGED "$head_sha" "$merged_sha" > "$FAKE_GH/pr-view.2.json"
}

t_merge_merge_commit() {
  # Given: PR 43 open at head_sha; the repo allows all three methods
  fake_gh; open_then_merged; methods true true true
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq exit 0 "$code"
  eq stdout "MERGED https://github.com/o/r/pull/43 merge bbbbbbb" "$out"
  eq "merge args" "pr merge 43 --repo o/r --merge --match-head-commit $head_sha" "$(cat "$FAKE_GH/pr-merge.args")"
}

t_merge_falls_back_to_squash() {
  # Given: the repo allows no merge commit
  fake_gh; open_then_merged; methods false true true
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq stdout "MERGED https://github.com/o/r/pull/43 squash bbbbbbb" "$out"
}

t_merge_falls_back_to_rebase() {
  # Given: the repo allows only a rebase
  fake_gh; open_then_merged; methods false false true
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq stdout "MERGED https://github.com/o/r/pull/43 rebase bbbbbbb" "$out"
}

t_merge_already_merged_twice() {
  # Given: PR 43 is merged already
  fake_gh; view MERGED "$head_sha" "$merged_sha" > "$FAKE_GH/pr-view.json"
  # When: it runs twice
  run bash "$merge" o/r 43 --sha "$head_sha"
  eq "first exit" 0 "$code"
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq exit 0 "$code"
  eq stdout "MERGED https://github.com/o/r/pull/43 already bbbbbbb" "$out"
  [ ! -e "$FAKE_GH/pr-merge.calls" ] || eq "merge calls" "" "$(cat "$FAKE_GH/pr-merge.calls")"
}

t_merge_stops_when_head_moved() {
  # Given: the head is not the SHA that ready checked
  fake_gh; view OPEN cccccccccccccccccccccccccccccccccccccccc > "$FAKE_GH/pr-view.json"
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: head moved to ccccccc; ready it again" "$err"
  [ ! -e "$FAKE_GH/pr-merge.calls" ] || eq "merge calls" "" "$(cat "$FAKE_GH/pr-merge.calls")"
}

t_merge_stops_on_closed_pr() {
  # Given: PR 43 is closed
  fake_gh; view CLOSED > "$FAKE_GH/pr-view.json"
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #43 is CLOSED, not open" "$err"
}

t_merge_stops_when_gh_refuses() {
  # Given: gh refuses the merge
  fake_gh; open_then_merged; methods true true true
  printf 'X Pull request o/r#43 is not mergeable: the base branch policy prohibits the merge.\n' > "$FAKE_GH/pr-merge.fail"
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: merge refused: X Pull request o/r#43 is not mergeable: the base branch policy prohibits the merge." "$err"
}

t_merge_stops_when_pr_stays_open() {
  # Given: the merge call works, but the PR stays open
  fake_gh; open_then_merged; methods true true true
  view OPEN > "$FAKE_GH/pr-view.2.json"
  # When
  run bash "$merge" o/r 43 --sha "$head_sha"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: #43 is still open after the merge; a merge queue or a rule holds it" "$err"
}

t_merge_stops_on_short_sha() {
  # Given: PR 43 open at head_sha
  fake_gh; open_then_merged; methods true true true
  # When: the SHA is the short one from a report line
  run bash "$merge" o/r 43 --sha aaaaaaa
  # Then
  eq exit 1 "$code"
  eq stderr "stop: --sha needs the full 40-character head SHA, got: aaaaaaa" "$err"
}

t_merge_prints_usage() {
  # Given: no fixture
  T="$(cd "$(mktemp -d)" && pwd -P)"
  # When
  run bash "$merge" o/r
  # Then
  eq exit 64 "$code"
  eq stderr "usage: merge.sh <owner/repo> <number> --sha <sha>" "$err"
}

cases=(
  "merge.sh merges with a merge commit|t_merge_merge_commit"
  "merge.sh falls back to squash|t_merge_falls_back_to_squash"
  "merge.sh falls back to rebase|t_merge_falls_back_to_rebase"
  "merge.sh says already on a second run|t_merge_already_merged_twice"
  "merge.sh stops when the head moved|t_merge_stops_when_head_moved"
  "merge.sh stops on a closed PR|t_merge_stops_on_closed_pr"
  "merge.sh stops when gh refuses|t_merge_stops_when_gh_refuses"
  "merge.sh stops when the PR stays open|t_merge_stops_when_pr_stays_open"
  "merge.sh stops on a short SHA|t_merge_stops_on_short_sha"
  "merge.sh prints its usage|t_merge_prints_usage"
)
