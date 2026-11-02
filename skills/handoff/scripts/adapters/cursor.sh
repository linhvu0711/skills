#!/usr/bin/env bash
# The Cursor adapter of the handoff module (scripts/handoff.sh). Thin Cursor
# Cloud Agents v1 client, curl + jq only. The module keeps the ledger and runs
# the watch.
#
#   cursor.sh start <prompt-file> --repo <owner/name or URL> [--base REF] [--title T] [--model ID]
#                   [--platform linux|macos]               -> "<agent_id>\t<url>"
#   cursor.sh poll <agent> [--repo owner/name --issue N]   -> "<state>\t<run_id>|<run state>\t<prs>\t<url>\t<message>"
#   cursor.sh say <agent> <note-file>                      -> sends a follow-up (a new run on the agent)
#   cursor.sh down <agent>                                 -> destroys the agent's Mac, if one runs
#   cursor.sh models                                       -> model ids this account can use
#   cursor.sh repos                                        -> repos connected to this account
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
# shows there. poll with --repo and --issue also asks GitHub for open
# PRs whose head is `<type>/<issue>-…` and reports those.
# --platform macos runs the agent on a Namespace Mac (scripts/mac.sh) with a Cursor
# worker on it, as a My Machines agent; Cursor's own machines are Ubuntu only.
# The Mac lives for one run: poll destroys it when the latest run ends, and
# say rents a new one before it sends, whose worker takes the first worker's
# name and ID: Cursor sends an agent's runs to the worker ID it first ran on.
# The rows, agent, worker, worker ID, repo, base, and Mac (`-` when none),
# sit in ~/.config/dispatch/cursor-macs.tsv. A worker refuses a grok_ key, so a
# Mac needs a personal crsr_ key. --platform windows stops: Devin has one.
# Key: ~/.zshrc `export CURSOR_API_KEY=` wins over the env (a rotated key
# leaves a stale value in a running shell). Never printed.
set -euo pipefail

API="${CURSOR_API_URL:-https://api.cursor.com}/v1"
MSG_CHARS=600
MAC="${HANDOFF_MAC:-$(cd "$(dirname "$0")/.." && pwd -P)/mac.sh}"
MACS="$HOME/.config/dispatch/cursor-macs.tsv"

