#!/usr/bin/env bash
# Thin Cursor Cloud Agents v1 client for /handoff-cursor. curl + jq only.
#
#   cursor.sh create <prompt-file> --repo <owner/name or URL> [--base REF] [--title T] [--issue URL] [--model ID]
#                                                          -> "<agent_id>\t<url>"
#   cursor.sh status <agent>                               -> agent state, run state, PRs, last message
#   cursor.sh say <agent> <note-file>                      -> sends a follow-up (a new run on the agent)
#   cursor.sh watch <agent> [--repo owner/name --issue N] [--interval S] [--max S] [--follow]
#                                                          -> one line per event; exits when the run ends
#   cursor.sh last [issue-url]                             -> newest agent (for that issue) from the ledger
#   cursor.sh models                                       -> model ids this account can use
#   cursor.sh repos                                        -> repos connected to this account
#
# <agent> is the id with or without the "bc-" prefix, or the app URL.
# The prompt file goes whole into prompt.text: the API has no attachment
# and no documented cap. An agent holds runs: create makes run 1, say
# makes the next. One run at a time; a second one is 409 agent_busy.
# Cursor's git snapshot tracks only the cursor/… branch it opened the
# workspace on, so a PR the agent opens with gh on its own branch never
# shows there. watch with --repo and --issue also asks GitHub for open
# PRs whose head is `<type>/<issue>-…` and reports those.
# Key: ~/.zshrc `export CURSOR_API_KEY=` wins over the env (a rotated key
# leaves a stale value in a running shell). Never printed.
set -euo pipefail

API="${CURSOR_API_URL:-https://api.cursor.com}/v1"
LEDGER="${HOME}/.config/dispatch/cursor-sessions.tsv"
MSG_CHARS=600

die() { echo "cursor.sh: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
cursor.sh create <prompt-file> --repo <owner/name or URL> [--base REF] [--title T] [--issue URL] [--model ID]
cursor.sh status <agent>
cursor.sh say <agent> <note-file>
cursor.sh watch <agent> [--repo owner/name --issue N] [--interval S] [--max S] [--follow]
cursor.sh last [issue-url]
cursor.sh models
cursor.sh repos
EOF
  exit 1
}

key() {
  local k=""
  if [[ -f "$HOME/.zshrc" ]]; then
    k=$(grep -E '^export CURSOR_API_KEY=' "$HOME/.zshrc" | tail -1 \
        | sed -E 's/^export CURSOR_API_KEY="?([^"]*)"?$/\1/')
  fi
  [[ -z "$k" || "$k" == crsr_PASTE* ]] && k="${CURSOR_API_KEY:-}"
  [[ -z "$k" || "$k" == crsr_PASTE* ]] && die "no CURSOR_API_KEY in ~/.zshrc or env (make one at cursor.com/dashboard, API Keys)"
  printf %s "$k"
}

aid() {
  local s="${1:-}"
  [[ -z "$s" ]] && die "agent id required"
  s="${s%%\?*}"                      # drop a query string
  s="${s##*/}"                       # app URL -> id
  [[ "$s" == bc-* ]] || s="bc-$s"
  printf %s "$s"
}

# api METHOD PATH [JSON]  -> body on stdout, dies on non-2xx
api() {
  local method="$1" path="$2" data="${3:-}" out code
  out=$(mktemp)
  if [[ -n "$data" ]]; then
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $(key)" -H 'Content-Type: application/json' \
      -d "$data" "$API$path")
  else
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $(key)" "$API$path")
  fi
  if [[ "$code" != 2* ]]; then
    local why; why=$(jq -r '.error.code // empty' "$out" 2>/dev/null || true)
    local msg; msg=$(jq -r '.error.message // empty' "$out" 2>/dev/null || true)
    rm -f "$out"; die "HTTP $code on $method $path${why:+: $why}${msg:+ ($msg)}"
  fi
  cat "$out"; rm -f "$out"
}

