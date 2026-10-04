#!/usr/bin/env bash
# restack.sh: keep the PRs stacked on a branch on its tip across a force push.
#
#   restack.sh list <owner/repo> <branch>                       before the push
#   restack.sh move <checkout> <branch> <old-sha> <stack-file>  after it
#
# list: every open PR whose base is <branch>, then the PRs on each of their
# heads, depth first, a parent before its children and siblings by number. A
# fork PR's head is not walked, and a head already listed is not walked again.
# More than 100 open PRs on one branch is a stop, not a short list.
# Prints `STACK=<n>` first, then one line per PR:
#   <number> <base> <head> <url> fork=<true|false>
#
# move: <stack-file> holds what list printed; <old-sha> is <branch>'s tip
# before the push. Each PR, in order, is rebased in a temp worktree of
# origin/<head> onto origin/<base>, dropping the commits its base had before
# (`--onto`, from the merge base with the base's old tip), and pushed with
# `--force-with-lease` against its own old tip. A local branch of that name
# follows: `branch -f`, or `reset --keep` in the clean worktree that holds it.
# One line per PR: `MOVED <url> <old>..<new>`, or the stop and its reason:
#   SKIP <url>: fork PR, not mine
#   SKIP <url>: <head> has <n> commit(s) not on origin
#   SKIP <url>: worktree <path> has uncommitted changes
#   SKIP <url>: <head> has merge commits; move it by hand
#   CLASH <url>: <files>              (the rebase is aborted)
#   SKIP <url>: push refused: <git's last line>
# then `LEFT <url>` for each PR after a stop. Last line `RESTACK=moved <n>`
# (exit 0) or `RESTACK=stopped` (exit 1). Nothing after a stop is pushed.
set -euo pipefail

usage='usage: restack.sh list <owner/repo> <branch> | move <checkout> <branch> <old-sha> <stack-file>'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
checkout="$here/../../../shared-skill-core/checkout.sh"

# children <branch>: the open PRs on <branch>, one line each, by number.
children() {
  local json
  json="$(gh pr list --repo "$repo" --base "$1" --state open --limit 101 \
    --json number,baseRefName,headRefName,url,isCrossRepository 2>&1)" \
    || { printf 'stop: %s\n' "$json" >&2; exit 1; }
  [ "$(jq length <<<"$json")" -le 100 ] \
    || { printf 'stop: more than 100 open PRs on %s; restack lists at most 100\n' "$1" >&2; exit 1; }
  jq -r 'sort_by(.number)[] | "\(.number) \(.baseRefName) \(.headRefName) \(.url) fork=\(.isCrossRepository)"' <<<"$json"
}

# walk <branch>: add the PRs on <branch>, and theirs, to `stack`.
walk() {
  local kids line head fork
  kids="$(children "$1")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    read -r _ _ head _ fork <<<"$line"
    # A fork's head names a branch in another repo, so it marks nothing seen.
    [ "$fork" = "fork=false" ] || { stack+=("$line"); continue; }
    case "$seen" in *" $head "*) continue ;; esac
    seen="$seen$head "; stack+=("$line")
    walk "$head"
  done <<<"$kids"
}

g() { git -C "$wt" "$@"; }

# old_of <branch>: its tip before this run moved it.
old_of() {
  local i
  for i in "${!olds_b[@]}"; do
    [ "${olds_b[$i]}" = "$1" ] && { printf '%s' "${olds_s[$i]}"; return 0; }
  done
  return 1
}

# holder <branch>: the worktree that has <branch> checked out, if any, as the
# checkout resolver lists them.
holder() {
  local listed b w
  listed="$(bash "$checkout" worktrees "$wt")"
  while read -r b _ _ w; do
    if [ "$b" = "BRANCH=$1" ]; then printf '%s' "${w#WORKTREE=}"; return 0; fi
  done <<<"$listed"
}

drop_tmp() { g worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true; }

