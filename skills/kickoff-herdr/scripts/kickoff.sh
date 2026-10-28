#!/usr/bin/env bash
# kickoff.sh: open a herdr pane and run /ship-ready, /ship-full, or /plan-up there.
#
# Usage: kickoff.sh [--label L] [--model M] [--effort E]
#                   [--command ship-ready|ship-full|plan-up|triage|grill|ready-pr]
#                   [--size n=SIZE ...] <issue-url> [#n ...] [on <pr-url>]
#
# <issue-url> #n ...: when the first issue has sub-issues it is the parent and
# the numbers are a run under it. When it has none, it is the first ticket of a
# set: plain issues with no shared parent, planned together in the order given.
#
# The model, effort, and command come from the tickets' size and
# ready-to-build labels unless a flag names them; --size gives a ticket with
# no size label the size the agent guessed.
#
# Exit 0: the pane is running the command, one report line on stdout.
# Exit 1: something stopped us; the reason is the last line on stderr.
# Nothing is half done: no pane exists until every check passed.
# The tree is left as is: /ship-ready, /ship-full, and /plan-up read their own copy of the base.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*" >&2; }

# ---------- decide ----------
# The shared decide script reads the target and flags; its stop line is ours.
decided="$(bash "$here/../../../shared/kickoff/decide.sh" "$@")" || exit 1
field() { jq -r ".$1" <<<"$decided"; }
number="$(field number)"; title="$(field title)"; prep_args="$(field args)"
command="$(field command)"; command_from="$(field command_from)"
model="$(field model)"; model_from="$(field model_from)"
effort="$(field effort)"; effort_from="$(field effort_from)"
reason="$(field reason)"; base="$(field base)"; path="$(field path)"; label="$(field label)"

# ---------- herdr ----------
[ "${HERDR_ENV:-}" = 1 ] || die "not inside herdr"
ws="${HERDR_WORKSPACE_ID:?}"; my_tab="${HERDR_TAB_ID:?}"

# unique agent name
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

if [ -n "$target_tab" ]; then
  new_pane="$(herdr pane split --pane "$split_pane" --direction right --ratio 0.5 --cwd "$path" --no-focus | jq -r .result.pane.pane_id)"
  python3 "$here/equalize_columns.py" "$new_pane" >/dev/null
  placed="split in $target_tab"
else
  created="$(herdr tab create --workspace "$ws" --cwd "$path" --label "$label" --no-focus)"
  new_pane="$(jq -r .result.root_pane.pane_id <<<"$created")"
  target_tab="$(jq -r .result.tab.tab_id <<<"$created")"
  placed="new tab $target_tab"
fi
herdr pane rename "$new_pane" "$label" >/dev/null

# A fresh pane's shell takes a moment to reach its prompt; herdr answers
# agent_pane_busy until then. Retry on that one error only.
started=0
for _ in $(seq 1 20); do
  if err="$(herdr agent start "$label" --kind claude --pane "$new_pane" --timeout 60000 \
      -- --model "$model" --effort "$effort" --permission-mode auto 2>&1 >/dev/null)"; then
    started=1; break
  fi
  grep -q agent_pane_busy <<<"$err" || { say "$err"; break; }
  sleep 1
done
[ "$started" -eq 1 ] || die "claude did not come up in $new_pane; the pane is left as is"

herdr agent prompt "$label" "/$command $prep_args" >/dev/null
status="idle"
for _ in $(seq 1 30); do
  status="$(herdr agent get "$label" | jq -r .result.agent.agent_status)"
  [ "$status" = "working" ] && break
  sleep 0.5
done
if [ "$status" != "working" ]; then
  herdr agent read "$label" --source visible --lines 40 >&2 || true
  die "/$command did not start in $new_pane (status $status); the pane is left as is"
fi

printf '#%s %s → %s/%s/%s · /%s (%s) · model %s (%s) · effort %s (%s) · %s · %s · %s\n' \
  "$number" "$title" "$ws" "$target_tab" "$new_pane" "$command" "$command_from" "$model" "$model_from" "$effort" "$effort_from" "$reason" "base $base" "$placed"
