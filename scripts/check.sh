#!/usr/bin/env bash
# check.sh: find leaks before they reach the public repo.
#
#   check.sh <path>...     scan every file under these paths, tracked or not
#
# Checks: an absolute home path.
#
# Exit 0: `check: clean` on stdout.
# Exit 1: one `<file>:<line>: <kind>: <match>` line per problem on stderr,
# then `check: <n> problem(s) found`.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

home_re='/(Users|home)/[A-Za-z0-9._-]+'

[ $# -gt 0 ] || die "usage: check.sh <path>..."
cd "$(git rev-parse --show-toplevel)" || die "not inside a git repo"

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$@" -type f -not -path '*/.git/*')

problems=()

# scan <kind> <pattern>: add every hit in the files as `<file>:<line>: <kind>: <match>`.
scan() {
  local kind="$1" re="$2" hit
  [ ${#files[@]} -gt 0 ] || return 0
  while IFS= read -r hit; do
    problems+=("$(printf '%s' "$hit" | sed -E "s/^([^:]*):([0-9]+):/\1:\2: $kind: /")")
  done < <(grep -nHIoE -e "$re" -- "${files[@]}" || true)
}

scan "home path" "$home_re"

if [ ${#problems[@]} -eq 0 ]; then
  echo "check: clean"
  exit 0
fi
printf '%s\n' "${problems[@]}" >&2
printf 'check: %d problem(s) found\n' "${#problems[@]}" >&2
exit 1
