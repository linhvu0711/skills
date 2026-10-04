#!/usr/bin/env bash
# checkout.sh: find a repo's main checkout, make or reuse a worktree for a
# branch, and name the repo's default branch.
#
#   checkout.sh <owner/repo> <branch> [--base <ref>]
#
# The main checkout is the one the repo map names
# (${KICKOFF_REPO_MAP:-$HOME/.config/kickoff/repos.tsv}, `owner/repo<TAB>path`),
# else the current folder when its origin is <owner/repo>, else the one clone
# of it under ${KICKOFF_DEV_ROOT:-$HOME/development}. A checkout found without
# the map is added to it; a stale map line is dropped.
#
# A new worktree goes to
# ${WORKTREES_ROOT:-$HOME/development/worktrees}/<owner>/<repo>/<branch>,
# with every `/` in the branch written as `-`. Shared by /ship and /ready-pr.
#
# - A worktree of the repo is on the branch, clean, in this shape or the
#   older <root>/<repo>/<branch>: reused.
# - The branch exists locally: the worktree checks it out.
# - It exists only on origin: fetched and tracked.
# - It exists nowhere: made from --base (fetched from origin first).
#
# The default branch is GitHub's; when gh fails, origin/HEAD's; when both
# fail, it stops and says how to set origin/HEAD.
#
# Exit 0: one line,
# `MAIN=<dir> WORKTREE=<dir> BRANCH=<b> DEFAULT=<b> STATE=<created|reused> FROM=<what>`.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
# The .git directory a checkout or worktree belongs to, symlinks resolved.
common_dir() {
  local d
  d="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$d" ] || return 1
  (cd "$d" && pwd -P)
}

usage="usage: checkout.sh <owner/repo> <branch> [--base <ref>]"
slug=""; branch=""; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ -n "${2:-}" ] || die "$usage"; base="$2"; shift 2 ;;
    -*) die "unknown flag $1" ;;
    *) if [ -z "$slug" ]; then slug="$1"; elif [ -z "$branch" ]; then branch="$1"; else die "unexpected argument: $1"; fi; shift ;;
  esac
done
[ -n "$slug" ] && [ -n "$branch" ] || die "$usage"
[[ "$slug" =~ ^[^/]+/[^/]+$ ]] || die "$usage"

# ---------- main checkout ----------
map="${KICKOFF_REPO_MAP:-$HOME/.config/kickoff/repos.tsv}"
dev_root="${KICKOFF_DEV_ROOT:-$HOME/development}"

# origin_slug <dir>: owner/repo of a checkout's GitHub origin, or nothing. The
# raw config value, so an insteadOf rewrite never hides it.
origin_slug() {
  local url
  url="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 0
  case "$url" in
    *github.com[:/]*) printf '%s' "$url" | sed -E 's#\.git$##; s#/$##; s#.*github\.com[:/]##' ;;
  esac
}
is_main_checkout() { [ -d "$1/.git" ]; }  # a .git file is a worktree

main=""; main_from=""
# 1. the map
if [ -f "$map" ]; then
  cand="$(awk -F'\t' -v s="$slug" '$1==s {print $2; exit}' "$map")"
  if [ -n "$cand" ]; then
    if is_main_checkout "$cand" && [ "$(origin_slug "$cand")" = "$slug" ]; then
      main="$cand"; main_from="map"
    else
      printf 'map entry for %s is stale (%s), dropping it\n' "$slug" "$cand" >&2
      tmp="$(mktemp)"; awk -F'\t' -v s="$slug" '$1!=s' "$map" >"$tmp"; mv "$tmp" "$map"
    fi
  fi
fi
# 2. the current folder
if [ -z "$main" ] && is_main_checkout "$PWD" && [ "$(origin_slug "$PWD")" = "$slug" ]; then
  main="$PWD"; main_from="cwd"
