#!/usr/bin/env bash
# The Cursor adapter of the handoff module (scripts/handoff.sh). Thin Cursor
# Cloud Agents v1 client, with curl, jq, and gh. The module keeps the ledger and runs
# the watch.
#
#   cursor.sh start <prompt-file> --repo <owner/name or URL> [--base REF] [--title T] [--model ID]
#                   [--platform linux|macos]               -> "<agent_id>\t<url>"
#   cursor.sh poll <agent> [--repo owner/name --issue N]   -> "<state>\t<run_id>|<run state>\t<prs>\t<url>\t<message>"
#   cursor.sh say <agent> <note-file>                      -> sends a follow-up (a new run on the agent)
#   cursor.sh release <agent>                              -> gives the agent's Mac back once its run ended
#                                                             (mac.sh return); nothing for an agent with no Mac
#   cursor.sh ended <agent>                                -> exit 0 when the latest run ended, 1 while
#                                                             it goes, 2 when the run cannot be read
#   cursor.sh create <body-file> <worker>                  -> starts the agent on a Mac's worker
#   cursor.sh send <agent> <note-file>                     -> posts the note as a new run
#                                                             (mac.sh runs these three inside the rental)
#   cursor.sh facts                                        -> "repo\t<url>" per connected repo, then "model\t<id>\t<name>"
#   cursor.sh interval                                     -> the watch's poll interval, in seconds
#
# <agent> is the id with or without the "bc-" prefix, or the app URL.
# The prompt file goes whole into prompt.text: the API has no attachment
# and no documented cap. An agent holds runs: start makes run 1, say
# makes the next. One run at a time; a second one is 409 agent_busy.
# start stops when the repo is not connected to this account: the agent could
# not clone it. poll's state is finished, error, cancelled, or expired when
# the latest run ended so, else working; the second field is the key of an
# event, so a follow-up's run is a new event.
# Cursor's git snapshot tracks only the cursor/… branch it opened the
# workspace on, so a PR the agent opens with gh on its own branch never
# shows there. poll with --repo and --issue also asks GitHub for PRs in
# any state whose head is `<type>/<issue>-…` and reports those.
# --platform macos runs the agent on a rented Mac with a Cursor worker on it.
# Why: see docs/adr/0047-cursor-macos-runs-use-a-rented-mac.md
# Key: ~/.zshrc `export CURSOR_API_KEY=` wins over the env (a rotated key
# leaves a stale value in a running shell). Never printed.
# A wrong command line: `stop: <why>` when there is one, then the usage lines
# on stderr, exit 64.
set -euo pipefail

API="${CURSOR_API_URL:-https://api.cursor.com}/v1"
MSG_CHARS=600
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MAC="${HANDOFF_MAC:-$here/../mac.sh}"
SELF="$here/$(basename "${BASH_SOURCE[0]}")"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
. "$here/../../../../shared/gh.sh"
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT

usage_text() {
  cat <<'EOF'
cursor.sh start <prompt-file> --repo <owner/name or URL> [--base REF] [--title T] [--model ID] [--platform linux|macos]
cursor.sh poll <agent> [--repo owner/name --issue N]
cursor.sh say <agent> <note-file>
cursor.sh facts
cursor.sh release <agent>
cursor.sh interval
cursor.sh ended <agent>    (mac.sh runs these three)
cursor.sh create <body-file> <worker>
cursor.sh send <agent> <note-file>
EOF
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
  [[ -n "$s" ]] || die_usage "$(usage_text)" "agent id required"
  s="${s%%\?*}"
  s="${s##*/}"
  [[ "$s" == bc-* ]] || s="bc-$s"
  printf %s "$s"
}

