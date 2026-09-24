#!/usr/bin/env bash
# open-threads.sh: the review threads on a PR that still wait for the author.
#
#   open-threads.sh <owner/repo> <number> [--me <login>]
#
# A thread is open when it is not resolved and its last comment is not by
# --me (default: the login `gh api user` prints). Devin resolves a thread
# itself once a push fixes it, with a `✅ Resolved` reply, so those are
# never listed. Prints `OPEN=<n>` first, then one line per open thread:
#   <thread node id> <path>:<line> last=<login> :: <first comment, 120 chars>
set -euo pipefail

repo=""; num=""; me=""
while [ $# -gt 0 ]; do
  case "$1" in
    --me) me="${2:-}"; shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 1 ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$num" ]; then num="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 1; fi; shift ;;
  esac
done
[ -n "$repo" ] && [ -n "$num" ] || { echo 'usage: open-threads.sh <owner/repo> <number> [--me <login>]' >&2; exit 64; }
[ -n "$me" ] || me="$(gh api user -q .login)"
owner="${repo%%/*}"; name="${repo##*/}"

q='query($o:String!,$r:String!,$n:Int!,$after:String){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100,after:$after){pageInfo{hasNextPage endCursor}nodes{id isResolved path line comments(first:50){nodes{author{login}body}}}}}}}'

all='[]'; after=""
while :; do
  page="$(gh api graphql -f query="$q" -F o="$owner" -F r="$name" -F n="$num" ${after:+-F after="$after"} -q '.data.repository.pullRequest.reviewThreads')"
  all="$(jq -c --argjson p "$page" '. + $p.nodes' <<<"$all")"
  [ "$(jq -r '.pageInfo.hasNextPage' <<<"$page")" = "true" ] || break
  after="$(jq -r '.pageInfo.endCursor' <<<"$page")"
done

jq -r --arg me "$me" '
  [ .[] | select(.isResolved | not)
        | select((.comments.nodes | last | .author.login) != $me)
        | select((.comments.nodes | last | .body) | test("^\\s*✅ \\*\\*Resolved\\*\\*") | not) ]
  | "OPEN=\(length)",
    (.[] | "\(.id) \(.path):\(.line // "-") last=\(.comments.nodes | last | .author.login) :: \(.comments.nodes | first | .body | gsub("<!--[^>]*-->"; "") | gsub("\\s+"; " ") | .[:120])")
' <<<"$all"
