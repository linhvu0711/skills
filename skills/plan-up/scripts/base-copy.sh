#!/usr/bin/env bash
# base-copy.sh: a fresh copy of the base for /plan-up to read, so the checkout
# you work in can be on any branch, with edits or not, and is never touched.
#
#   base-copy.sh <base>          fetch origin/<base>, add a detached worktree of it, with its
#                                submodules, in a temp folder, and install the packages its
#                                lockfile names (pnpm, npm, yarn, bun) with no install scripts
#   base-copy.sh --remove <dir>  remove that worktree and its temp folder
#
# Run it inside a checkout of the repo: any branch, any state.
# Exit 0: `BASE_WT=<dir> BASE_SHA=<sha>` on add, `removed <dir>` on remove.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
# A failed install, or no package tool, is no stop: one
# `warn: could not install the packages of <base>: <why>` line on stderr, and
# the copy is kept with no packages. The install's output is in
# <dir>/../install.log.
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
    # Readers look up library code and types in the copy. It is read, never
    # run, so install scripts stay off, and the frozen flags keep its lockfile.
    install=()
    if [ -f "$dir/pnpm-lock.yaml" ]; then
      install=(pnpm install --frozen-lockfile --ignore-scripts)
    elif [ -f "$dir/package-lock.json" ]; then
      install=(npm ci --ignore-scripts)
    elif [ -f "$dir/yarn.lock" ] && grep -qF '# yarn lockfile v1' "$dir/yarn.lock"; then
      install=(yarn install --frozen-lockfile --ignore-scripts)
    elif [ -f "$dir/yarn.lock" ]; then
      install=(yarn install --immutable --mode=skip-build)
    elif [ -f "$dir/bun.lock" ] || [ -f "$dir/bun.lockb" ]; then
      install=(bun install --frozen-lockfile --ignore-scripts)
    fi
    if [ "${#install[@]}" -gt 0 ]; then
      why=""
      if ! command -v "${install[0]}" >/dev/null 2>&1; then
        why="${install[0]} not found"
      else
        rc=0
        (cd "$dir" && "${install[@]}") </dev/null >"$tmp/install.log" 2>&1 || rc=$?
        if [ "$rc" -ne 0 ]; then
          # npm prints its `npm warn` lines before the `npm error` one.
          why="$(awk '!hit && tolower($0) ~ /err/ { hit = $0 } NF { last = $0 }
            END { line = hit != "" ? hit : last; gsub(/^[ \t]+|[ \t]+$/, "", line); print line }' "$tmp/install.log")"
          why="${why:-exit $rc}"
        fi
      fi
      [ -z "$why" ] || printf 'warn: could not install the packages of %s: %s\n' "$base" "$why" >&2
    fi
    printf 'BASE_WT=%s BASE_SHA=%s\n' "$dir" "$sha"
    ;;
esac
