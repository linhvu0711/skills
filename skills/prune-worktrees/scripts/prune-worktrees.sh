#!/usr/bin/env bash
# prune-worktrees.sh: remove the worktrees that are safe to prune, with their
# branches, and list every other worktree with the reason it stays.
#
#   prune-worktrees.sh [all]
#   prune-worktrees.sh [all] --remove <path> [--remove <path>]...
#
# It reads every worktree of the repo the current folder is in, wherever the
# worktree is on disk. `all` adds every repo that has a worktree under
# ${WORKTREES_ROOT:-$HOME/development/worktrees}, in <owner>/<repo>/<branch>
# or the older <repo>/<branch>. The main checkout is never touched and never
# printed. Every worktree is judged first, then the
# safe ones are removed.
#
# --remove: only the worktrees the user named, each removed with --force
# whatever its reason, unless the session is in it or it is locked. Its branch
# goes by the same rule as below; a branch git will not take with -d stays.
#
# Safe to prune: a clean worktree whose PR is merged on GitHub with the branch
# tip as its last commit; the branch goes with `git branch -D`. Or, with no
# PR, a clean worktree whose branch tip is in the default branch; the branch
# goes with `git branch -d`. A repo with no GitHub remote gets only the second
# test, and no gh call.
#
# Prints, in this order:
#   kept <path>: <reason>            one per worktree that stays. The reasons:
#     `this session is in it`, `locked`, `detached HEAD`,
#     `<n> uncommitted files`, `PR #<n> open`, `PR #<n> closed, not merged`,
#     `PR #<n> merged, tip is not its last commit`,
#     `<n> commits not on GitHub` (a branch with no PR), `no PR`,
#     `not in <default>` (a repo with no GitHub remote),
#     `its repo is gone` (all: a folder under the root whose repo is deleted)
#   cleared <n> stale entries        when folders were gone
#   removed <path>, branch <b> deleted (-D|-d)
#   removed <path>, branch <b> kept: git branch -d refused
#                                    one of these per worktree removed
#   nothing to prune                 when nothing was cleared or removed
# A path under $HOME is printed with ~.
# Exit 1: `stop: <why>` on stderr, and nothing was removed.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
# The .git directory a checkout or worktree belongs to, symlinks resolved.
common_dir() {
  local d
  d="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$d" ] || return 1
  (cd "$d" && pwd -P)
}
# show <path>: the path, with $HOME written as ~.
show() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# github_repo <main>: owner/name when origin is on GitHub, else nothing. The
# raw config value, so an insteadOf rewrite never hides it.
github_repo() {
  local url
  url="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 0
  case "$url" in
    *github.com[:/]*) printf '%s' "$url" | sed -E 's#\.git$##; s#/$##; s#.*github\.com[:/]##' ;;
  esac
}

# pr_of <owner/repo> <branch>: `<number> <STATE> <headRefOid>` of the
# branch's newest PR, or nothing when it has none. gh fails: the stop line on
# stderr, and return 1.
pr_of() {
  local out err
  err="$(mktemp)"
  if out="$(gh pr list -R "$1" --head "$2" --state all --limit 1 \
      --json number,state,headRefOid --jq '.[] | "\(.number) \(.state) \(.headRefOid)"' 2>"$err")"; then
    rm -f "$err"; printf '%s' "$out"; return 0
  fi
  printf 'stop: gh failed: %s\n' "$(head -1 "$err")" >&2; rm -f "$err"; return 1
}

# default_ref <main>: the default branch to test a tip against: origin/HEAD,
# else the first of main and master that exists. No fetch; local refs only.
default_ref() {
  local b
  if b="$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s' "$b"; return
  fi
  for b in main master; do
    git -C "$1" show-ref --verify --quiet "refs/heads/$b" && { printf '%s' "$b"; return; }
  done
}

# Fields of a record. Not a tab: read collapses empty tab-split fields.
sep=$'\x1f'
kept=()       # <path> SEP <reason>
removals=()   # <main> SEP <path> SEP <branch> SEP <flag> SEP <--force or empty>
stale=()      # <main> SEP <entries whose folder is gone>