# summary AGENT_JSON RUN_JSON -> "agent<TAB>run<TAB>run_id<TAB>prs<TAB>url<TAB>last message (one line, cut)"
summary() {
  jq -rn --argjson a "$1" --argjson r "$2" --argjson n "$MSG_CHARS" '
    [ ($a.status // "unknown"),
      ($r.status // "none"),
      ($r.id // "-"),
      ( [ $r.git.branches[]? | .prUrl // empty ] | if length == 0 then "-" else join(",") end ),
      ($a.url // ("https://cursor.com/agents/" + ($a.id // ""))),
      ( ($r.result // "-") | gsub("[\r\n]+"; " ") | .[0:$n] )
    ] | @tsv'
}

# fetch AGENT_ID -> summary line for the agent and its latest run
fetch() {
  local id="$1" a rid r='{}'
  a=$(api GET "/agents/$id")
  rid=$(jq -r '.latestRunId // empty' <<<"$a")
  [[ -n "$rid" ]] && r=$(api GET "/agents/$id/runs/$rid")
  summary "$a" "$r"
}

repo_url() {
  local r="$1"
  [[ "$r" == http* ]] || r="https://github.com/$r"
  printf %s "${r%.git}"
}

cmd_create() {
  local file="${1:-}"; shift || true
  local title="" issue="" repo="" base="main" model=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      --repo)  repo="$2"; shift 2 ;;
      --base)  base="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ -s "$file" ]] || die "prompt file missing or empty: $file"
  [[ -n "$repo" ]] || die "--repo owner/name is required"
  repo=$(repo_url "$repo")
  [[ -z "$title" ]] && title=$(head -c 100 "$file" | head -1)
  local body res id url
  body=$(jq -Rs --arg t "${title:0:100}" --arg repo "$repo" --arg base "$base" --arg model "$model" '
    { prompt: { text: . }, name: $t,
      repos: [ { url: $repo, startingRef: $base } ],
      autoCreatePR: false, mode: "agent" }
    + (if $model != "" then { model: { id: $model } } else {} end)' "$file")
  res=$(api POST /agents "$body")
  id=$(jq -r '.agent.id' <<<"$res")
  url=$(jq -r '.agent.url // empty' <<<"$res")
  [[ -z "$url" ]] && url="https://cursor.com/agents/$id"
  mkdir -p "$(dirname "$LEDGER")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$url" "${issue:--}" "${title:0:100}" >>"$LEDGER"
  printf '%s\t%s\n' "$id" "$url"
}

cmd_status() {
  local id; id=$(aid "${1:-}")
  fetch "$id" | while IFS=$'\t' read -r ast rst rid prs url msg; do
    echo "agent: $ast"
    echo "run: $rst ($rid)"
    echo "pr: $prs"
    echo "url: $url"
    echo "cursor: $msg"
  done
}

cmd_say() {
  local id; id=$(aid "${1:-}")
  local file="${2:-}"
  [[ -s "$file" ]] || die "note file missing or empty: $file"
  local res rid
  res=$(api POST "/agents/$id/runs" "$(jq -Rs '{ prompt: { text: . } }' "$file")")
  rid=$(jq -r '.run.id // "-"' <<<"$res")
  echo "sent to $id ($rid)"
}

cmd_watch() {
  local id; id=$(aid "${1:-}"); shift || true
  local interval=60 max=0 follow=0 repo="" issue=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      --max) max="$2"; shift 2 ;;
      --follow) follow=1; shift ;;
      --repo) repo="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ -n "$repo" && -z "$issue" || -z "$repo" && -n "$issue" ]] && die "--repo and --issue go together"
  local start prev_key="" seen=" " line ast rst rid prs url msg p ghprs
  start=$(date +%s)
  while :; do
    if line=$(fetch "$id" 2>/dev/null); then
      IFS=$'\t' read -r ast rst rid prs url msg <<<"$line"
      if [[ "$prs" != "-" ]]; then
        IFS=',' read -ra arr <<<"$prs"
        for p in "${arr[@]}"; do
          case "$seen" in *" $p "*) ;; *) echo "[$(date +%H:%M)] pr $p"; seen="$seen$p " ;; esac
        done
      fi
      if [[ -n "$repo" ]]; then
        ghprs=$(gh pr list -R "$repo" --state all --limit 50 --json url,headRefName \
          -q ".[] | select(.headRefName | test(\"^[a-z]+/${issue}-\")) | .url" 2>/dev/null || true)
        for p in $ghprs; do
          case "$seen" in *" $p "*) ;; *) echo "[$(date +%H:%M)] pr $p"; seen="$seen$p " ;; esac
        done
      fi
      # An event is a run reaching an end state. A follow-up makes a new
      # run, so the key holds the run id too.
      if [[ "$rid|$rst" != "$prev_key" ]]; then
        case "$rst" in
          FINISHED)                echo "[$(date +%H:%M)] finished $url :: $msg" ;;
          ERROR|CANCELLED|EXPIRED) echo "[$(date +%H:%M)] $(tr '[:upper:]' '[:lower:]' <<<"$rst") $url :: $msg" ;;
        esac
        prev_key="$rid|$rst"
      fi
      if (( follow == 0 )); then
        case "$rst" in FINISHED|ERROR|CANCELLED|EXPIRED) exit 0 ;; esac
      fi
    fi
    if (( max > 0 && $(date +%s) - start >= max )); then
      echo "[$(date +%H:%M)] watch stopped after ${max}s, run ${rst:-unknown}"
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

cmd_models() {
  api GET /models | jq -r '.items[] | "\(.id)\t\(.displayName)"'
}

cmd_repos() {
  api GET /repositories | jq -r '.items[].url'
}

for c in curl jq; do command -v "$c" >/dev/null || die "$c is required"; done
case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  status) shift; cmd_status "$@" ;;
  say)    shift; cmd_say "$@" ;;
  watch)  shift; cmd_watch "$@" ;;
  last)   shift; cmd_last "$@" ;;
  models) shift; cmd_models "$@" ;;
  repos)  shift; cmd_repos "$@" ;;
  *) usage ;;
esac
