# reviewers.sh: the cases for the shared core's review/reviewers.sh, driven
# through the fake gh. The repo's test.sh sources this file after test-lib.sh
# and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# reviewers <args...>: run reviewers.sh on the fake gh.
reviewers() { run bash "$here/../review/reviewers.sh" "$@"; }

# pr_node [reviews] [comments] [contexts]: the graphql answer for one PR,
# each part a JSON array body.
pr_node() {
  printf '{"data":{"repository":{"pullRequest":{"reviews":{"nodes":[%s]},"comments":{"nodes":[%s]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[%s]}}}}]}}}}}\n' \
    "${1:-}" "${2:-}" "${3:-}" > "$FAKE_GH/graphql.json"
}
by() { printf '{"author":{"login":"%s"}}' "$1"; }
status() { printf '{"__typename":"StatusContext","context":"%s","creator":{"login":"%s"}}' "$1" "$2"; }
check() { printf '{"__typename":"CheckRun","name":"%s","checkSuite":{"app":{"slug":"%s"}}}' "$1" "$2"; }

t_rv_bugbot_by_check() {
  # Given: Cursor Bugbot's check run and a review by a person
  fake_gh; pr_node "$(by alice)" "" "$(check "Cursor Bugbot" cursor)"
  # When
  reviewers acme/app 7
  # Then
  eq exit 0 "$code"
  eq stdout "bugbot" "$out"
}

t_rv_table_order() {
  # Given: a CodeRabbit comment and a Devin review
  fake_gh; pr_node "$(by devin-ai-integration)" "$(by "coderabbitai[bot]")"
  # When
  reviewers acme/app 7
  # Then
  eq stdout "$(printf 'devin\ncoderabbit')" "$out"
}

t_rv_by_status_creator() {
  fake_gh; pr_node "" "" "$(status "Greptile Review" greptile-apps)"
  reviewers acme/app 7
  eq stdout "greptile" "$out"
}

t_rv_none() {
  # Given: a CI check and a review by a person
  fake_gh; pr_node "$(by alice)" "" "$(check test github-actions)"
  # When
  reviewers acme/app 7
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_rv_asks_for_the_pr() {
  fake_gh; pr_node
  reviewers acme/app 7
  has "graphql owner" "o=acme" "$(cat "$FAKE_GH/graphql.args")"
  has "graphql repo" "r=app" "$(cat "$FAKE_GH/graphql.args")"
  has "graphql number" "n=7" "$(cat "$FAKE_GH/graphql.args")"
}

t_rv_gh_fails() {
  # Given: gh cannot find the repo
  fake_gh; printf 'gh: Could not resolve to a Repository\n' > "$FAKE_GH/graphql.fail"
  # When
  reviewers acme/app 7
  # Then
  eq exit 1 "$code"
  eq stderr "stop: gh failed: gh: Could not resolve to a Repository" "$err"
}

t_rv_bad_args() {
  fake_gh
  reviewers app 7
  eq exit 64 "$code"
  eq stderr "stop: app is not owner/repo" "$err"
  reviewers acme/app x
  eq exit 64 "$code"
  eq stderr "stop: x is not a PR number" "$err"
}

cases=(
  "reviewers finds bugbot by its check app|t_rv_bugbot_by_check"
  "reviewers lists each bot in table order|t_rv_table_order"
  "reviewers finds a bot by its status creator|t_rv_by_status_creator"
  "reviewers prints nothing when no bot is seen|t_rv_none"
  "reviewers asks gh for that one PR|t_rv_asks_for_the_pr"
  "reviewers stops when gh fails|t_rv_gh_fails"
  "reviewers stops on a bad repo or number|t_rv_bad_args"
)