# plural <n> <one> <many>: `<n> <one>` or `<n> <many>`.
plural() { if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }

# judge <main> <owner/repo> <path> <branch> <locked>: sets `flag` to the
# branch flag (-D or -d) when the worktree is safe to prune, else `reason` to
# why it stays. The first reason that holds is the one given.
judge() {
  local main="$1" slug="$2" path="$3" branch="$4" locked="$5" tip n ref pr="" num="" state="" oid=""
  flag="" reason=""
  if [ "$(cd "$path" 2>/dev/null && pwd -P)" = "$session" ]; then reason="this session is in it"; return; fi
  [ "$locked" -eq 0 ] || { reason="locked"; return; }
  [ -n "$branch" ] || { reason="detached HEAD"; return; }
  n="$(git -C "$path" status --porcelain | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ] || { reason="$(plural "$n" "uncommitted file" "uncommitted files")"; return; }
  tip="$(git -C "$main" rev-parse "refs/heads/$branch")"
  if [ -n "$slug" ]; then
    # Every worktree is judged before the first removal, so a stop here
    # removes nothing.
    pr="$(pr_of "$slug" "$branch")" || exit 1
    read -r num state oid <<<"$pr" || true
  fi
  case "$state" in
    MERGED)
      if [ "$oid" = "$tip" ]; then flag="-D"
      else reason="PR #$num merged, tip is not its last commit"; fi
      return ;;
    OPEN) reason="PR #$num open"; return ;;
    CLOSED) reason="PR #$num closed, not merged"; return ;;
  esac
  # No PR, or no GitHub: git's own test.
  ref="$(default_ref "$main")"
  if [ -n "$ref" ] && git -C "$main" merge-base --is-ancestor "$tip" "$ref"; then flag="-d"; return; fi
  [ -n "$slug" ] || { reason="not in ${ref:-a default branch}"; return; }
  # A squash-merged branch's commits are on no remote ref, so this count is
  # only read for a branch with no PR.
  n="$(git -C "$main" rev-list --count "refs/heads/$branch" --not --remotes=origin)"
  [ "$n" -eq 0 ] || { reason="$(plural "$n" "commit not on GitHub" "commits not on GitHub")"; return; }
  reason="no PR"
}

# named <path>: whether the user named this worktree with --remove.
named() {
  local p
  for p in ${names[@]+"${names[@]}"}; do [ "$p" = "$1" ] && return 0; done
  return 1
}

# sort_one <main> <owner/repo> <path> <branch> <locked>: puts one worktree in
# kept or removals. With --remove, only a named worktree, and it is removed
# whatever the reason, unless the session is in it or it is locked; its branch
# keeps the flag judge gives, -d for any reason.
sort_one() {
  local main="$1" path="$3" branch="$4"
  if [ "${#names[@]}" -gt 0 ]; then
    named "$path" || return 0
    found+=("$path")
    judge "$@"
    [ "$reason" != "this session is in it" ] || die "this session is in $(show "$path")"
    if [ "$reason" = "locked" ]; then kept+=("$path${sep}locked"); return; fi
    removals+=("$main$sep$path$sep$branch$sep${flag:--d}$sep--force")
    return
  fi
  judge "$@"
  if [ -n "$flag" ]; then removals+=("$main$sep$path$sep$branch$sep$flag$sep")
  else kept+=("$path$sep$reason"); fi
}

# sort_repo <main>: sorts every worktree of the repo but the main checkout,
# which `git worktree list` always prints first. An entry whose folder is gone
# (`prunable`) is only counted, for `git worktree prune`.
sort_repo() {
  local main="$1" slug path="" branch="" locked=0 gone=0 line n=0 stale_n=0
  slug="$(github_repo "$main")"
  if named "$main"; then die "$(show "$main") is the main checkout"; fi
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }"; branch=""; locked=0; gone=0; n=$((n + 1)) ;;
      "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
      locked|"locked "*) locked=1 ;;
      prunable|"prunable "*) gone=1 ;;
      "")
        if [ -n "$path" ] && [ "$n" -gt 1 ]; then
          if [ "$gone" -eq 1 ]; then stale_n=$((stale_n + 1))
          else sort_one "$main" "$slug" "$path" "$branch" "$locked"; fi
        fi
        path="" ;;
    esac
  done < <(git -C "$main" worktree list --porcelain; echo)
  [ "$stale_n" -eq 0 ] || [ "${#names[@]}" -gt 0 ] || stale+=("$main$sep$stale_n")
}

