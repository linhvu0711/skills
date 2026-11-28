#!/usr/bin/env bash
# edit-labels.sh: add a label to an issue, take one off, or both in one
# edit, and make an added label the repo lacks. run-in-t3 and the
# orchestrator write an answer to a Proposal this way.
#
# Usage: edit-labels.sh <owner/repo> <n> [--add <label>] [--remove <label>]
#
# When the edit fails, a lookup of the label tells why: a 404 means the repo
# lacks it, so it is made from label_spec in labels.sh and the edit runs once
# more. A make that fails while a second lookup finds the label, as when a
# teammate made it a moment before, still runs the edit once more.
#
# Exit 0: `edited`, or `made` when it made the label. Exit 1: `stop:` and
# gh's last line on stderr; the issue is as it was. Exit 64: a wrong command
# line, with the usage after the reason.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=labels.sh
. "$here/labels.sh"
. "$here/../gh.sh"
. "$here/../die.sh"
# gh reads --add-label and --remove-label as a CSV row, so a raw `Size, Small`
# is two labels. The q variable keeps the replace safe on macOS Bash 3.2.
csv_field() { local q='"'; printf '"%s"' "${1//$q/$q$q}"; }
usage="usage: edit-labels.sh <owner/repo> <n> [--add <label>] [--remove <label>]"

command -v gh >/dev/null || die "gh is not installed"
command -v jq >/dev/null || die "jq is not installed"

[ $# -ge 2 ] || die_usage "$usage"
slug="$1"; n="$2"; shift 2
[[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die_usage "$usage" "first argument must be <owner/repo>, got: $slug"
[[ "$n" =~ ^[0-9]+$ ]] || die_usage "$usage" "an issue is a number, got: $n"
add=""; edit=()
while [ $# -gt 0 ]; do
  case "$1" in
    --add) [ -n "${2:-}" ] || die_usage "$usage" "--add needs a label"; add="$2"; edit+=(--add-label "$(csv_field "$2")"); shift 2 ;;
    --remove) [ -n "${2:-}" ] || die_usage "$usage" "--remove needs a label"; edit+=(--remove-label "$(csv_field "$2")"); shift 2 ;;
    *) die_usage "$usage" "unexpected argument: $1" ;;
  esac
done
[ ${#edit[@]} -gt 0 ] || die_usage "$usage" "name --add, --remove, or both"

if gh_out issue edit "$n" --repo "$slug" "${edit[@]}"; then echo edited; exit 0; fi
[ -n "$add" ] || die "$err"
edit_err="$err"
label_path="repos/$slug/labels/$(jq -rn --arg l "$add" '$l | @uri')"
if gh_out api "$label_path"; then die "$edit_err"; fi
[ "$status" = 404 ] || die "$err"
spec="$(label_spec "$add")"
[ -n "$spec" ] || die "$edit_err"
made=made
if ! gh_out label create "$add" --repo "$slug" --color "$(sed -n 1p <<<"$spec")" --description "$(sed -n 2p <<<"$spec")"; then
  create_err="$err"
  gh_out api "$label_path" || die "$create_err"
  made=edited
fi
gh_out issue edit "$n" --repo "$slug" "${edit[@]}" || die "$err"
echo "$made"
