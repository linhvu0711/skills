#!/usr/bin/env bash
# The handoff module: one flow for every executor. curl + jq live in the
# adapters; this file only routes, keeps the ledger, and runs the adapters.
#
#   handoff.sh route <issue-url> [<executor>]                 -> "follow <executor> <session> <link>" or "start <executor>"
#   handoff.sh start <executor> <prompt-file> [--issue URL] [--title T] [adapter options]
#                                                             -> "<session>\t<link>"
#   handoff.sh status <executor> <session> [poll options]     -> state, PR, link, last message
#   handoff.sh say <executor> <session> <note-file>           -> sends a follow-up
#   handoff.sh watch <executor> <session> [--interval S] [--max S] [--once] [--follow] [poll options]
#                                                             -> one line per event; exits when it ends
#
# <executor> is devin or cursor. Each has an adapter, adapters/<executor>.sh;
# HANDOFF_ADAPTERS names another folder (the tests use a fake one). Options
# start does not know go to the adapter unchanged: devin --platform and
# --mode, cursor --repo, --base, and --model.
# The handoff ledger, ~/.config/dispatch/handoff.tsv, holds a row per session:
# time, executor, session, link, issue, title, tab separated.
# Each command first moves in the rows of the old ledgers, sessions.tsv
# (devin) and cursor-sessions.tsv (cursor) in the same folder, and renames
# each to .migrated; a row it cannot read is skipped with a warning.
# route reads it: the issue's newest session, of the named executor when one
# is named, is a follow-up; no session starts on the named executor, else
# devin. status asks the adapter's poll, one line of state, event key, PRs,
# link, and message, tab separated. watch polls until the session ends:
# `pr <url>` once per PR, and `<state> <link> :: <message>` when it blocks,
# finishes, errors, is cancelled, expires, or is suspended. --once exits on
# the first event, for a caller that only sees the process end; --follow
# keeps going past the end, for a session that gets a follow-up. At --max
# seconds it prints `still running <link>`. A failed poll is tried again; after
# three in a row it prints `poll failed <link> :: <the adapter's error>` and
# exits 1. The interval defaults to 120s for
# devin and 60s for cursor. start on an issue that only another executor has prints
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

