#!/usr/bin/env bash
# Thin Devin v3 client for /handoff-devin. curl + jq only.
#
#   devin.sh create <prompt-file> [--title T] [--issue URL] [--platform P] [--mode M]
#                                                             -> "<session_id>\t<url>"
#   devin.sh status <session>                                 -> state, PR, last Devin message
#   devin.sh say <session> <note-file>                        -> sends a follow-up
#   devin.sh watch <session> [--interval S] [--max S] [--once] -> one line per event; exits on finished/error
#   devin.sh archive <session>                                -> archives the session
#   devin.sh last [issue-url]                                 -> newest session (for that issue) from the ledger
#   devin.sh upload <file>                                    -> attachment URL
#
# <session> is the id with or without the "devin-" prefix, or the app URL.
# --platform picks the VM: linux (default), macos, windows, or an outpost
# pool name. --mode picks the agent mode: normal, fast, lite, ultra, fusion.
# No flag = the org default. A wrong value is a 400 that lists the
# labels the org has.
# create and say never send the file as the prompt: the API caps prompt
# length. They upload it as an attachment and send a short prompt that
# keeps the head lines (everything before the first "# " heading) and
# points at the file with the exact line Devin needs, ATTACHMENT:"<url>".
# Keys: ~/.zshrc `export DEVIN_API_KEY=` (a cog_ service-user key or
# PAT) and `export DEVIN_ORG_ID=` win over the env (a rotated key leaves
# a stale value in a running shell). Optional `export DEVIN_USER_ID=`
# makes a service-user key create sessions as that user. Never printed.
set -euo pipefail

LEDGER="${HOME}/.config/dispatch/sessions.tsv"
MSG_CHARS="${MSG_CHARS:-600}"

die() { echo "devin.sh: $*" >&2; exit 1; }

# zvar NAME -> value from ~/.zshrc, else env, else empty
zvar() {
  local n="$1" v=""
  if [[ -f "$HOME/.zshrc" ]]; then
    v=$(grep -E "^export $n=" "$HOME/.zshrc" | tail -1 \
        | sed -E "s/^export $n=\"?([^\"]*)\"?\$/\1/")
  fi
  [[ -z "$v" ]] && v=$(eval "printf %s \"\${$n:-}\"")
  printf %s "$v"
}

key() {
  local k; k=$(zvar DEVIN_API_KEY)
  [[ -z "$k" ]] && die "no DEVIN_API_KEY in ~/.zshrc or env"
  printf %s "$k"
}

org() {
  local o; o=$(zvar DEVIN_ORG_ID)
  [[ -z "$o" ]] && die "no DEVIN_ORG_ID in ~/.zshrc or env (Devin → Settings → Service Users)"
  printf %s "$o"
}

api_base() { printf '%s/v3/organizations/%s' "${DEVIN_API_URL:-https://api.devin.ai}" "$(org)"; }

sid() {
  local s="${1:-}"
  [[ -z "$s" ]] && die "session id required"
  s="${s##*/}"                       # app URL -> id
  [[ "$s" == devin-* ]] || s="devin-$s"
  printf %s "$s"
}

# api METHOD PATH [JSON]  -> body on stdout, dies on non-2xx
api() {
  local method="$1" path="$2" data="${3:-}" out code
  out=$(mktemp)
  if [[ -n "$data" ]]; then
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $(key)" -H 'Content-Type: application/json' \
      -d "$data" "$(api_base)$path")
  else
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $(key)" "$(api_base)$path")
  fi
  if [[ "$code" != 2* ]]; then
    local why; why=$(jq -r '.detail // .message // .error // empty' "$out" 2>/dev/null || true)
    rm -f "$out"; die "HTTP $code on $method $path${why:+: $why}"
  fi
  cat "$out"; rm -f "$out"
}

