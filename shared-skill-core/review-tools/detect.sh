#!/usr/bin/env bash
# detect.sh: which review tools a repo uses, read off its recent PRs.
#
#   detect.sh <owner/repo> [--prs 10]
#
# No file in a repo says which review tools review its PRs; the tools are
# GitHub apps, and the list of apps on a repo needs an app token. Each tool
# leaves marks on the PRs it reviews, so this reads the last --prs PRs, open,
# merged, or closed, in one GraphQL call. A tool from known.tsv is seen on a
# PR when any of these is its login: a review's author, a comment's author, a
# commit status's creator, or a check run's app on the PR's last commit; or
# when its status name is a commit status or check run there.
#
# Prints `PRS=<n>`, the PRs read, then one line per tool seen, in known.tsv
# order: `<tool> <seen>/<n>`, the PRs it was seen on. A repo with no PRs, or
# none a known tool touched, prints only the first line: no PRs means nothing
# is known yet, not that no tool is installed. Exit 0.
# A gh call that fails is `stop: gh failed: <its last line>` on stderr,
# exit 1. A bad flag or argument is `stop: …` on stderr, exit 64.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo=""; prs=10
while [ $# -gt 0 ]; do
  case "$1" in
    --prs) prs="${2:-}"; shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 64 ;;
    *) if [ -z "$repo" ]; then repo="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 64; fi; shift ;;
  esac
done
[ -n "$repo" ] || { echo 'usage: detect.sh <owner/repo> [--prs N]' >&2; exit 64; }
case "$repo" in */*) ;; *) printf 'stop: %s is not owner/repo\n' "$repo" >&2; exit 64 ;; esac
case "$prs" in ''|*[!0-9]*|0) printf 'stop: --prs takes a number from 1 to 100\n' >&2; exit 64 ;; esac
[ "$prs" -le 100 ] || { printf 'stop: --prs takes a number from 1 to 100\n' >&2; exit 64; }

known="$(grep -v '^#' "$here/known.tsv" | jq -R -s -c '
  [split("\n")[] | select(length > 0) | split("\t") | {tool: .[0], login: .[1], status: .[2]}]')"

# shellcheck disable=SC2016 # the $ names are GraphQL variables
q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequests(first:$n,orderBy:{field:CREATED_AT,direction:DESC}){nodes{reviews(first:100){nodes{author{login}}}comments(first:100){nodes{author{login}}}commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{__typename ... on StatusContext{context creator{login}}... on CheckRun{name checkSuite{app{slug}}}}}}}}}}}}}'
errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
if ! out="$(gh api graphql -f query="$q" -F o="${repo%%/*}" -F r="${repo##*/}" -F n="$prs" 2>"$errf")"; then
  printf 'stop: gh failed: %s\n' "$(tail -1 "$errf")" >&2; exit 1
fi

jq -r --argjson known "$known" '
  def bare: sub("\\[bot\\]$"; "");
  [.data.repository.pullRequests.nodes[]
    | ([.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?]) as $ctx
    | {logins: ([.reviews.nodes[].author.login?, .comments.nodes[].author.login?,
                 ($ctx[] | .creator.login?, .checkSuite.app.slug?)]
                | map(select(. != null) | bare)),
       names: [$ctx[] | .context // .name]}] as $prs
  | "PRS=\($prs | length)",
    ($known[] as $t
      | [$prs[] | select((.logins | index($t.login)) or ($t.status != "-" and (.names | index($t.status))))]
      | length | select(. > 0) | "\($t.tool) \(.)/\($prs | length)")
' <<<"$out"