# move_one: move the PR in base, head, url, fork. Sets `result`; 1 is a stop.
move_one() {
  local parent_old child_old n hold up files new err
  [ "$fork" = "fork=false" ] || { result="SKIP $url: fork PR, not mine"; return 1; }
  parent_old="$(old_of "$base")" || { result="SKIP $url: $base was not moved"; return 1; }
  g fetch -q origin "$base" "$head" 2>/dev/null || { result="SKIP $url: cannot fetch $head"; return 1; }
  child_old="$(g rev-parse "origin/$head")"
  if g show-ref -q --verify "refs/heads/$head"; then
    n="$(g rev-list --count "origin/$head..$head")"
    [ "$n" -eq 0 ] || { result="SKIP $url: $head has $n commit(s) not on origin"; return 1; }
  fi
  hold="$(holder "$head")"
  if [ -n "$hold" ] && [ -n "$(git -C "$hold" status --porcelain)" ]; then
    result="SKIP $url: worktree $hold has uncommitted changes"; return 1
  fi
  g worktree add -q --detach "$tmp/wt" "origin/$head" 2>/dev/null || { result="SKIP $url: cannot check out $head"; return 1; }
  up="$(git -C "$tmp/wt" merge-base "$parent_old" HEAD)" || { drop_tmp; result="SKIP $url: no commit in common with $base"; return 1; }
  # A rebase drops merge commits, and with them any resolution made there.
  if [ "$(git -C "$tmp/wt" rev-list --merges --count "$up..HEAD")" -gt 0 ]; then
    drop_tmp; result="SKIP $url: $head has merge commits; move it by hand"; return 1
  fi
  if ! git -C "$tmp/wt" rebase -q --onto "origin/$base" "$up" >/dev/null 2>&1; then
    files="$(git -C "$tmp/wt" diff --name-only --diff-filter=U | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    git -C "$tmp/wt" rebase --abort; drop_tmp
    result="CLASH $url: $files"; return 1
  fi
  new="$(git -C "$tmp/wt" rev-parse HEAD)"
  if ! err="$(git -C "$tmp/wt" push -q --force-with-lease="refs/heads/$head:$child_old" origin "HEAD:refs/heads/$head" 2>&1)"; then
    drop_tmp; result="SKIP $url: push refused: $(printf '%s\n' "$err" | tail -1)"; return 1
  fi
  drop_tmp
  if [ -n "$hold" ]; then git -C "$hold" reset -q --keep "$new"
  elif g show-ref -q --verify "refs/heads/$head"; then g branch -f "$head" "$new" >/dev/null
  fi
  olds_b+=("$head"); olds_s+=("$child_old")
  result="MOVED $url ${child_old:0:7}..${new:0:7}"
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
  move)
    [ $# -eq 4 ] || { echo "$usage" >&2; exit 64; }
    wt="$1"; olds_b=("$2"); olds_s=("$3")
    [ -f "$4" ] || { printf 'stop: no stack file %s\n' "$4" >&2; exit 1; }
    lines=(); while IFS= read -r l; do lines+=("$l"); done < "$4"
    tmp="$(mktemp -d)"; trap 'drop_tmp; rm -rf "$tmp"' EXIT
    moved=0; stopped=0
    for line in ${lines[@]+"${lines[@]}"}; do
      case "$line" in ''|STACK=*) continue ;; esac
      read -r _ base head url fork <<<"$line"
      if [ "$stopped" -eq 1 ]; then printf 'LEFT %s\n' "$url"; continue; fi
      if move_one; then moved=$((moved + 1)); else stopped=1; fi
      printf '%s\n' "$result"
    done
    [ "$stopped" -eq 0 ] || { echo 'RESTACK=stopped'; exit 1; }
    printf 'RESTACK=moved %s\n' "$moved"
    ;;
  *) echo "$usage" >&2; exit 64 ;;
esac
