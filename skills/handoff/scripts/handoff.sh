#!/usr/bin/env bash
# The handoff module: one flow for every executor. curl + jq live in the
# adapters; this file only routes, keeps the ledger, and runs the adapters.
#
#   handoff.sh route <issue-url> [<executor>]                 -> "follow <executor> <session> <link>" or "start <executor>"
#   handoff.sh start <executor> <prompt-file> [--issue URL] [--title T] [adapter options]
#                                                             -> "<session>\t<link>"
#
# <executor> is devin or cursor. Each has an adapter, adapters/<executor>.sh;
# HANDOFF_ADAPTERS names another folder (the tests use a fake one). Options
# start does not know go to the adapter unchanged: devin --platform and
# --mode, cursor --repo, --base, and --model.
# The handoff ledger, ~/.config/dispatch/handoff.tsv, holds a row per session:
# time, executor, session, link, issue, title, tab separated.
# route reads it: the issue's newest session, of the named executor when one
# is named, is a follow-up; no session starts on the named executor, else
# devin. start on an issue that only another executor has prints
# "#<n> already has a <executor> session" on stderr and starts anyway.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
ADAPTERS="${HANDOFF_ADAPTERS:-$here/adapters}"
LEDGER="${HOME}/.config/dispatch/handoff.tsv"

die() { echo "handoff.sh: $*" >&2; exit 1; }

# executor NAME -> NAME, or dies when no adapter has that name
executor() {
  case "${1:-}" in
    devin|cursor) printf %s "$1" ;;
    *) die "executor must be devin or cursor" ;;
  esac
}

# newest ISSUE [EXECUTOR] -> the ledger's newest row for that issue, of that executor when given
newest() {
  [[ -f "$LEDGER" ]] || return 0
  awk -F'\t' -v i="$1" -v e="${2:-}" '$5 == i && (e == "" || $2 == e)' "$LEDGER" | tail -1
}

# adapter EXECUTOR VERB [ARGS] -> runs that executor's adapter
adapter() { local e="$1"; shift; bash "$ADAPTERS/$e.sh" "$@"; }

cmd_start() {
  local e; e=$(executor "${1:-}"); shift || true
  local file="${1:-}"; shift || true
  local title="" issue="" rest=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      *) rest+=("$1"); shift ;;
    esac
  done
  [[ -s "$file" ]] || die "prompt file missing or empty: $file"
  [[ -z "$title" ]] && title=$(head -c 100 "$file" | head -1)
  local line id link
  line=$(adapter "$e" start "$file" --title "$title" ${rest[@]+"${rest[@]}"}) || exit 1
  IFS=$'\t' read -r id link <<<"$line"
  if [[ -n "$issue" && -z "$(newest "$issue" "$e")" ]]; then
    local other; other=$(newest "$issue" | cut -f2)
    [[ -n "$other" ]] && echo "#${issue##*/} already has a $other session" >&2
  fi
  mkdir -p "$(dirname "$LEDGER")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$e" "$id" "$link" "${issue:--}" "${title:0:100}" >>"$LEDGER"
  printf '%s\t%s\n' "$id" "$link"
}

cmd_route() {
  local issue="${1:-}" e="" row
  [[ -n "$issue" ]] || die "issue URL required"
  [[ -n "${2:-}" ]] && e=$(executor "$2")
  row=$(newest "$issue" "$e")
  if [[ -n "$row" ]]; then
    awk -F'\t' '{ print "follow " $2 " " $3 " " $4 }' <<<"$row"
  else
    echo "start ${e:-devin}"
  fi
}

case "${1:-}" in
  route) shift; cmd_route "$@" ;;
  start) shift; cmd_start "$@" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 1 ;;
esac
