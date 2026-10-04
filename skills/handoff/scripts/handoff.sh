#!/usr/bin/env bash
# The handoff module: one flow for every executor. curl + jq live in the
# adapters; this file only routes, keeps the ledger, and runs the adapters.
#
#   handoff.sh start <executor> <prompt-file> [--issue URL] [--title T] [adapter options]
#                                                             -> "<session>\t<link>"
#
# <executor> is devin or cursor. Each has an adapter, adapters/<executor>.sh;
# HANDOFF_ADAPTERS names another folder (the tests use a fake one). Options
# start does not know go to the adapter unchanged: devin --platform and
# --mode, cursor --repo, --base, and --model.
# The handoff ledger, ~/.config/dispatch/handoff.tsv, holds a row per session:
# time, executor, session, link, issue, title, tab separated.
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
  mkdir -p "$(dirname "$LEDGER")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$e" "$id" "$link" "${issue:--}" "${title:0:100}" >>"$LEDGER"
  printf '%s\t%s\n' "$id" "$link"
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 1 ;;
esac
