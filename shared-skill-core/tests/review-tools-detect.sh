# review-tools-detect.sh: the cases for the shared core's review-tools/detect.sh,
# driven through the fake gh. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# detect <args...>: run detect.sh on the fake gh, in a fresh temp folder T.
detect() { run bash "$here/../review-tools/detect.sh" "$@"; }
dt_setup() { T="$(cd "$(mktemp -d)" && pwd -P)"; fake_gh; }

# prs <pr json>...: the graphql answer, one pullRequests node per argument.
prs() { local IFS=,; printf '{"data":{"repository":{"pullRequests":{"nodes":[%s]}}}}\n' "$*" > "$FAKE_GH/graphql.json"; }

# pr [reviews] [comments] [contexts]: one node, each part a JSON array body.
pr() {
  printf '{"reviews":{"nodes":[%s]},"comments":{"nodes":[%s]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[%s]}}}}]}}' "${1:-}" "${2:-}" "${3:-}"
}
by() { printf '{"author":{"login":"%s"}}' "$1"; }
status() { printf '{"__typename":"StatusContext","context":"%s","creator":null}' "$1"; }
check() { printf '{"__typename":"CheckRun","name":"%s","checkSuite":{"app":{"slug":"%s"}}}' "$1" "$2"; }

t_dt_devin_by_status_or_review() {
  dt_setup
  prs "$(pr "" "" "$(status "Devin Review")")" "$(pr "$(by devin-ai-integration)")"
  detect acme/app
  eq exit 0 "$code"
  eq stdout "$(printf 'PRS=2\ndevin 2/2')" "$out"
}

t_dt_tools_in_table_order() {
  dt_setup
  prs "$(pr "" "" "$(check "Macroscope - Approvability Check" macroscopeapp)")" \
      "$(pr "" "$(by macroscopeapp)" "$(status CodeRabbit)")" \
      "$(pr "$(by alice)")"
  detect acme/app
  eq exit 0 "$code"
  eq stdout "$(printf 'PRS=3\ncoderabbit 1/3\nmacroscope 2/3')" "$out"
}

t_dt_bot_suffix() {
  dt_setup
  prs "$(pr "" "$(by "coderabbitai[bot]")")"
  detect acme/app
  eq stdout "$(printf 'PRS=1\ncoderabbit 1/1')" "$out"
}

t_dt_no_tool() {
  dt_setup
  prs "$(pr "$(by alice)" "" "$(check test github-actions)")"
  detect acme/app
  eq exit 0 "$code"
  eq stdout "PRS=1" "$out"
}

t_dt_no_prs() {
  dt_setup
  prs
  detect acme/app
  eq exit 0 "$code"
  eq stdout "PRS=0" "$out"
}

t_dt_prs_flag() {
  dt_setup
  prs
  detect acme/app --prs 5
  eq exit 0 "$code"
  has "graphql args" "n=5" "$(cat "$FAKE_GH/graphql.args")"
  has "graphql owner" "o=acme" "$(cat "$FAKE_GH/graphql.args")"
}

t_dt_gh_fails() {
  dt_setup
  printf 'gh: Could not resolve to a Repository\n' > "$FAKE_GH/graphql.fail"
  detect acme/app
  eq exit 1 "$code"
  eq stderr "stop: gh failed: gh: Could not resolve to a Repository" "$err"
}

t_dt_bad_args() {
  dt_setup
  detect app
  eq exit 64 "$code"
  eq stderr "stop: app is not owner/repo" "$err"
  detect acme/app --prs 0
  eq exit 64 "$code"
  detect acme/app --prs 101
  eq exit 64 "$code"
}

cases=(
  "detect finds devin by its status or its review|t_dt_devin_by_status_or_review"
  "detect counts each tool and prints them in table order|t_dt_tools_in_table_order"
  "detect matches a login with a [bot] suffix|t_dt_bot_suffix"
  "detect prints only the PR count when no tool is seen|t_dt_no_tool"
  "detect prints PRS=0 for a repo with no PRs|t_dt_no_prs"
  "detect passes --prs and the repo to gh|t_dt_prs_flag"
  "detect stops when gh fails|t_dt_gh_fails"
  "detect stops on a bad repo or --prs|t_dt_bad_args"
)
