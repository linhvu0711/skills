#!/usr/bin/env bash
# edit-labels.sh: add a label to an issue, take one off, or both in one
# edit, and make an added label the repo lacks. run-in-t3 and the
# orchestrator write an answer to a Proposal this way.
#
# Usage: edit-labels.sh <owner/repo> <n> [--add <label>] [--remove <label>]
#
# A label the repo lacks is made from label_spec in labels.sh, then the edit
# runs once more. A make that fails because the label exists by then, as
# when a teammate made it a moment before, still runs the edit once more.
#
# Exit 0: `edited`, or `made` when it made the label. Exit 1: `stop:` and
# gh's last line on stderr; the issue is as it was. Exit 64: a wrong command
# line, with the usage after the reason.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=labels.sh
. "$here/labels.sh"
. "$here/../gh.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
usage="usage: edit-labels.sh <owner/repo> <n> [--add <label>] [--remove <label>]"

command -v gh >/dev/null || die "gh is not installed"

[ $# -ge 2 ] || die_usage "$usage"
slug="$1"; n="$2"; shift 2
[[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die_usage "$usage" "first argument must be <owner/repo>, got: $slug"
[[ "$n" =~ ^[0-9]+$ ]] || die_usage "$usage" "an issue is a number, got: $n"
add=""; edit=()
while [ $# -gt 0 ]; do
  case "$1" in
    --add) [ -n "${2:-}" ] || die_usage "$usage" "--add needs a label"; add="$2"; edit+=(--add-label "$2"); shift 2 ;;
    --remove) [ -n "${2:-}" ] || die_usage "$usage" "--remove needs a label"; edit+=(--remove-label "$2"); shift 2 ;;
    *) die_usage "$usage" "unexpected argument: $1" ;;
  esac
done
[ ${#edit[@]} -gt 0 ] || die_usage "$usage" "name --add, --remove, or both"

if gh_out issue edit "$n" --repo "$slug" "${edit[@]}"; then echo edited; exit 0; fi
[ -n "$add" ] && [[ "$err" == *"'$add' not found"* ]] || die "$err"
spec="$(label_spec "$add")"
[ -n "$spec" ] || die "$err"
made=made
if ! gh_out label create "$add" --repo "$slug" --color "$(sed -n 1p <<<"$spec")" --description "$(sed -n 2p <<<"$spec")"; then
  [[ "$err" == *"already exists"* ]] || die "$err"
  made=edited
fi
gh_out issue edit "$n" --repo "$slug" "${edit[@]}" || die "$err"
echo "$made"
