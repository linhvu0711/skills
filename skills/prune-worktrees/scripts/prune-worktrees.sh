#!/usr/bin/env bash
# prune-worktrees.sh: remove the worktrees that are safe to prune, with their
# branches, and list every other worktree with the reason it stays.
#
#   prune-worktrees.sh
#
# It reads every worktree of the repo the current folder is in, wherever the
# worktree is on disk. The main checkout is never touched and never printed.
# Every worktree is sorted first, then the safe ones are removed.
#
# Safe to prune: a clean worktree whose PR is merged on GitHub with the branch
# tip as its last commit; the branch goes with `git branch -D`. Or, with no
# PR, a clean worktree whose branch tip is in the default branch; the branch
# goes with `git branch -d`. A repo with no GitHub remote gets only the second
# test, and no gh call.
#
# Prints, in this order:
#   kept <path>: <reason>                          one per worktree that stays:
#     `locked`, `detached HEAD`, `<n> uncommitted files`, `PR #<n> open`,
#     `PR #<n> closed, not merged`, `PR #<n> merged, tip is not its last commit`,
#     `<n> commits not on GitHub` (a branch with no PR), `no PR`,
#     `not in <default>` (a repo with no GitHub remote)
#   removed <path>, branch <b> deleted (-D|-d)     one per worktree removed,
#   removed <path>, branch <b> kept: git branch -d refused      or this
#   nothing to prune                               when nothing was removed
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

tab=$'\t'
kept=()       # <path> TAB <reason>
removals=()   # <main> TAB <path> TAB <branch> TAB <flag>

# plural <n> <one> <many>: `<n> <one>` or `<n> <many>`.
plural() { if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }

# sort_one <main> <owner/repo> <path> <branch> <locked>: puts one worktree in
# kept or removals. The first reason that holds is the one printed.
sort_one() {
  local main="$1" slug="$2" path="$3" branch="$4" locked="$5" tip n ref pr="" num="" state="" oid=""
  keep() { kept+=("$path$tab$1"); }
  [ "$locked" -eq 0 ] || { keep "locked"; return; }
  [ -n "$branch" ] || { keep "detached HEAD"; return; }
  n="$(git -C "$path" status --porcelain | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ] || { keep "$(plural "$n" "uncommitted file" "uncommitted files")"; return; }
  tip="$(git -C "$main" rev-parse "refs/heads/$branch")"
  if [ -n "$slug" ]; then
    # Every worktree is sorted before the first removal, so a stop here
    # removes nothing.
    pr="$(pr_of "$slug" "$branch")" || exit 1
    read -r num state oid <<<"$pr" || true
  fi
  case "$state" in
    MERGED)
      if [ "$oid" = "$tip" ]; then removals+=("$main$tab$path$tab$branch$tab-D")
      else keep "PR #$num merged, tip is not its last commit"; fi
      return ;;
    OPEN) keep "PR #$num open"; return ;;
    CLOSED) keep "PR #$num closed, not merged"; return ;;
  esac
  # No PR, or no GitHub: git's own test.
  ref="$(default_ref "$main")"
  if [ -n "$ref" ] && git -C "$main" merge-base --is-ancestor "$tip" "$ref"; then
    removals+=("$main$tab$path$tab$branch$tab-d"); return
  fi
  [ -n "$slug" ] || { keep "not in ${ref:-a default branch}"; return; }
  # A squash-merged branch's commits are on no remote ref, so this count is
  # only read for a branch with no PR.
  n="$(git -C "$main" rev-list --count "refs/heads/$branch" --not --remotes=origin)"
  [ "$n" -eq 0 ] || { keep "$(plural "$n" "commit not on GitHub" "commits not on GitHub")"; return; }
  keep "no PR"
}

# sort_repo <main>: sorts every worktree of the repo but the main checkout,
# which `git worktree list` always prints first.
sort_repo() {
  local main="$1" slug path="" branch="" locked=0 line n=0
  slug="$(github_repo "$main")"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }"; branch=""; locked=0; n=$((n + 1)) ;;
      "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
      locked|"locked "*) locked=1 ;;
      "")
        if [ -n "$path" ] && [ "$n" -gt 1 ]; then sort_one "$main" "$slug" "$path" "$branch" "$locked"; fi
        path="" ;;
    esac
  done < <(git -C "$main" worktree list --porcelain; echo)
}

[ $# -eq 0 ] || die "usage: prune-worktrees.sh"
cd_git="$(common_dir "$PWD")" || die "not in a git repo"
sort_repo "${cd_git%/.git}"

for k in ${kept[@]+"${kept[@]}"}; do
  printf 'kept %s: %s\n' "$(show "${k%%"$tab"*}")" "${k#*"$tab"}"
done
done_any=0
for r in ${removals[@]+"${removals[@]}"}; do
  IFS="$tab" read -r main path branch flag <<<"$r"
  git -C "$main" worktree remove "$path"
  if git -C "$main" branch "$flag" "$branch" >/dev/null 2>&1; then
    printf 'removed %s, branch %s deleted (%s)\n' "$(show "$path")" "$branch" "$flag"
  else
    printf 'removed %s, branch %s kept: git branch %s refused\n' "$(show "$path")" "$branch" "$flag"
  fi
  done_any=1
done
[ "$done_any" -eq 1 ] || echo "nothing to prune"