fi
# 3. search the dev root
if [ -z "$main" ]; then
  matches=()
  while IFS= read -r gitdir; do
    d="${gitdir%/.git}"
    [ "$(origin_slug "$d")" = "$slug" ] && matches+=("$d")
  done < <(find "$dev_root" -maxdepth 6 -type d -name .git -not -path '*/node_modules/*' 2>/dev/null | sort)
  case "${#matches[@]}" in
    0) die "no checkout of $slug under $dev_root. Clone it, or add a line to $map: $slug<TAB>/path" ;;
    1) main="${matches[0]}"; main_from="search" ;;
    *) die "several checkouts of $slug: ${matches[*]}. Add the right one to $map: $slug<TAB>/path" ;;
  esac
fi
if [ "$main_from" != "map" ]; then
  mkdir -p "$(dirname "$map")"
  printf '%s\t%s\n' "$slug" "$main" >>"$map"
fi

git -C "$main" check-ref-format --branch "$branch" >/dev/null 2>&1 || die "not a valid branch name: $branch"

# ---------- default branch ----------
# GitHub's; when gh fails, origin/HEAD's, with no fetch.
default="$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)" || default=""
if [ -z "$default" ]; then
  default="$(git -C "$main" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || default=""
  default="${default#origin/}"
fi
[ -n "$default" ] || die "could not find the default branch of $slug: gh failed and origin/HEAD is not set. Set it with: git -C $main remote set-head origin --auto"

# ---------- worktree ----------
root="${WORKTREES_ROOT:-$HOME/development/worktrees}"
dir="$root/$slug/$(printf '%s' "$branch" | tr '/' '-')"

# done_line <worktree> <state> <from>: the exit 0 line.
done_line() {
  printf 'MAIN=%s WORKTREE=%s BRANCH=%s DEFAULT=%s STATE=%s FROM=%s\n' "$main" "$1" "$branch" "$default" "$2" "$3"
}

# A worktree on the branch already, in either folder shape: reused. The main
# checkout, which `git worktree list` prints first, is never one.
listed="$(git -C "$main" worktree list --porcelain)"
where="$(awk -v b="refs/heads/$branch" '$1=="worktree"{w=$2} $1=="branch" && $2==b {print w}' <<<"$listed")"
if [ -n "$where" ]; then
  [ "$where" != "$(awk '$1=="worktree"{print $2; exit}' <<<"$listed")" ] \
    || die "branch $branch is already checked out at $where"
  dirty="$(git -C "$where" status --porcelain)"
  [ -z "$dirty" ] || die "dirty worktree at $where:"$'\n'"$dirty"
  done_line "$where" reused existing
  exit 0
fi

# Something else in the folder?
if [ -e "$dir" ]; then
  [ -f "$dir/.git" ] || die "$dir exists and is not a worktree"
  owner="$(common_dir "$dir")" || die "$dir is a worktree whose repo is gone"
  [ "$owner" = "$(common_dir "$main")" ] || die "$dir is a worktree of ${owner%/.git}, not $main"
  die "$dir is on '$(git -C "$dir" branch --show-current 2>/dev/null || true)', not '$branch'"
fi

# Where is the branch?
from=""
if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
  from="local"
elif git -C "$main" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  from="origin"
else
  [ -n "$base" ] || die "branch $branch exists nowhere and no --base was given"
  from="base:$base"
fi

mkdir -p "$(dirname "$dir")"
case "$from" in
  local)  git -C "$main" worktree add --quiet "$dir" "$branch" ;;
  origin) git -C "$main" fetch --quiet origin "$branch"
          git -C "$main" worktree add --quiet --track -b "$branch" "$dir" "origin/$branch" ;;
  base:*) git -C "$main" fetch --quiet origin "$base" || die "could not fetch origin/$base"
          git -C "$main" worktree add --quiet -b "$branch" "$dir" "origin/$base" ;;
esac
done_line "$dir" created "$from"
