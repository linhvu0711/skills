#!/usr/bin/env bash
# reviewers.sh: the review bots seen on one PR.
#
#   reviewers.sh <owner/repo> <number>
#
# Two skills ask it. ship asks after the first wait on the PR it opened, to
# choose whether review-pr runs there. Waiting needs no bot names: ready-pr
# waits for every check. Only this choice does, since a deploy bot comments
# and posts checks too. set-review-rules asks it on a repo's recent PRs, to
# find the bots to point at REVIEW.md. A bot from reviewers.tsv is seen when any of these is its login: a
# review's author, a comment's author, a commit status's creator, or a check
# run's app on the PR's last commit. A bot not in the table is not seen, so
# review-pr runs: one review too many, never one too few.
#
# Prints one line per bot seen, its tool name, in reviewers.tsv order, and
# nothing when none is seen. Exit 0.
# A gh call that fails is `stop: gh failed: <its last line>` on stderr,
# exit 1. A bad argument is `stop: …` on stderr, exit 64.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ $# -eq 2 ] || { echo 'usage: reviewers.sh <owner/repo> <number>' >&2; exit 64; }
repo="$1"; num="$2"
case "$repo" in */*) ;; *) printf 'stop: %s is not owner/repo\n' "$repo" >&2; exit 64 ;; esac
case "$num" in ''|*[!0-9]*) printf 'stop: %s is not a PR number\n' "$num" >&2; exit 64 ;; esac

known="$(grep -v '^#' "$here/reviewers.tsv" | jq -R -s -c '
  [split("\n")[] | select(length > 0) | split("\t") | {tool: .[0], login: .[1]}]')"

# shellcheck disable=SC2016 # the $ names are GraphQL variables
q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviews(first:100){nodes{author{login}}}comments(first:100){nodes{author{login}}}commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{__typename ... on StatusContext{creator{login}}... on CheckRun{checkSuite{app{slug}}}}}}}}}}}}'
errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
if ! out="$(gh api graphql -f query="$q" -F o="${repo%%/*}" -F r="${repo##*/}" -F n="$num" 2>"$errf")"; then
  printf 'stop: gh failed: %s\n' "$(tail -1 "$errf")" >&2; exit 1
fi

jq -r --argjson known "$known" '
  def bare: sub("\\[bot\\]$"; "");
  .data.repository.pullRequest
  | ([.reviews.nodes[].author.login?, .comments.nodes[].author.login?,
      (.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]? | .creator.login?, .checkSuite.app.slug?)]
     | map(select(. != null) | bare)) as $logins
  | $known[] | select(.login as $l | $logins | index($l)) | .tool
' <<<"$out"