# state SESSION-JSON -> one word the watch and status read:
#   working | blocked | finished | error | suspended:<why> | new | claimed | resuming
state() {
  jq -r '
    (.status // "unknown") as $s | (.status_detail // "") as $d |
    if $s == "running" then
      (if $d == "waiting_for_user" or $d == "waiting_for_approval" then "blocked"
       elif $d == "finished" then "finished"
       else "working" end)
    elif $s == "exit" then "finished"
    elif $s == "suspended" then ("suspended" + (if $d != "" then ":" + $d else "" end))
    else $s end'
}

# last_devin ID -> the last Devin message, one line, cut (pages to the end)
last_devin() {
  local id="$1" after="" res msg="-" next
  while :; do
    res=$(api GET "/sessions/$id/messages?first=200${after:+&after=$after}")
    next=$(jq -r '[ .items[] | select(.source == "devin") ] | last | .message // empty' <<<"$res")
    [[ -n "$next" ]] && msg="$next"
    if [[ "$(jq -r '.has_next_page // false' <<<"$res")" == "true" ]]; then
      after=$(jq -r '.end_cursor // empty' <<<"$res"); [[ -z "$after" ]] && break
    else
      break
    fi
  done
  printf %s "$msg" | tr '\r\n' '  ' | head -c "$MSG_CHARS"
}

# summary ID -> "state<TAB>pr<TAB>url<TAB>last devin message"
summary() {
  local id="$1" res st pr url
  res=$(api GET "/sessions/$id")
  st=$(state <<<"$res")
  pr=$(jq -r '.pull_requests[0].pr_url // "-"' <<<"$res")
  url=$(jq -r '.url // ("https://app.devin.ai/sessions/" + (.session_id | ltrimstr("devin-")))' <<<"$res")
  printf '%s\t%s\t%s\t%s\n' "$st" "$pr" "$url" "$(last_devin "$id")"
}

# upload FILE -> attachment URL on stdout
upload() {
  local file="$1" out code url
  [[ -s "$file" ]] || die "file missing or empty: $file"
  out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $(key)" -F "file=@$file" "$(api_base)/attachments")
  if [[ "$code" != 2* ]]; then
    local why; why=$(jq -r '.detail // .message // .error // empty' "$out" 2>/dev/null || true)
    rm -f "$out"; die "HTTP $code on POST /attachments${why:+: $why}"
  fi
  url=$(jq -r 'if type == "string" then . else (.url // empty) end' "$out" 2>/dev/null || true)
  [[ -z "$url" ]] && url=$(tr -d '"[:space:]' <"$out")
  rm -f "$out"
  [[ "$url" == http* ]] || die "no attachment URL in response"
  printf %s "$url"
}

# pointer FILE KIND URL -> the short text Devin gets: head lines, a pointer, the ATTACHMENT line
# The file is referenced once, by that line (docs.devin.ai, "Upload an attachment": Devin
# recognizes attachments only as ATTACHMENT:"<url>" on its own line). The v3 body field
# attachment_urls is not sent as well: sending both made Devin show the same file twice.
pointer() {
  local file="$1" kind="$2" url="$3" head
  head=$(awk '/^# /{exit} {print}' "$file" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
  {
    [[ -n "$head" ]] && printf '%s\n\n' "$head"
    case "$kind" in
      brief) printf 'The full brief is in the attached file. Read it whole before you start; every heading the rules name is in it.\n' ;;
      note)  printf 'The follow-up is in the attached file. Read it whole before you go on.\n' ;;
    esac
    printf 'ATTACHMENT:"%s"\n' "$url"
  }
}

cmd_upload() { upload "${1:-}"; echo; }