# api METHOD PATH [JSON]  -> body on stdout, dies on non-2xx
api() {
  local method="$1" path="$2" data="${3:-}" out code
  out=$(mktemp "$scratch/out.XXXXXX")
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
    die "HTTP $code on $method $path${why:+: $why}${msg:+ ($msg)}"
  fi
  cat "$out"
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

# create_on_mac BODY WORKER -> the create response. The create call to a
# machine agent blocks until its run ends (proven 2026-11-02), so it gets a
# short timeout, and on that timeout the agent is found by its worker's
# name, which no other agent has, see docs/adr/0052-cursor-create-stops-at-20s-and-polls.md
create_on_mac() {
  local body="$1" worker="$2" out code rc=0 i found
  out=$(mktemp "$scratch/out.XXXXXX")
  code=$(curl -sS --max-time 20 -o "$out" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $(key)" -H 'Content-Type: application/json' \
    -d "$body" "$API/agents" 2>/dev/null) || rc=$?
  if [[ $rc -eq 0 && "$code" == 2* ]]; then cat "$out"; return 0; fi
  if [[ $rc -eq 0 ]]; then
    local why; why=$(jq -r '.error.code // empty' "$out" 2>/dev/null || true)
    die "HTTP $code on POST /agents${why:+: $why}"
  fi
  [[ $rc -eq 28 ]] || die "POST /agents failed (curl exit $rc)"
  for i in 1 2 3; do
    found=$(api GET "/agents?limit=20" | jq -c --arg w "$worker" \
      '[.items[] | select(.env.type == "machine" and .env.name == $w)][0] // empty | { agent: . }')
    [[ -n "$found" ]] && { printf '%s\n' "$found"; return 0; }
    sleep 5
  done
  die "POST /agents timed out and no agent runs on worker $worker"
}

repo_url() {
  local r="$1"
  [[ "$r" == http* ]] || r="https://github.com/$r"
  printf %s "${r%.git}"
}

# agent_line CREATE_JSON -> "<agent_id>\t<url>"
agent_line() {
  local id url
  id=$(jq -r '.agent.id' <<<"$1")
  url=$(jq -r '.agent.url // empty' <<<"$1")
  [[ -z "$url" ]] && url="https://cursor.com/agents/$id"
  printf '%s\t%s\n' "$id" "$url"
}

# create BODY_FILE WORKER -> starts the agent on the Mac's worker; mac.sh rent runs it
cmd_create() {
  local res
  [[ -n "${1:-}" && -n "${2:-}" ]] || die_usage "$(usage_text)" "create needs a body file and a worker"
  res=$(create_on_mac "$(cat "$1")" "$2")
  agent_line "$res"
}

cmd_start() {
  local file="${1:-}"; shift || true
  local title="" repo="" base="main" model="" platform=linux
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --repo)  repo="$2"; shift 2 ;;
      --base)  base="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --platform) platform="$2"; shift 2 ;;
      *) die_usage "$(usage_text)" "unknown option $1" ;;
    esac
  done
  case "$platform" in
    linux|macos) ;;
    windows) die "Cursor has no Windows machine: hand this one to devin" ;;
    *) die_usage "$(usage_text)" "--platform must be linux or macos" ;;
  esac
  [[ -s "$file" ]] || die "prompt file missing or empty: $file"
  [[ -n "$repo" ]] || die_usage "$(usage_text)" "--repo owner/name is required"
  repo=$(repo_url "$repo")
  local connected
  connected=$(api GET /repositories | jq -r '.items[].url | sub("\\.git$"; "")')
  grep -qxF "$repo" <<<"$connected" \
    || die "Connect ${repo#https://github.com/} to Cursor first: cursor.com/dashboard, Integrations, GitHub."
  [[ -z "$title" ]] && title=$(head -c 100 "$file" | head -1)
  local body res id url worker="" bf
  [[ "$platform" == macos ]] && worker="ho-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  body=$(jq -Rs --arg t "${title:0:100}" --arg repo "$repo" --arg base "$base" --arg model "$model" --arg w "$worker" '
    { prompt: { text: . }, name: $t,
      repos: [ { url: $repo, startingRef: $base } ],
      autoCreatePR: false, mode: "agent" }
    + (if $model != "" then { model: { id: $model } } else {} end)
    + (if $w != "" then { env: { type: "machine", name: $w } } else {} end)' "$file")
  if [[ -n "$worker" ]]; then
    bf=$(mktemp "$scratch/body.XXXXXX"); printf '%s' "$body" >"$bf"
    res=$(CURSOR_API_KEY="$(key)" bash "$MAC" rent "$worker" "$repo" "$base" -- bash "$SELF" create "$bf" "$worker") \
      || exit 1
    printf '%s\n' "$res"
    return 0
  fi
  res=$(api POST /agents "$body")
  agent_line "$res"
}

