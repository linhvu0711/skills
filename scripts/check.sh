#!/usr/bin/env bash
# check.sh: find leaks before they reach the public repo.
#
#   check.sh <path>...     scan every file under these paths, tracked or not
#
# Checks: an absolute home path, and an email address unless it is on the
# allow list below.
#
# Exit 0: `check: clean` on stdout.
# Exit 1: one `<file>:<line>: <kind>: <match>` line per problem on stderr,
# then `check: <n> problem(s) found`.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

home_re='/(Users|home)/[A-Za-z0-9._-]+'
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Public addresses the skills name on purpose, one per line.
allowed_emails='cursoragent@cursor.com'

[ $# -gt 0 ] || die "usage: check.sh <path>..."
cd "$(git rev-parse --show-toplevel)" || die "not inside a git repo"

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$@" -type f -not -path '*/.git/*')

problems=()

# scan <kind> <pattern> [<allowed>]: add every hit in the files as
# `<file>:<line>: <kind>: <match>`, except a match listed in <allowed>.
scan() {
  local kind="$1" re="$2" allowed="${3:-}" hit
  [ ${#files[@]} -gt 0 ] || return 0
  while IFS= read -r hit; do
    [ -n "$allowed" ] && printf '%s\n' "$allowed" | grep -qxF -e "${hit#*:*:}" && continue
    problems+=("$(printf '%s' "$hit" | sed -E "s/^([^:]*):([0-9]+):/\1:\2: $kind: /")")
  done < <(grep -nHIoE -e "$re" -- "${files[@]}" || true)
}

scan "home path" "$home_re"
scan "email" "$email_re" "$allowed_emails"

if [ ${#problems[@]} -eq 0 ]; then
  echo "check: clean"
  exit 0
fi
printf '%s\n' "${problems[@]}" >&2
printf 'check: %d problem(s) found\n' "${#problems[@]}" >&2
exit 1
