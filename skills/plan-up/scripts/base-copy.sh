#!/usr/bin/env bash
# base-copy.sh: a fresh copy of the base for /plan-up to read, so the checkout
# you work in can be on any branch, with edits or not, and is never touched.
#
#   base-copy.sh <base>          fetch origin/<base> and add a detached worktree of it, by
#                                the shared base-tree.sh, check out its submodules, and
#                                install the packages its lockfile names (pnpm, npm, yarn,
#                                bun) with no install scripts
#   base-copy.sh --remove <dir>  remove that worktree and its temp folder
#
# Run it inside a checkout of the repo: any branch, any state.
# Exit 0: `BASE_WT=<dir> BASE_SHA=<sha>` on add, `removed <dir>` on remove.
# Exit 1: `stop: <why>` on stderr. Nothing is half done.
# Exit 64: a wrong command line, its usage on stderr.
# A failed install, or no package tool, is no stop: one
# `warn: could not install the packages of <base>: <why>` line on stderr, and
# the copy is kept with no packages. The install's output is in
# <dir>/../install.log.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
usage='usage: base-copy.sh <base> | --remove <dir>'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tree="$here/../../../shared/base-tree.sh"

case "${1:-}" in
  --remove)
    dir="${2:-}"
    [ -n "$dir" ] || die_usage "$usage"
    "$BASH" "$tree" --remove "$dir"
    ;;
  "" | -*)
    die_usage "$usage"
    ;;
  *)
    base="$1"
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git checkout"
    # $BASH, not PATH's bash: a caller's PATH may hold no bash.
    line="$("$BASH" "$tree" "$top" "$base")" || exit 1
    dir="${line#BASE_TREE=}"; dir="${dir% BASE_SHA=*}"; sha="${line##* BASE_SHA=}"
    tmp="$(dirname "$dir")"
    # A worktree starts with empty submodules; the facts step reads them too.
    # submodule.active=. adds every path, whatever the repo's own filter says.
    if [ -f "$dir/.gitmodules" ]; then
      git -C "$dir" -c submodule.active=. submodule update --quiet --init --recursive \
        || { "$BASH" "$tree" --remove "$dir" >/dev/null; die "could not check out the submodules of $base"; }
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
