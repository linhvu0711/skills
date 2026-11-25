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
#   handoff.sh facts <executor>                               -> one fact a line: repo, model, or mode
#   handoff.sh release <session>                              -> frees what the session holds
#
# <executor> is the name of an adapter file, adapters/<executor>.sh: devin and
# cursor now. A new file there is a new executor. HANDOFF_ADAPTERS names
# another folder (the tests use a fake one). Options
# start does not know go to the adapter unchanged: devin --platform and
# --mode, cursor --repo, --base, --model, and --platform.
# The handoff ledger, ~/.config/dispatch/handoff.tsv, holds a row per session:
# time, executor, session, link, issue, title, tab separated.
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
# exits 1. Each line a working poll writes on stderr is printed too, stamped.
# When a run ends, watch runs the adapter's release, on each poll until it
# works, and prints its stderr lines stamped, such as a Mac it could not give
# back; status never does. The interval is the
# adapter's `interval`. start on an issue that only another executor has prints
# "#<n> already has a <executor> session" on stderr and starts anyway.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
ADAPTERS="${HANDOFF_ADAPTERS:-$here/adapters}"
LEDGER="${HOME}/.config/dispatch/handoff.tsv"
DEFAULT_EXECUTOR=devin

die() { echo "handoff.sh: $*" >&2; exit 1; }

# executor NAME -> NAME, or dies naming the executors the adapter files give,
# the default first
executor() {
  if [[ "${1:-}" =~ ^[a-z0-9-]+$ && -f "$ADAPTERS/$1.sh" ]]; then
    printf %s "$1"; return 0
  fi
  local f n names=("$DEFAULT_EXECUTOR") list
  for f in "$ADAPTERS"/*.sh; do
    n=$(basename "$f" .sh)
    [[ "$n" == "$DEFAULT_EXECUTOR" ]] || names+=("$n")
  done
  case ${#names[@]} in
    1) list="${names[0]}" ;;
    2) list="${names[0]} or ${names[1]}" ;;
    *) list=$(printf '%s, ' "${names[@]:0:${#names[@]}-1}"); list="${list}or ${names[${#names[@]}-1]}" ;;
  esac
  die "executor must be $list"
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

cmd_facts() {
  local e; e=$(executor "${1:-}")
  adapter "$e" facts
}

cmd_watch() {
  local e; e=$(executor "${1:-}"); shift || true
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "session id required"
  local interval="" max=0 once=0 follow=0 opts=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      --max) max="$2"; shift 2 ;;
      --once) once=1; shift ;;
      --follow) follow=1; shift ;;
      *) opts+=("$1"); shift ;;
    esac
  done
  [[ -n "$interval" ]] || interval=$(adapter "$e" interval)
  local start prev_key="" seen=" " last_link="$id" line st key prs link msg p arr errf relf fails=0 w freed=""
  errf=$(mktemp); relf=$(mktemp); trap "rm -f '$errf' '$relf'" EXIT
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
      # A poll that works can still warn, as of a Mac it could not give back;
      # the chat reads only this output, so the warning goes there.
      while IFS= read -r w; do
        if [[ -n "$w" ]]; then echo "[$(date +%H:%M)] $w"; fi
      done <"$errf"
      IFS=$'\t' read -r st key prs link msg <<<"$line"
      last_link="$link"
      # A run that ended gives back what the session holds before any line
      # prints, a PR line too, since --once exits on it: a chat that answers
      # the line finds it back. A release that fails is tried again on the
      # next poll of the same run, while the watch goes on.
      case "$st" in
        finished|error|cancelled|expired)
          if [[ "$key" != "$freed" ]]; then
            if adapter "$e" release "$id" >/dev/null 2>"$relf"; then freed="$key"; fi
            while IFS= read -r w; do
              if [[ -n "$w" ]]; then echo "[$(date +%H:%M)] $w"; fi
            done <"$relf"
          fi
          ;;
      esac
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

# release SESSION: the executor is the one of the session's newest ledger row
cmd_release() {
  local s="${1:-}" row e id
  [[ -n "$s" ]] || die "session id required"
  [[ -f "$LEDGER" ]] && row=$(awk -F'\t' -v s="$s" '$3 == s || $4 == s' "$LEDGER" | tail -1)
  [[ -n "${row:-}" ]] || die "no session $s in the ledger"
  IFS=$'\t' read -r _ e id _ <<<"$row"
  adapter "$(executor "$e")" release "$id"
}

cmd_route() {
  local issue="${1:-}" e="" row
  [[ -n "$issue" ]] || die "issue URL required"
  [[ -n "${2:-}" ]] && e=$(executor "$2")
  row=$(newest "$issue" "$e")
  if [[ -n "$row" ]]; then
    awk -F'\t' '{ print "follow " $2 " " $3 " " $4 }' <<<"$row"
  else
    echo "start ${e:-$DEFAULT_EXECUTOR}"
  fi
}

case "${1:-}" in
  route) shift; cmd_route "$@" ;;
  start) shift; cmd_start "$@" ;;
  status) shift; cmd_status "$@" ;;
  say)   shift; cmd_say "$@" ;;
  watch) shift; cmd_watch "$@" ;;
  facts) shift; cmd_facts "$@" ;;
  release) shift; cmd_release "$@" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 1 ;;
esac
