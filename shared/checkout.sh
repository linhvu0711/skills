#!/usr/bin/env bash
# checkout.sh: find a repo's main checkout, make or reuse a worktree for a
# branch, name the repo's default branch, and name a checkout's GitHub repo
# (`checkout.sh slug <dir>`).
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
# with every `/` in the branch written as `-`. Shared by /ship, /ready-pr,
# /kickoff-herdr, /kickoff-t3, restack.sh, prune-worktrees.sh, orchestrate.sh,
# and retro's github.py.
#
# - A worktree of the repo is on the branch, clean, in this shape or the
#   older <root>/<repo>/<branch>: reused.
# - The branch exists locally: the worktree checks it out.
# - It exists only on origin: fetched and tracked.
# - It exists nowhere: made from --base (fetched from origin first).
#
# A worktree it makes or reuses gets each file of the main checkout that the
# main checkout's .worktreeinclude lists and git ignores, such as .dev.vars,
# when the worktree lacks it. The list is .gitignore patterns at the repo root,
# the file Claude Code, the Codex app, and Conductor read for the same job. A
# file inside a folder git ignores whole, as node_modules/, is copied only when
# a list line starts with that folder. Stderr names the files, never their
# contents, one line each, only when it has a name:
#   worktreeinclude: copied <names>
#   worktreeinclude: not in the main checkout, skipped: <plain list lines>
#   worktreeinclude: not git-ignored, skipped: <plain list lines>
#   worktreeinclude: could not copy, skipped: <names>
# None of them stops it.
#
# The default branch is GitHub's; when gh fails, origin/HEAD's; when both
# fail, it stops and says how to set origin/HEAD.
#
# Exit 0: one line,
# `MAIN=<dir> WORKTREE=<dir> BRANCH=<b> DEFAULT=<b> STATE=<created|reused> FROM=<what>`.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
#
#   checkout.sh main <owner/repo>
#
# Finds only the main checkout, by the order above, with no gh call. Exit 0:
# one line, `FROM=<map|cwd|search> MAIN=<dir>`, the path last.
#
#   checkout.sh default <owner/repo>
#
# Names the repo's default branch by the rule above, from the main checkout
# the order above finds. Exit 0: one line, the branch. Exit 2: gh failed and
# origin/HEAD is not set, so a caller can tell a GitHub outage from a missing
# checkout, which stays exit 1.
#
#   checkout.sh slug <dir>
#
# Names the GitHub repo of the checkout at <dir> by its origin, as
# origin_is reads it. Exit 0: one line, `owner/repo`. No GitHub origin:
# `stop: <dir> has no GitHub remote`.
#
#   checkout.sh worktrees <dir>
#
# Lists every worktree of the repo <dir> is in, the main checkout (or the
# bare repo) first, as git lists them, one line each:
# `BRANCH=<b> LOCKED=<0|1> PRUNABLE=<0|1> WORKTREE=<path>`. BRANCH is empty on
# a detached HEAD and on the bare repo; PRUNABLE=1 is a worktree whose folder is gone. The path
# comes last, so `read` keeps a space in it.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
# The .git directory a checkout or worktree belongs to, symlinks resolved.
common_dir() {
  local d
  d="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$d" ] || return 1
  (cd "$d" && pwd -P)
}
# worktrees <dir>: the lines of the `worktrees` form, from
# `git worktree list --porcelain`.
worktrees() {
  local listed line path="" branch="" locked=0 gone=0
  listed="$(git -C "$1" worktree list --porcelain 2>/dev/null)" || die "not a git checkout: $1"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }"; branch=""; locked=0; gone=0 ;;
      "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
      locked|"locked "*) locked=1 ;;
      prunable|"prunable "*) gone=1 ;;
      "")
        if [ -n "$path" ]; then
          printf 'BRANCH=%s LOCKED=%s PRUNABLE=%s WORKTREE=%s\n' "$branch" "$locked" "$gone" "$path"
        fi
        path="" ;;
    esac
  done < <(printf '%s\n\n' "$listed")
}

# ---------- main checkout ----------
map="${KICKOFF_REPO_MAP:-$HOME/.config/kickoff/repos.tsv}"
dev_root="${KICKOFF_DEV_ROOT:-$HOME/development}"