cmd_poll() {
  local id; id=$(aid "${1:-}"); shift || true
  local repo="" issue=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      *) die_usage "$(usage_text)" "unknown option $1" ;;
    esac
  done
  [[ -n "$repo" && -z "$issue" || -z "$repo" && -n "$issue" ]] && die_usage "$(usage_text)" "--repo and --issue go together"
  local line ast rst rid prs url msg st ghprs all=" " p arr=() out err
  line=$(fetch "$id")
  IFS=$'\t' read -r ast rst rid prs url msg <<<"$line"
  case "$rst" in
    FINISHED|ERROR|CANCELLED|EXPIRED) st=$(tr '[:upper:]' '[:lower:]' <<<"$rst") ;;
    *) st=working ;;
  esac
  [[ "$prs" != "-" ]] && IFS=',' read -ra arr <<<"$prs"
  if [[ -n "$repo" ]]; then
    gh_or_stop pr list -R "$repo" --state all --limit 50 --json url,headRefName \
      -q ".[] | select(.headRefName | test(\"^[a-z]+/${issue}-\")) | .url"
    ghprs="$out"
    while IFS= read -r p; do [[ -z "$p" ]] || arr+=("$p"); done <<<"$ghprs"
  fi
  for p in ${arr[@]+"${arr[@]}"}; do
    case "$all" in *" $p "*) ;; *) all="$all$p " ;; esac
  done
  all=$(echo $all | tr ' ' ',')
  printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$rid|$rst" "${all:--}" "$url" "$msg"
}

cmd_say() {
  local id; id=$(aid "${1:-}")
  local file="${2:-}"
  [[ -s "$file" ]] || die "note file missing or empty: $file"
  CURSOR_API_KEY="$(key)" bash "$MAC" renew "$id" -- bash "$SELF" send "$id" "$file"
}

# send AGENT NOTE_FILE -> posts the note as a new run; mac.sh renew runs it,
# with MAC_NEW_BASE set when the run is on a new Mac
cmd_send() {
  local id; id=$(aid "${1:-}")
  local file="${2:-}" text res rid
  [[ -s "$file" ]] || die "note file missing or empty: $file"
  text=$(cat "$file")
  if [[ -n "${MAC_NEW_BASE:-}" ]]; then
    text="This run is on a new Mac: the repo is a fresh clone of $MAC_NEW_BASE. Before you change anything, fetch and check out the branch you worked on, and its PR's branch if one is open.

$text"
  fi
  res=$(api POST "/agents/$id/runs" "$(jq -Rn --arg t "$text" '{ prompt: { text: $t } }')")
  rid=$(jq -r '.run.id // "-"' <<<"$res")
  echo "sent to $id ($rid)"
}

cmd_ended() {
  local id; id=$(aid "${1:-}")
  local line rst
  line=$(fetch "$id") || exit 2
  IFS=$'\t' read -r _ rst _ <<<"$line"
  case "$rst" in FINISHED|ERROR|CANCELLED|EXPIRED) return 0 ;; *) return 1 ;; esac
}

cmd_release() {
  local id; id=$(aid "${1:-}")
  CURSOR_API_KEY="$(key)" bash "$MAC" return "$id" -- bash "$SELF" ended "$id"
}

cmd_facts() {
  api GET /repositories | jq -r '.items[] | "repo\t" + (.url | sub("\\.git$"; ""))'
  api GET /models | jq -r '.items[] | "model\t\(.id)\t\(.displayName)"'
}

for c in curl jq; do command -v "$c" >/dev/null || die "$c is required"; done
case "${1:-}" in start|poll|say|facts|release|ended|create|send) key >/dev/null ;; esac
case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  poll)   shift; cmd_poll "$@" ;;
  say)    shift; cmd_say "$@" ;;
  facts)  shift; cmd_facts "$@" ;;
  release) shift; cmd_release "$@" ;;
  ended)  shift; cmd_ended "$@" ;;
  create) shift; cmd_create "$@" ;;
  send)   shift; cmd_send "$@" ;;
  interval) echo 60 ;;
  *) die_usage "$(usage_text)" ;;
esac
