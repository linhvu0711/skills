#!/usr/bin/env bash
# worktree.sh: make or reuse a git worktree in the one folder all of them live in.
#
#   worktree.sh <main-checkout> <branch> [--base <ref>] [--dry-run]
#
# The folder is ${WORKTREES_ROOT:-$HOME/development/worktrees}/<repo>/<branch>,
# with every `/` in the branch written as `-`. <repo> is the origin's repo
# name. Shared by /ship and /land-pr.
#
# - The branch exists locally: the worktree checks it out.
# - It exists only on origin: fetched and tracked.
# - It exists nowhere: made from --base (fetched from origin first).
# - The folder is already that worktree, clean, on that branch: reused.
#
# Exit 0: one line, `WORKTREE=<dir> BRANCH=<b> STATE=<created|reused> FROM=<what>`.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

repo=""; branch=""; base=""; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -*) die "unknown flag $1" ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$branch" ]; then branch="$1"; else die "unexpected argument: $1"; fi; shift ;;
  esac
done
[ -n "$repo" ] && [ -n "$branch" ] || die "usage: worktree.sh <main-checkout> <branch> [--base <ref>] [--dry-run]"
[ -d "$repo/.git" ] || die "$repo is not a main checkout (no .git directory)"
git -C "$repo" check-ref-format --branch "$branch" >/dev/null 2>&1 || die "not a valid branch name: $branch"

origin="$(git -C "$repo" remote get-url origin 2>/dev/null)" || die "no origin remote in $repo"
name="$(printf '%s' "$origin" | sed -E 's#\.git$##; s#/$##; s#.*[/:]##')"
[ -n "$name" ] || die "could not read the repo name from $origin"

root="${WORKTREES_ROOT:-$HOME/development/worktrees}"
dir="$root/$name/$(printf '%s' "$branch" | tr '/' '-')"

# Already a worktree there?
if [ -e "$dir" ]; then
  [ -f "$dir/.git" ] || die "$dir exists and is not a worktree"
  cur="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
  [ "$cur" = "$branch" ] || die "$dir is on '$cur', not '$branch'"
  dirty="$(git -C "$dir" status --porcelain)"
  [ -z "$dirty" ] || die "dirty worktree at $dir:"$'\n'"$dirty"
  printf 'WORKTREE=%s BRANCH=%s STATE=reused FROM=existing\n' "$dir" "$branch"
  exit 0
fi

# Where is the branch?
from=""
if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  where="$(git -C "$repo" worktree list --porcelain | awk -v b="refs/heads/$branch" '$1=="worktree"{w=$2} $1=="branch" && $2==b {print w}')"
  [ -z "$where" ] || die "branch $branch is already checked out at $where"
  from="local"
elif git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  from="origin"
else
  [ -n "$base" ] || die "branch $branch exists nowhere and no --base was given"
  from="base:$base"
fi

if [ "$dry" -eq 1 ]; then
  printf 'dry-run: WORKTREE=%s BRANCH=%s STATE=created FROM=%s\n' "$dir" "$branch" "$from"
  exit 0
fi

mkdir -p "$(dirname "$dir")"
case "$from" in
  local)  git -C "$repo" worktree add --quiet "$dir" "$branch" ;;
  origin) git -C "$repo" fetch --quiet origin "$branch"
          git -C "$repo" worktree add --quiet --track -b "$branch" "$dir" "origin/$branch" ;;
  base:*) git -C "$repo" fetch --quiet origin "$base" || die "could not fetch origin/$base"
          git -C "$repo" worktree add --quiet -b "$branch" "$dir" "origin/$base" ;;
esac
printf 'WORKTREE=%s BRANCH=%s STATE=created FROM=%s\n' "$dir" "$branch" "$from"
