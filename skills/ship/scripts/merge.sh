#!/usr/bin/env bash
# merge.sh: merge one ready PR at the head its ready step checked.
#
#   merge.sh <owner/repo> <number> --sha <sha>
#
# The method is the first one the repo allows of a merge commit, squash, and
# rebase: a merge commit keeps one commit per slice, and the PR stacked above
# needs no rebase. `--match-head-commit` makes GitHub refuse the merge when the
# head moved after the check. Never `--admin`, `--auto`, or `--delete-branch`:
# the repo's rules stay in force, and the remote branch is the repo's setting.
#
# Prints `MERGED <url> <merge|squash|rebase> <sha7>`, the merge commit, or
# `MERGED <url> already <sha7>` when it was merged before (exit 0). Each stop
# is one `stop:` line on stderr, exit 1:
#   stop: --sha needs the full 40-character head SHA, got: <sha>
#   stop: #<n> is <state>, not open
#   stop: head moved to <sha7>; ready it again
#   stop: merge refused: <gh's last line>
#   stop: #<n> is still open after the merge; a merge queue or a rule holds it
# A wrong command line prints the usage on stderr, exit 64.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$here/../../../shared/die.sh"
usage='usage: merge.sh <owner/repo> <number> --sha <sha>'
[ $# -eq 4 ] && [ "$3" = --sha ] || die_usage "$usage"
repo="$1"; number="$2"; sha="$4"

# A short SHA never equals GitHub's headRefOid, so it would read as a moved head.
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "--sha needs the full 40-character head SHA, got: $sha"

. "$here/../../../shared/gh.sh"

# view: the PR's url, state, head, and merge commit, one per line.
view() {
  gh_or_stop pr view "$number" --repo "$repo" --json url,state,headRefOid,mergeCommit
  jq -r '.url, .state, .headRefOid, (.mergeCommit.oid // "")' <<<"$out"
}

{ read -r url; read -r state; read -r head; read -r merged; } < <(view)
if [ "$state" = MERGED ]; then
  printf 'MERGED %s already %s\n' "$url" "${merged:0:7}"; exit 0
fi
[ "$state" = OPEN ] || die "#$number is $state, not open"
[ "$head" = "$sha" ] || die "head moved to ${head:0:7}; ready it again"

gh_or_stop api "repos/$repo"
method="$(jq -r 'if .allow_merge_commit then "merge" elif .allow_squash_merge then "squash" elif .allow_rebase_merge then "rebase" else "" end' <<<"$out")"
[ -n "$method" ] || die "repos/$repo allows no merge method"

gh_out pr merge "$number" --repo "$repo" "--$method" --match-head-commit "$sha" || die "merge refused: $err"

{ read -r url; read -r state; read -r _; read -r merged; } < <(view)
[ "$state" = MERGED ] || die "#$number is still open after the merge; a merge queue or a rule holds it"
printf 'MERGED %s %s %s\n' "$url" "$method" "${merged:0:7}"