# github_slug <url>: owner/repo of a GitHub URL, or nothing.
github_slug() {
  case "$1" in
    *github.com[:/]*) printf '%s' "$1" | sed -E 's#\.git$##; s#/$##; s#.*github\.com[:/]##' ;;
  esac
}
# origin_slug <dir>: owner/repo of the checkout's origin, or nothing. The
# URL git uses after insteadOf names it when it is on GitHub, so an alias such
# as gh:acme/app counts; else the URL as configured does, so a rewrite to a
# local mirror never hides it. One checkout never names two repos. It always
# returns 0, since a failing $(...) under set -e would exit before a caller's
# own stop line.
origin_slug() {
  local raw eff
  eff="$(github_slug "$(git -C "$1" remote get-url origin 2>/dev/null || true)")"
  if [ -n "$eff" ]; then printf '%s' "$eff"; return 0; fi
  raw="$(git -C "$1" config --get remote.origin.url 2>/dev/null || true)"
  github_slug "$raw"
  return 0
}
# origin_is <dir> <owner/repo>: the checkout's origin is that GitHub repo.
origin_is() {
  local s
  s="$(origin_slug "$1")"
  [ -n "$s" ] && [ "$s" = "$2" ]
}
is_main_checkout() { [ -d "$1/.git" ]; }  # a .git file is a worktree

# find_main <owner/repo>: sets main and main_from (map, cwd, or search) by the
# order in the header, and writes a find to the map. Stops on none or several.
find_main() {
  local slug="$1" cand tmp gitdir d matches
  main=""; main_from=""
  # 1. the map
  if [ -f "$map" ]; then
    cand="$(awk -F'\t' -v s="$slug" '$1==s {print $2; exit}' "$map")"
    if [ -n "$cand" ]; then
      if is_main_checkout "$cand" && origin_is "$cand" "$slug"; then
        main="$cand"; main_from="map"
      else
        printf 'map entry for %s is stale (%s), dropping it\n' "$slug" "$cand" >&2
        tmp="$(mktemp)"; awk -F'\t' -v s="$slug" '$1!=s' "$map" >"$tmp"; mv "$tmp" "$map"
      fi
    fi
  fi
  # 2. the current folder
  if [ -z "$main" ] && is_main_checkout "$PWD" && origin_is "$PWD" "$slug"; then
    main="$PWD"; main_from="cwd"
  fi
  # 3. search the dev root
  if [ -z "$main" ]; then
    matches=()
    while IFS= read -r gitdir; do
      d="${gitdir%/.git}"
      if origin_is "$d" "$slug"; then matches+=("$d"); fi
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
}

# default_branch <owner/repo> <main> [<code>]: sets default to GitHub's
# default branch; when gh fails, origin/HEAD's, with no fetch. When both fail,
# the stop line and exit <code>, 1 when not given.
default_branch() {
  default="$(gh repo view "$1" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)" || default=""
  if [ -z "$default" ]; then
    default="$(git -C "$2" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || default=""
    default="${default#origin/}"
  fi
  [ -n "$default" ] && return 0
  printf 'stop: could not find the default branch of %s: gh failed and origin/HEAD is not set. Set it with: git -C %s remote set-head origin --auto\n' "$1" "$2" >&2
  exit "${3:-1}"
}