usage="usage: prune-worktrees.sh [all] [--remove <path>]..."
all=0
names=()      # --remove paths, physical
found=()      # the names that are worktrees
while [ $# -gt 0 ]; do
  case "$1" in
    all) all=1; shift ;;
    --remove)
      [ -n "${2:-}" ] || die "$usage"
      [ -d "$2" ] || die "no folder at $2"
      names+=("$(cd "$2" && pwd -P)"); shift 2 ;;
    *) die "$usage" ;;
  esac
done

repos=()      # main checkouts, each once
add_repo() {
  local r
  for r in ${repos[@]+"${repos[@]}"}; do [ "$r" = "$1" ] && return 0; done
  repos+=("$1")
}

# The repo this session is in, and the worktree it is in, which stays.
session=""
if cd_git="$(common_dir "$PWD")"; then
  add_repo "${cd_git%/.git}"
  session="$(cd "$(git -C "$PWD" rev-parse --show-toplevel)" && pwd -P)"
elif [ "$all" -eq 0 ]; then
  die "not in a git repo"
fi
# root_worktree <path>: adds the repo of a worktree under the root, or keeps
# the folder when its repo is gone.
root_worktree() {
  local g
  if g="$(common_dir "$1")"; then add_repo "${g%/.git}"
  else kept+=("$1${sep}its repo is gone"); fi
}
# all: every repo with a worktree under the root, in either shape the checkout
# resolver lays out: <root>/<owner>/<repo>/<branch>, or the older
# <root>/<repo>/<branch>. A folder two down with a .git file is an old-shape
# worktree, and is never looked inside; any other folder there holds new-shape
# worktrees.
if [ "$all" -eq 1 ]; then
  root="${WORKTREES_ROOT:-$HOME/development/worktrees}"
  for d in "$root"/*/*; do
    if [ -f "$d/.git" ]; then root_worktree "$d"; continue; fi
    [ -d "$d" ] || continue
    for e in "$d"/*; do
      if [ -f "$e/.git" ]; then root_worktree "$e"; fi
    done
  done
fi
for r in ${repos[@]+"${repos[@]}"}; do sort_repo "$r"; done
for p in ${names[@]+"${names[@]}"}; do
  named_found=0
  for q in ${found[@]+"${found[@]}"}; do [ "$q" = "$p" ] && named_found=1; done
  [ "$named_found" -eq 1 ] || die "$(show "$p") is not a worktree of $(show "${repos[0]:-this repo}")"
done

for k in ${kept[@]+"${kept[@]}"}; do
  printf 'kept %s: %s\n' "$(show "${k%%"$sep"*}")" "${k#*"$sep"}"
done
done_any=0
for st in ${stale[@]+"${stale[@]}"}; do
  git -C "${st%%"$sep"*}" worktree prune
  printf 'cleared %s\n' "$(plural "${st#*"$sep"}" "stale entry" "stale entries")"
  done_any=1
done
for r in ${removals[@]+"${removals[@]}"}; do
  IFS="$sep" read -r main path branch flag force <<<"$r"
  git -C "$main" worktree remove ${force:+"$force"} "$path"
  if [ -z "$branch" ]; then
    printf 'removed %s\n' "$(show "$path")"
  elif git -C "$main" branch "$flag" "$branch" >/dev/null 2>&1; then
    printf 'removed %s, branch %s deleted (%s)\n' "$(show "$path")" "$branch" "$flag"
  else
    printf 'removed %s, branch %s kept: git branch %s refused\n' "$(show "$path")" "$branch" "$flag"
  fi
  done_any=1
done
[ "$done_any" -eq 1 ] || echo "nothing to prune"
