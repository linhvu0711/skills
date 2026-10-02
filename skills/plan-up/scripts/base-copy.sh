#!/usr/bin/env bash
# base-copy.sh: a fresh copy of the base for /plan-up to read, so the checkout
# you work in can be on any branch, with edits or not, and is never touched.
#
#   base-copy.sh <base>          fetch origin/<base>, add a detached worktree of it, with its
#                                submodules, in a temp folder
#   base-copy.sh --remove <dir>  remove that worktree and its temp folder
#
# Run it inside a checkout of the repo: any branch, any state.
# Exit 0: `BASE_WT=<dir> BASE_SHA=<sha>` on add, `removed <dir>` on remove.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --remove)
    dir="${2:-}"
    [ -n "$dir" ] || die "usage: base-copy.sh --remove <dir>"
    case "$dir" in */plan-up-base.*/base) ;; *) die "$dir is not a base copy" ;; esac
    if [ -e "$dir/.git" ]; then
      common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)" \
        || die "$dir is a worktree whose repo is gone"
      git --git-dir="$common" worktree remove --force "$dir"
    fi
    rm -rf "$(dirname "$dir")"
    printf 'removed %s\n' "$dir"
    ;;
  "" | -*)
    die "usage: base-copy.sh <base> | --remove <dir>"
    ;;
  *)
    base="$1"
    git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git checkout"
    git check-ref-format --branch "$base" >/dev/null 2>&1 || die "not a valid branch name: $base"
    git fetch --quiet origin "+refs/heads/$base:refs/remotes/origin/$base" \
      || die "could not fetch $base from origin"
    sha="$(git rev-parse --verify "refs/remotes/origin/$base^{commit}")"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/plan-up-base.XXXXXX")"
    dir="$(cd "$tmp" && pwd -P)/base"
    git worktree add --quiet --detach "$dir" "$sha" \
      || { rm -rf "$tmp"; die "could not add a worktree at $dir"; }
    # A worktree starts with empty submodules; the facts step reads them too.
    # submodule.active=. adds every path, whatever the repo's own filter says.
    if [ -f "$dir/.gitmodules" ]; then
      git -C "$dir" -c submodule.active=. submodule update --quiet --init --recursive \
        || { git worktree remove --force "$dir"; rm -rf "$tmp"; die "could not check out the submodules of $base"; }
    fi
    printf 'BASE_WT=%s BASE_SHA=%s\n' "$dir" "$sha"
    ;;
esac
