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
# Safe to prune: the PR of the branch is merged on GitHub, and the branch tip
# is the PR's last commit. The worktree goes with `git worktree remove`, the
# branch with `git branch -D`.
#
# Prints, in this order:
#   kept <path>: <reason>                          one per worktree that stays
#   removed <path>, branch <b> deleted (-D)        one per worktree removed
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
# branch's newest PR, or nothing when it has none.
pr_of() {
  gh pr list -R "$1" --head "$2" --state all --limit 1 \
    --json number,state,headRefOid --jq '.[] | "\(.number) \(.state) \(.headRefOid)"'
}

tab=$'\t'
kept=()       # <path> TAB <reason>
removals=()   # <main> TAB <path> TAB <branch> TAB <flag>

# sort_one <main> <owner/repo> <path> <branch>: puts one worktree in kept or
# removals.
sort_one() {
  local main="$1" slug="$2" path="$3" branch="$4" tip num="" state="" oid=""
  tip="$(git -C "$main" rev-parse "refs/heads/$branch")"
  if [ -n "$slug" ]; then
    read -r num state oid <<<"$(pr_of "$slug" "$branch")" || true
  fi
  if [ "$state" = MERGED ] && [ "$oid" = "$tip" ]; then
    removals+=("$main$tab$path$tab$branch$tab-D")
  else
    kept+=("$path${tab}no PR")
  fi
}

# sort_repo <main>: sorts every worktree of the repo but the main checkout,
# which `git worktree list` always prints first.
sort_repo() {
  local main="$1" slug path="" branch="" line n=0
  slug="$(github_repo "$main")"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }"; branch=""; n=$((n + 1)) ;;
      "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
      "")
        if [ -n "$path" ] && [ "$n" -gt 1 ]; then sort_one "$main" "$slug" "$path" "$branch"; fi
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