# The forms that take no branch.
case "${1:-}" in
  slug)
    [ $# -eq 2 ] && [ -n "$2" ] || die "usage: checkout.sh slug <dir>"
    s="$(origin_slug "$2")"
    [ -n "$s" ] || die "$2 has no GitHub remote"
    printf '%s\n' "$s"; exit 0 ;;
  worktrees)
    [ $# -eq 2 ] && [ -n "$2" ] || die "usage: checkout.sh worktrees <dir>"
    worktrees "$2"; exit 0 ;;
  main)
    [ $# -eq 2 ] && [[ "$2" =~ ^[^/]+/[^/]+$ ]] || die "usage: checkout.sh main <owner/repo>"
    find_main "$2"
    printf 'FROM=%s MAIN=%s\n' "$main_from" "$main"; exit 0 ;;
  default)
    [ $# -eq 2 ] && [[ "$2" =~ ^[^/]+/[^/]+$ ]] || die "usage: checkout.sh default <owner/repo>"
    find_main "$2"
    default_branch "$2" "$main" 2
    printf '%s\n' "$default"; exit 0 ;;
esac

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

find_main "$slug"

git -C "$main" check-ref-format --branch "$branch" >/dev/null 2>&1 || die "not a valid branch name: $branch"

default_branch "$slug" "$main"

# ---------- worktree ----------
root="${WORKTREES_ROOT:-$HOME/development/worktrees}"
dir="$root/$slug/$(printf '%s' "$branch" | tr '/' '-')"

# done_line <worktree> <state> <from>: the exit 0 line.
done_line() {
  printf 'MAIN=%s WORKTREE=%s BRANCH=%s DEFAULT=%s STATE=%s FROM=%s\n' "$main" "$1" "$branch" "$default" "$2" "$3"
}

# names <head> <name...>: one stderr line, `worktreeinclude: <head><names>`,
# the names joined by `, `; nothing when no name is given.
names() {
  local head="$1" joined
  shift
  [ $# -gt 0 ] || return 0
  joined="$(printf '%s, ' "$@")"
  printf 'worktreeinclude: %s%s\n' "$head" "${joined%, }" >&2
}

# copy_included <worktree>: copy into the worktree each file of the main
# checkout that its .worktreeinclude lists and git ignores, by the rule Claude
# Code, the Codex app, and Conductor share for that file, so one list serves
# every tool. A file inside a folder git ignores whole, as node_modules/, is
# copied only when a list line starts with that folder. A file the worktree
# has already is kept. Only names are printed, and nothing here stops the
# script: the worktree is whole without the copies.
copy_included() {
  local wt="$1" list="$main/.worktreeinclude" f d line keep
  # Each array is read as ${a[@]+"${a[@]}"}: Bash 3.2, the macOS one, calls
  # an empty "${a[@]}" unbound under set -u.
  local dirs=() copied=() missing=() unignored=() failed=()
  [ -f "$list" ] || return 0
  while IFS= read -r d; do
    case "$d" in */) if git -C "$main" check-ignore -q -- "$d"; then dirs+=("$d"); fi ;; esac
  done < <(git -C "$main" ls-files -o -i --exclude-standard --directory)
  while IFS= read -r -d '' f; do
    git -C "$main" check-ignore -q -- "$f" || continue
    keep=1
    for d in ${dirs[@]+"${dirs[@]}"}; do
      case "$f" in "$d"*)
        keep=0
        while IFS= read -r line || [ -n "$line" ]; do
          case "${line#/}" in "$d"*) keep=1; break ;; esac
        done < "$list"
        break ;;
      esac
    done
    [ "$keep" -eq 1 ] || continue
    # -e is false for a dangling link; that link is the worktree's own, so keep it.
    [ ! -e "$wt/$f" ] && [ ! -L "$wt/$f" ] || continue
    # Written under a temp name and moved, so a cut-off copy never looks whole.
    if mkdir -p "$(dirname "$wt/$f")" && cp -p "$main/$f" "$wt/$f.tmp.$$" 2>/dev/null && mv "$wt/$f.tmp.$$" "$wt/$f"; then
      copied+=("$f")
    else
      rm -f "$wt/$f.tmp.$$"; failed+=("$f")
    fi
  done < <(git -C "$main" ls-files -z -o -i --exclude-from="$list")
  # A pattern may match nothing on purpose; only a plain path is named.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|'!'*|*'*'*|*'?'*|*'['*) continue ;; esac
    line="${line#/}"
    if [ ! -e "$main/$line" ]; then
      missing+=("$line")
    elif ! git -C "$main" ls-files --error-unmatch -- "$line" >/dev/null 2>&1 && ! git -C "$main" check-ignore -q -- "$line"; then
      unignored+=("$line")
    fi
  done < "$list"
  names "copied " ${copied[@]+"${copied[@]}"}
  names "not in the main checkout, skipped: " ${missing[@]+"${missing[@]}"}
  names "not git-ignored, skipped: " ${unignored[@]+"${unignored[@]}"}
  names "could not copy, skipped: " ${failed[@]+"${failed[@]}"}
}

# A worktree on the branch already, in either folder shape: reused. The main
# checkout, which `worktrees` lists first, is never one.
listed="$(worktrees "$main")"
first=""; where=""
while read -r b _ _ w; do
  [ -n "$first" ] || first="${w#WORKTREE=}"
  if [ "$b" = "BRANCH=$branch" ]; then where="${w#WORKTREE=}"; break; fi
done <<<"$listed"
if [ -n "$where" ]; then
  [ "$where" != "$first" ] || die "branch $branch is already checked out at $where"
  dirty="$(git -C "$where" status --porcelain)"
  [ -z "$dirty" ] || die "dirty worktree at $where:"$'\n'"$dirty"
  copy_included "$where"
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
copy_included "$dir"
done_line "$dir" created "$from"