cmd_create() {
  local file="${1:-}"; shift || true
  local title="" issue="" platform="" mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    title="$2"; shift 2 ;;
      --issue)    issue="$2"; shift 2 ;;
      --platform) platform="$2"; shift 2 ;;
      --mode)     mode="$2"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ -s "$file" ]] || die "prompt file missing or empty: $file"
  [[ -z "$title" ]] && title=$(head -c 100 "$file" | head -1)
  case "$platform" in ""|linux|default) platform="" ;; esac
  local url body res id surl user
  url=$(upload "$file")
  user=$(zvar DEVIN_USER_ID)
  body=$(pointer "$file" brief "$url" | jq -Rs \
    --arg t "${title:0:100}" --arg u "$url" --arg p "$platform" --arg m "$mode" --arg as "$user" '
    {prompt: ., title: $t, tags: ["dispatch"]}
    + (if $p  != "" then {platform: $p} else {} end)
    + (if $m  != "" then {devin_mode: $m} else {} end)
    + (if $as != "" then {create_as_user_id: $as} else {} end)')
  res=$(api POST /sessions "$body")
  id=$(jq -r '.session_id' <<<"$res")
  surl=$(jq -r '.url // empty' <<<"$res")
  [[ -z "$surl" ]] && surl="https://app.devin.ai/sessions/${id#devin-}"
  mkdir -p "$(dirname "$LEDGER")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$surl" "${issue:--}" "${title:0:100}" >>"$LEDGER"
  printf '%s\t%s\n' "$id" "$surl"
}

cmd_status() {
  local id; id=$(sid "${1:-}")
  summary "$id" | while IFS=$'\t' read -r st pr url msg; do
    echo "state: $st"
    echo "pr: $pr"
    echo "url: $url"
    echo "devin: $msg"
  done
}

cmd_say() {
  local id; id=$(sid "${1:-}")
  local file="${2:-}" url
  [[ -s "$file" ]] || die "note file missing or empty: $file"
  url=$(upload "$file")
  api POST "/sessions/$id/messages" \
    "$(pointer "$file" note "$url" | jq -Rs '{message: .}')" >/dev/null
  echo "sent to $id"
}

cmd_archive() {
  local id; id=$(sid "${1:-}")
  api POST "/sessions/$id/archive" '{}' >/dev/null
  echo "archived $id"
}

cmd_watch() {
  local id; id=$(sid "${1:-}"); shift || true
  local interval=120 max=0 once=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      --max) max="$2"; shift 2 ;;
      --once) once=1; shift ;;
      *) die "unknown option $1" ;;
    esac
  done
  local start prev_key="" prev_pr="-" line st="" pr url msg
  start=$(date +%s)
  while :; do
    if line=$(summary "$id" 2>/dev/null); then
      IFS=$'\t' read -r st pr url msg <<<"$line"
      if [[ "$pr" != "-" && "$pr" != "$prev_pr" ]]; then
        echo "[$(date +%H:%M)] pr $pr"
        prev_pr="$pr"
      fi
      # An event is a new state, or a new Devin message while it waits
      # (a working->blocked round trip can fit inside one interval).
      if [[ "$st|$msg" != "$prev_key" ]]; then
        case "$st" in
          blocked|finished|error|suspended*)
            echo "[$(date +%H:%M)] $st $url :: $msg"
            # --once: exit on the first event, for a caller that only
            # sees the process end (a background shell, not Monitor).
            (( once )) && exit 0
            ;;
        esac
        prev_key="$st|$msg"
      fi
      case "$st" in finished|error) exit 0 ;; esac
    fi
    if (( max > 0 && $(date +%s) - start >= max )); then
      echo "[$(date +%H:%M)] watch stopped after ${max}s, state $st"
      exit 0
    fi
    sleep "$interval"
  done
}

cmd_last() {
  local issue="${1:-}"
  [[ -f "$LEDGER" ]] || die "no ledger at $LEDGER"
  if [[ -n "$issue" ]]; then
    awk -F'\t' -v i="$issue" '$4 == i' "$LEDGER" | tail -1
  else
    tail -1 "$LEDGER"
  fi | awk -F'\t' 'NF { print $2 "\t" $3 "\t" $4 } END { if (!NF && NR == 0) exit 1 }'
}

for c in curl jq; do command -v "$c" >/dev/null || die "$c is required"; done
case "${1:-}" in last|"") ;; *) key >/dev/null; org >/dev/null ;; esac
case "${1:-}" in
  create)  shift; cmd_create "$@" ;;
  status)  shift; cmd_status "$@" ;;
  say)     shift; cmd_say "$@" ;;
  watch)   shift; cmd_watch "$@" ;;
  archive) shift; cmd_archive "$@" ;;
  last)    shift; cmd_last "$@" ;;
  upload)  shift; cmd_upload "$@" ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
