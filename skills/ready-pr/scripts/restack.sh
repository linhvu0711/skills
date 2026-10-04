#!/usr/bin/env bash
# restack.sh: the open PRs stacked on a branch, before a force push of it.
#
#   restack.sh list <owner/repo> <branch>
#
# list: every open PR whose base is <branch>, then the PRs on each of their
# heads, depth first, a parent before its children and siblings by number. A
# fork PR's head is not walked, and a head already listed is not walked again.
# Prints `STACK=<n>` first, then one line per PR:
#   <number> <base> <head> <url> fork=<true|false>
set -euo pipefail

usage='usage: restack.sh list <owner/repo> <branch>'

# children <branch>: the open PRs on <branch>, one line each, by number.
children() {
  local json
  json="$(gh pr list --repo "$repo" --base "$1" --state open --limit 100 \
    --json number,baseRefName,headRefName,url,isCrossRepository 2>&1)" \
    || { printf 'stop: %s\n' "$json" >&2; exit 1; }
  jq -r 'sort_by(.number)[] | "\(.number) \(.baseRefName) \(.headRefName) \(.url) fork=\(.isCrossRepository)"' <<<"$json"
}

# walk <branch>: add the PRs on <branch>, and theirs, to `stack`.
walk() {
  local kids line head fork
  kids="$(children "$1")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    read -r _ _ head _ fork <<<"$line"
    case "$seen" in *" $head "*) continue ;; esac
    seen="$seen$head "; stack+=("$line")
    [ "$fork" = "fork=true" ] || walk "$head"
  done <<<"$kids"
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  list)
    [ $# -eq 2 ] || { echo "$usage" >&2; exit 64; }
    repo="$1"; seen=" $2 "; stack=()
    walk "$2"
    printf 'STACK=%s\n' "${#stack[@]}"
    [ "${#stack[@]}" -eq 0 ] || printf '%s\n' "${stack[@]}"
    ;;
  *) echo "$usage" >&2; exit 64 ;;
esac