die() { echo "cursor.sh: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
cursor.sh start <prompt-file> --repo <owner/name or URL> [--base REF] [--title T] [--model ID] [--platform linux|macos]
cursor.sh poll <agent> [--repo owner/name --issue N]
cursor.sh say <agent> <note-file>
cursor.sh down <agent>
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

# mac_row AGENT -> "worker<TAB>worker id<TAB>repo<TAB>base<TAB>mac" of a Mac agent, or nothing
mac_row() {
  [[ -f "$MACS" ]] || return 0
  awk -F'\t' -v a="$1" '$1 == a { r = $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 } END { if (r != "") print r }' "$MACS"
}

# mac_set AGENT WORKER WID REPO BASE MAC -> writes the agent's row, replacing an older one
mac_set() {
  local tmp
  mkdir -p "$(dirname "$MACS")"; touch "$MACS"
  tmp=$(mktemp "$MACS.XXXXXX")
  awk -F'\t' -v a="$1" '$1 != a' "$MACS" >"$tmp"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$tmp"
  mv "$tmp" "$MACS"
}

# mac_clear AGENT MAC -> marks the agent as having no Mac, only while its row
# still names MAC: a say that rented a newer Mac meanwhile keeps its row.
mac_clear() {
  local row w wid r b mac
  row=$(mac_row "$1")
  [[ -n "$row" ]] || return 0
  IFS=$'\t' read -r w wid r b mac <<<"$row"
  [[ "$mac" == "$2" ]] && mac_set "$1" "$w" "$wid" "$r" "$b" -
  return 0
}

# mac_up WORKER REPO BASE [WID] -> "<mac>\t<worker id>"; the key goes in the environment
mac_up() { CURSOR_API_KEY="$(key)" bash "$MAC" up "$@"; }

# mac_key_check -> dies when the key cannot run a worker
mac_key_check() {
  [[ "$(key)" == grok_* ]] && die "a Mac worker refuses grok_ keys: put a personal crsr_ key in CURSOR_API_KEY"
  return 0
}

# create_on_mac BODY WORKER -> the create response. The create call to a
# machine agent blocks until its run ends (proven 2026-11-02), so it gets a
# short timeout, and on that timeout the agent is found by its worker's
# name, which no other agent has.
create_on_mac() {
  local body="$1" worker="$2" out code rc=0 i found
  out=$(mktemp)
  code=$(curl -sS --max-time 20 -o "$out" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $(key)" -H 'Content-Type: application/json' \
    -d "$body" "$API/agents" 2>/dev/null) || rc=$?
  if [[ $rc -eq 0 && "$code" == 2* ]]; then cat "$out"; rm -f "$out"; return 0; fi
  if [[ $rc -eq 0 ]]; then
    local why; why=$(jq -r '.error.code // empty' "$out" 2>/dev/null || true)
    rm -f "$out"; die "HTTP $code on POST /agents${why:+: $why}"
  fi
  rm -f "$out"
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
      *) die "unknown option $1" ;;
    esac
  done
  case "$platform" in
    linux|macos) ;;
    windows) die "Cursor has no Windows machine: hand this one to devin" ;;
    *) die "--platform must be linux or macos" ;;
  esac
  [[ -s "$file" ]] || die "prompt file missing or empty: $file"
  [[ -n "$repo" ]] || die "--repo owner/name is required"
  [[ "$platform" == macos ]] && mac_key_check
  repo=$(repo_url "$repo")
  local connected
  connected=$(api GET /repositories | jq -r '.items[].url | sub("\\.git$"; "")')
  grep -qxF "$repo" <<<"$connected" \
    || die "Connect ${repo#https://github.com/} to Cursor first: cursor.com/dashboard, Integrations, GitHub."
  [[ -z "$title" ]] && title=$(head -c 100 "$file" | head -1)
  local body res id url worker="" mac="" wid="" up
  [[ "$platform" == macos ]] && worker="ho-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  body=$(jq -Rs --arg t "${title:0:100}" --arg repo "$repo" --arg base "$base" --arg model "$model" --arg w "$worker" '
    { prompt: { text: . }, name: $t,
      repos: [ { url: $repo, startingRef: $base } ],
      autoCreatePR: false, mode: "agent" }
    + (if $model != "" then { model: { id: $model } } else {} end)
    + (if $w != "" then { env: { type: "machine", name: $w } } else {} end)' "$file")
  if [[ -n "$worker" ]]; then
    up=$(mac_up "$worker" "$repo" "$base") || die "no Mac for the agent"
    IFS=$'\t' read -r mac wid <<<"$up"
    res=$(create_on_mac "$body" "$worker") \
      || { bash "$MAC" down "$mac" >/dev/null 2>&1 || true; exit 1; }
  else
    res=$(api POST /agents "$body")
  fi
  id=$(jq -r '.agent.id' <<<"$res")
  [[ -n "$worker" ]] && mac_set "$id" "$worker" "$wid" "$repo" "$base" "$mac"
  url=$(jq -r '.agent.url // empty' <<<"$res")
  [[ -z "$url" ]] && url="https://cursor.com/agents/$id"
  printf '%s\t%s\n' "$id" "$url"
}

