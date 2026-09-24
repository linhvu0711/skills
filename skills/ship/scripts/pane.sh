#!/usr/bin/env bash
# pane.sh: open a herdr pane in a worktree, start the Devin CLI there, and
# hand it the prompt file. Placement and retry logic follow kickoff.sh.
#
#   pane.sh <worktree> <label> <prompt-file> [--model M] [--mode P] [--dry-run]
#
# Defaults: model swe-2-medium, permission mode dangerous. The label names
# the herdr agent; made unique among live agents. The first prompt is one
# line that points at the file; the agent reads it whole.
#
# Exit 0: one report line on stdout, ending in `PANE=<id> AGENT=<label>`.
# Exit 1: `stop: <why>` as the last stderr line. No pane exists until every
# check passed; a pane that exists but did not start stays for a look.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*" >&2; }

model="swe-2-medium"; mode="dangerous"; dry=0; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -*) die "unknown flag $1" ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -eq 3 ] || die "usage: pane.sh <worktree> <label> <prompt-file> [--model M] [--mode P] [--dry-run]"
wt="${args[0]}"; label="${args[1]}"; prompt="${args[2]}"

[ -f "$wt/.git" ] || [ -d "$wt/.git" ] || die "$wt is not a git worktree"
[ -f "$prompt" ] || die "prompt file not found: $prompt"
prompt="$(cd "$(dirname "$prompt")" && pwd)/$(basename "$prompt")"
[ "${HERDR_ENV:-}" = 1 ] || die "not inside herdr"
command -v devin >/dev/null || die "devin CLI not on PATH"
devin auth status 2>&1 | grep -q 'Logged in' || die "devin CLI is not logged in; run: devin auth login"
label="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[^a-z]+//; s/[^a-z0-9_-]//g' | cut -c1-32)"
[ -n "$label" ] || die "label is empty after cleaning"

ws="${HERDR_WORKSPACE_ID:?}"; my_tab="${HERDR_TAB_ID:?}"

live="$(herdr agent list | jq -r '.result.agents[].name // empty')"
if grep -qx "$label" <<<"$live"; then
  n=2; while grep -qx "${label}-${n}" <<<"$live"; do n=$((n+1)); done
  label="${label}-${n}"
fi

panes_json="$(herdr pane list --workspace "$ws")"
tab_ids="$(herdr tab list --workspace "$ws" | jq -r '.result.tabs[].tab_id')"

columns_of() {  # prints "<count> <rightmost pane id>" for a tab
  local any
  any="$(jq -r --arg t "$1" '[.result.panes[] | select(.tab_id==$t)][0].pane_id // empty' <<<"$panes_json")"
  [ -n "$any" ] || { echo "0 "; return; }
  herdr pane layout --pane "$any" | jq -r '.result.layout.panes
    | ([.[].rect.x] | unique | length) as $n
    | (max_by(.rect.x).pane_id) as $r
    | "\($n) \($r)"'
}

target_tab=""; split_pane=""
read -r n r <<<"$(columns_of "$my_tab")"
if [ "$n" -gt 0 ] && [ "$n" -lt 3 ]; then target_tab="$my_tab"; split_pane="$r"; fi
if [ -z "$target_tab" ]; then
  best=9
  for t in $tab_ids; do
    [ "$t" = "$my_tab" ] && continue
    read -r n r <<<"$(columns_of "$t")"
    if [ "$n" -gt 0 ] && [ "$n" -lt 3 ] && [ "$n" -lt "$best" ]; then best=$n; target_tab="$t"; split_pane="$r"; fi
  done
fi

first_prompt="Read $prompt whole and follow it. It is your task and your rules. Work in $wt."

if [ "$dry" -eq 1 ]; then
  place="new tab"; [ -n "$target_tab" ] && place="split $split_pane in $target_tab"
  printf 'dry-run: %s · devin %s %s · cwd %s · %s · prompt: %s\n' "$label" "$model" "$mode" "$wt" "$place" "$first_prompt"
  exit 0
fi

if [ -n "$target_tab" ]; then
  new_pane="$(herdr pane split --pane "$split_pane" --direction right --ratio 0.5 --cwd "$wt" --no-focus | jq -r .result.pane.pane_id)"
  python3 "$here/../../kickoff/scripts/equalize_columns.py" "$new_pane" >/dev/null
  placed="split in $target_tab"
else
  created="$(herdr tab create --workspace "$ws" --cwd "$wt" --label "$label" --no-focus)"
  new_pane="$(jq -r .result.root_pane.pane_id <<<"$created")"
  target_tab="$(jq -r .result.tab.tab_id <<<"$created")"
  placed="new tab $target_tab"
fi
herdr pane rename "$new_pane" "$label" >/dev/null

# A fresh pane's shell takes a moment to reach its prompt; herdr answers
# agent_pane_busy until then. Retry on that one error only.
started=0
for _ in $(seq 1 20); do
  if err="$(herdr agent start "$label" --kind devin --pane "$new_pane" --timeout 90000 \
      -- --model "$model" --permission-mode "$mode" 2>&1 >/dev/null)"; then
    started=1; break
  fi
  grep -q agent_pane_busy <<<"$err" || { say "$err"; break; }
  sleep 1
done
[ "$started" -eq 1 ] || die "devin did not come up in $new_pane; the pane is left as is"

herdr agent prompt "$label" "$first_prompt" >/dev/null
status="idle"
for _ in $(seq 1 40); do
  status="$(herdr agent get "$label" | jq -r .result.agent.agent_status)"
  [ "$status" = "working" ] && break
  sleep 0.5
done
if [ "$status" != "working" ]; then
  herdr agent read "$label" --source visible --lines 40 >&2 || true
  die "devin did not start on the prompt in $new_pane (status $status); the pane is left as is"
fi

printf '%s → %s/%s/%s · devin %s %s · %s · PANE=%s AGENT=%s\n' \
  "$label" "$ws" "$target_tab" "$new_pane" "$model" "$mode" "$placed" "$new_pane" "$label"
