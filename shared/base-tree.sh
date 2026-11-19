#!/usr/bin/env bash
# base-tree.sh: a detached worktree of origin's head of a base branch, fetched
# just before, for a skill that must read or run the base. The local branch of
# the same name can lag origin, and a tree made from it shows old code.
#
#   base-tree.sh <checkout> <base>   fetch origin/<base> into <checkout>'s repo and add a
#                                    detached worktree of it at <temp>/base
#   base-tree.sh --remove <dir>      remove that worktree and its temp folder
#
# Exit 0: `BASE_TREE=<dir> BASE_SHA=<sha>` on add, `removed <dir>` on remove.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --remove)
    dir="${2:-}"
    [ -n "$dir" ] || die "usage: base-tree.sh --remove <dir>"
    case "$dir" in */base-tree.*/base) ;; *) die "$dir is not a base tree" ;; esac
    if [ -e "$dir/.git" ]; then
      common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)" \
        || die "$dir is a worktree whose repo is gone"
      git --git-dir="$common" worktree remove --force "$dir"
    fi
    rm -rf "$(dirname "$dir")"
    printf 'removed %s\n' "$dir"
    ;;
  "" | -*)
    die "usage: base-tree.sh <checkout> <base> | --remove <dir>"
    ;;
  *)
    [ $# -eq 2 ] || die "usage: base-tree.sh <checkout> <base> | --remove <dir>"
    checkout="$1"; base="$2"
    git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1 || die "$checkout is not a git checkout"
    git check-ref-format --branch "$base" >/dev/null 2>&1 || die "not a valid branch name: $base"
    git -C "$checkout" fetch --quiet origin "+refs/heads/$base:refs/remotes/origin/$base" \
      || die "could not fetch $base from origin"
    sha="$(git -C "$checkout" rev-parse --verify "refs/remotes/origin/$base^{commit}")"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/base-tree.XXXXXX")"
    dir="$(cd "$tmp" && pwd -P)/base"
    git -C "$checkout" worktree add --quiet --detach "$dir" "$sha" \
      || { rm -rf "$tmp"; die "could not add a worktree at $dir"; }
    printf 'BASE_TREE=%s BASE_SHA=%s\n' "$dir" "$sha"
    ;;
esac