# migrate -> moves each old per-tool ledger into the ledger, sorted by time, and
# renames it to .migrated, or appends it to a .migrated already there (the
# old skills write their file again until #84 removes them). Each old file is
# renamed aside, to a new <file>.taking.<suffix>, before it is read, so a row
# an old skill appends meanwhile lands in a new old file, which the next run
# moves in. A .taking file a stopped run left behind is moved in too, and a
# row the ledger already holds is not written twice.
migrate() {
  local dir old pair tmp t taken=()
  dir=$(dirname "$LEDGER")
  for pair in devin:sessions.tsv cursor:cursor-sessions.tsv; do
    old="$dir/${pair#*:}"
    # mktemp makes a name no other file has, so a .taking file a stopped run
    # left behind is never overwritten.
    if [[ -f "$old" ]]; then
      t=$(mktemp "$old.taking.XXXXXX")
      mv "$old" "$t" 2>/dev/null || rm -f "$t"
    fi
    for t in "$old".taking.*; do
      [[ -f "$t" ]] && taken+=("${pair%%:*}:$t")
    done
  done
  [[ ${#taken[@]} -gt 0 ]] || return 0
  tmp=$(mktemp "$dir/.handoff.XXXXXX")
  {
    [[ -f "$LEDGER" ]] && cat "$LEDGER"
    for pair in "${taken[@]}"; do
      t="${pair#*:}"
      # No {n} intervals: mawk, the awk on Ubuntu, may not read them.
      awk -F'\t' -v e="${pair%%:*}" -v f="$(basename "${t%.taking.*}")" '
        NF == 0 { next }
        NF == 5 && $2 != "" && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ {
          print $1 "\t" e "\t" $2 "\t" $3 "\t" $4 "\t" $5; next }
        { printf "handoff.sh: skipped line %d of %s: not a session row\n", FNR, f > "/dev/stderr" }' "$t"
    done
  } | awk '!seen[$0]++' | sort -s -t "$(printf '\t')" -k1,1 >"$tmp"
  mv "$tmp" "$LEDGER"
  for pair in "${taken[@]}"; do
    t="${pair#*:}"; old="${t%.taking.*}"
    [[ -f "$t" ]] || continue
    if [[ -f "$old.migrated" ]]; then
      cat "$t" >>"$old.migrated" && rm "$t"
    else
      mv "$t" "$old.migrated"
    fi
  done
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

cmd_status() {
  local e; e=$(executor "${1:-}"); shift || true
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "session id required"
  local line st key prs link msg
  line=$(adapter "$e" poll "$id" "$@") || exit 1
  IFS=$'\t' read -r st key prs link msg <<<"$line"
  echo "state: $st"
  echo "pr: $prs"
  echo "link: $link"
  echo "message: $msg"
}

cmd_say() {
  local e; e=$(executor "${1:-}")
  local id="${2:-}" file="${3:-}"
  [[ -n "$id" ]] || die "session id required"
  [[ -s "$file" ]] || die "note file missing or empty: $file"
  adapter "$e" say "$id" "$file"
}

cmd_watch() {
  local e; e=$(executor "${1:-}"); shift || true
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "session id required"
  local interval=60 max=0 once=0 follow=0 opts=()
  [[ "$e" == devin ]] && interval=120
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      --max) max="$2"; shift 2 ;;
      --once) once=1; shift ;;
      --follow) follow=1; shift ;;
      *) opts+=("$1"); shift ;;
    esac
  done
  local start prev_key="" seen=" " last_link="$id" line st key prs link msg p arr errf fails=0
  errf=$(mktemp); trap "rm -f '$errf'" EXIT
  start=$(date +%s)
  while :; do
    if ! line=$(adapter "$e" poll "$id" ${opts[@]+"${opts[@]}"} 2>"$errf"); then
      # One failure is often the network; three in a row is a key, a
      # session, or an outage the caller has to see.
      fails=$((fails + 1))
      if (( fails >= 3 )); then
        echo "[$(date +%H:%M)] poll failed $last_link :: $(tail -1 "$errf")"
        exit 1
      fi
    else
      fails=0
      IFS=$'\t' read -r st key prs link msg <<<"$line"
      last_link="$link"
      if [[ "$prs" != "-" ]]; then
        IFS=',' read -ra arr <<<"$prs"
        for p in "${arr[@]}"; do
          case "$seen" in
            *" $p "*) ;;
            *) echo "[$(date +%H:%M)] pr $p"; seen="$seen$p "; (( once )) && exit 0 ;;
          esac
        done
      fi
      # An event is a new key in a state the caller acts on. The adapter
      # makes the key, so a new message or a new run counts as new.
      if [[ "$key" != "$prev_key" ]]; then
        case "$st" in
          blocked|finished|error|cancelled|expired|suspended*)
            echo "[$(date +%H:%M)] $st $link :: $msg"
            (( once )) && exit 0
            ;;
        esac
        prev_key="$key"
      fi
      if (( follow == 0 )); then
        case "$st" in finished|error|cancelled|expired) exit 0 ;; esac
      fi
    fi
    if (( max > 0 && $(date +%s) - start >= max )); then
      echo "[$(date +%H:%M)] still running $last_link"
      exit 0
    fi
    sleep "$interval"
  done
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

migrate
case "${1:-}" in
  route) shift; cmd_route "$@" ;;
  start) shift; cmd_start "$@" ;;
  status) shift; cmd_status "$@" ;;
  say)   shift; cmd_say "$@" ;;
  watch) shift; cmd_watch "$@" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 1 ;;
esac