cmd_poll() {
  local id; id=$(aid "${1:-}"); shift || true
  local repo="" issue=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ -n "$repo" && -z "$issue" || -z "$repo" && -n "$issue" ]] && die "--repo and --issue go together"
  local line ast rst rid prs url msg st ghprs all=" " p arr=() row
  # The row is read before the run state: a Mac a say rents after this read
  # is not in it, so an ended run read here never frees a Mac newer than it.
  row=$(mac_row "$id")
  line=$(fetch "$id")
  IFS=$'\t' read -r ast rst rid prs url msg <<<"$line"
  case "$rst" in
    FINISHED|ERROR|CANCELLED|EXPIRED) st=$(tr '[:upper:]' '[:lower:]' <<<"$rst") ;;
    *) st=working ;;
  esac
  [[ "$prs" != "-" ]] && IFS=',' read -ra arr <<<"$prs"
  if [[ -n "$repo" ]]; then
    ghprs=$(gh pr list -R "$repo" --state all --limit 50 --json url,headRefName \
      -q ".[] | select(.headRefName | test(\"^[a-z]+/${issue}-\")) | .url" 2>/dev/null || true)
    for p in $ghprs; do arr+=("$p"); done
  fi
  for p in ${arr[@]+"${arr[@]}"}; do
    case "$all" in *" $p "*) ;; *) all="$all$p " ;; esac
  done
  all=$(echo $all | tr ' ' ',')
  # 1A: a Mac lives for one run. The run that ends frees it; say rents the next.
  local mac
  if [[ -n "$row" && "$st" != working ]]; then
    IFS=$'\t' read -r _ _ _ _ mac <<<"$row"
    if [[ "$mac" != "-" ]]; then
      bash "$MAC" down "$mac" >/dev/null 2>&1 || true
      mac_clear "$id" "$mac"
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$rid|$rst" "${all:--}" "$url" "$msg"
}

cmd_say() {
  local id; id=$(aid "${1:-}")
  local file="${2:-}"
  [[ -s "$file" ]] || die "note file missing or empty: $file"
  local res rid row w wid r b mac up text new=""
  text=$(cat "$file")
  row=$(mac_row "$id")
  if [[ -n "$row" ]]; then
    IFS=$'\t' read -r w wid r b mac <<<"$row"
    if ! bash "$MAC" alive "$mac" 2>/dev/null; then
      mac_key_check
      [[ "$mac" != "-" ]] && { bash "$MAC" down "$mac" >/dev/null 2>&1 || true; }
      up=$(mac_up "$w" "$r" "$b" "$wid") || die "no Mac for the agent"
      IFS=$'\t' read -r new _ <<<"$up"
      text="This run is on a new Mac: the repo is a fresh clone of $b. Before you change anything, fetch and check out the branch you worked on, and its PR's branch if one is open.

$text"
    fi
  fi
  res=$(api POST "/agents/$id/runs" "$(jq -Rn --arg t "$text" '{ prompt: { text: $t } }')") \
    || { [[ -n "$new" ]] && bash "$MAC" down "$new" >/dev/null 2>&1; exit 1; }
  # Only now, with the new run the latest, may a poll see the new Mac: one
  # that saw it next to the ended run before would destroy it.
  [[ -n "$new" ]] && mac_set "$id" "$w" "$wid" "$r" "$b" "$new"
  rid=$(jq -r '.run.id // "-"' <<<"$res")
  echo "sent to $id ($rid)"
}

cmd_down() {
  local id; id=$(aid "${1:-}")
  local row w wid r b mac
  row=$(mac_row "$id")
  [[ -n "$row" ]] || die "$id has no Mac"
  IFS=$'\t' read -r w wid r b mac <<<"$row"
  if [[ "$mac" == "-" ]]; then echo "$id: no Mac running"; return 0; fi
  bash "$MAC" down "$mac" >/dev/null 2>&1 || true
  mac_set "$id" "$w" "$wid" "$r" "$b" -
  echo "$id: destroyed $mac"
}

cmd_models() {
  api GET /models | jq -r '.items[] | "\(.id)\t\(.displayName)"'
}

cmd_repos() {
  api GET /repositories | jq -r '.items[].url'
}

for c in curl jq; do command -v "$c" >/dev/null || die "$c is required"; done
case "${1:-}" in start|poll|say|down|models|repos) key >/dev/null ;; esac
case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  poll)   shift; cmd_poll "$@" ;;
  say)    shift; cmd_say "$@" ;;
  down)   shift; cmd_down "$@" ;;
  models) shift; cmd_models "$@" ;;
  repos)  shift; cmd_repos "$@" ;;
  *) usage ;;
esac
