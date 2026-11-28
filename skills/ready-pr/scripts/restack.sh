#!/usr/bin/env bash
# restack.sh: keep the PRs stacked on a branch on its tip across a force push.
#
#   restack.sh list <owner/repo> <branch>                       before the push
#   restack.sh move <checkout> <branch> <old-sha> <stack-file> [--own <n>[,<n>...]]
#                                                               after it
#
# list: every open PR whose base is <branch>, then the PRs on each of their
# heads, depth first, a parent before its children and siblings by number. A
# fork PR's head is not walked, and a head already listed is not walked again.
# More than 100 open PRs on one branch is a stop, not a short list.
# Prints `STACK=<n>` first, then one line per PR:
#   <number> <base> <head> <url> fork=<true|false>
#
# move: <stack-file> holds what list printed; <old-sha> is <branch>'s tip
# before the push. Each PR, in order, is rebased in its own temp worktree of
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
# A temp worktree git cannot remove prints `WARN <path>: <git's last line>` on
# stderr, and the move goes on.
# --own: the numbers of the PRs the caller owns. Each other PR, and each PR
# stacked on a left one, prints `LEFT <url>` and is not pushed; the move goes
# on with the next PR, and this is no stop. Without it, every PR is owned.
# A wrong command line prints the usage on stderr, exit 64.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$here/../../../shared/die.sh"

usage='usage: restack.sh list <owner/repo> <branch> | move <checkout> <branch> <old-sha> <stack-file> [--own <n>[,<n>...]]'
checkout="$here/../../../shared/checkout.sh"
. "$here/../../../shared/gh.sh"

# children <branch>: the open PRs on <branch>, one line each, by number.
children() {
  local json
  gh_or_stop pr list --repo "$repo" --base "$1" --state open --limit 101 \
    --json number,baseRefName,headRefName,url,isCrossRepository
  json="$out"
  [ "$(jq length <<<"$json")" -le 100 ] \
    || die "more than 100 open PRs on $1; restack lists at most 100"
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

# drop_tmp: remove the current PR's temp worktree, `pwt`, if one is held.
drop_tmp() {
  local err
  [ -n "$pwt" ] || return 0
  if ! err="$(g worktree remove --force "$pwt" 2>&1)"; then
    printf 'WARN %s: %s\n' "$pwt" "$(printf '%s\n' "$err" | tail -1)" >&2
  fi
  pwt=""
}

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
  hold="$(bash "$checkout" holder "$wt" "$head")"
  if [ -n "$hold" ] && [ -n "$(git -C "$hold" status --porcelain)" ]; then
    result="SKIP $url: worktree $hold has uncommitted changes"; return 1
  fi
  pwt=""
  g worktree add -q --detach "$tmp/wt-$num" "origin/$head" 2>/dev/null || { result="SKIP $url: cannot check out $head"; return 1; }
  pwt="$tmp/wt-$num"
  up="$(git -C "$pwt" merge-base "$parent_old" HEAD)" || { drop_tmp; result="SKIP $url: no commit in common with $base"; return 1; }
  # A rebase drops merge commits, and with them any resolution made there.
  if [ "$(git -C "$pwt" rev-list --merges --count "$up..HEAD")" -gt 0 ]; then
    drop_tmp; result="SKIP $url: $head has merge commits; move it by hand"; return 1
  fi
  if ! git -C "$pwt" rebase -q --onto "origin/$base" "$up" >/dev/null 2>&1; then
    files="$(git -C "$pwt" diff --name-only --diff-filter=U | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    git -C "$pwt" rebase --abort; drop_tmp
    result="CLASH $url: $files"; return 1
  fi
  new="$(git -C "$pwt" rev-parse HEAD)"
  if ! err="$(git -C "$pwt" push -q --force-with-lease="refs/heads/$head:$child_old" origin "HEAD:refs/heads/$head" 2>&1)"; then
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
    [ $# -eq 2 ] || die_usage "$usage"
    repo="$1"; seen=" $2 "; stack=()
    walk "$2"
    printf 'STACK=%s\n' "${#stack[@]}"
    [ "${#stack[@]}" -eq 0 ] || printf '%s\n' "${stack[@]}"
    ;;
  move)
    own=""
    if [ $# -eq 6 ] && [ "$5" = --own ]; then own=",$6,"
    elif [ $# -ne 4 ]; then die_usage "$usage"
    fi
    wt="$1"; olds_b=("$2"); olds_s=("$3"); left=" "
    [ -f "$4" ] || die "no stack file $4"
    lines=(); while IFS= read -r l; do lines+=("$l"); done < "$4"
    # rmdir, not rm -rf: a worktree git could not remove stays where its WARN points.
    tmp="$(mktemp -d)"; pwt=""; trap 'drop_tmp; rmdir "$tmp" 2>/dev/null || true' EXIT
    moved=0; stopped=0
    for line in ${lines[@]+"${lines[@]}"}; do
      case "$line" in ''|STACK=*) continue ;; esac
      read -r num base head url fork <<<"$line"
      if [ "$stopped" -eq 1 ]; then printf 'LEFT %s\n' "$url"; continue; fi
      mine=1
      case "$left" in *" $base "*) mine=0 ;; esac
      if [ -n "$own" ]; then case "$own" in *",$num,"*) ;; *) mine=0 ;; esac; fi
      if [ "$mine" -eq 0 ]; then
        # A fork's head names a branch in another repo, as in walk.
        [ "$fork" != "fork=false" ] || left="$left$head "
        printf 'LEFT %s\n' "$url"; continue
      fi
      if move_one; then moved=$((moved + 1)); else stopped=1; fi
      printf '%s\n' "$result"
    done
    [ "$stopped" -eq 0 ] || { echo 'RESTACK=stopped'; exit 1; }
    printf 'RESTACK=moved %s\n' "$moved"
    ;;
  *) die_usage "$usage" ;;
esac
