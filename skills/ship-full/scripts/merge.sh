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
#   stop: #<n> is <state>, not open
#   stop: head moved to <sha7>; ready it again
#   stop: merge refused: <gh's last line>
#   stop: #<n> is still open after the merge; a merge queue or a rule holds it
set -euo pipefail

usage='usage: merge.sh <owner/repo> <number> --sha <sha>'
[ $# -eq 4 ] && [ "$3" = --sha ] || { echo "$usage" >&2; exit 64; }
repo="$1"; number="$2"; sha="$4"

die() { printf 'stop: %s\n' "$1" >&2; exit 1; }

# view: the PR's url, state, head, and merge commit, one per line.
view() {
  local json
  json="$(gh pr view "$number" --repo "$repo" --json url,state,headRefOid,mergeCommit 2>&1)" \
    || die "gh failed: $(printf '%s\n' "$json" | tail -1)"
  jq -r '.url, .state, .headRefOid, (.mergeCommit.oid // "")' <<<"$json"
}

{ read -r url; read -r state; read -r head; read -r merged; } < <(view)
if [ "$state" = MERGED ]; then
  printf 'MERGED %s already %s\n' "$url" "${merged:0:7}"; exit 0
fi
[ "$state" = OPEN ] || die "#$number is $state, not open"
[ "$head" = "$sha" ] || die "head moved to ${head:0:7}; ready it again"

allowed="$(gh api "repos/$repo" 2>&1)" || die "gh failed: $(printf '%s\n' "$allowed" | tail -1)"
method="$(jq -r 'if .allow_merge_commit then "merge" elif .allow_squash_merge then "squash" elif .allow_rebase_merge then "rebase" else "" end' <<<"$allowed")"
[ -n "$method" ] || die "repos/$repo allows no merge method"

if ! err="$(gh pr merge "$number" --repo "$repo" "--$method" --match-head-commit "$sha" 2>&1)"; then
  die "merge refused: $(printf '%s\n' "$err" | tail -1)"
fi

{ read -r url; read -r state; read -r _; read -r merged; } < <(view)
[ "$state" = MERGED ] || die "#$number is still open after the merge; a merge queue or a rule holds it"
printf 'MERGED %s %s %s\n' "$url" "$method" "${merged:0:7}"
