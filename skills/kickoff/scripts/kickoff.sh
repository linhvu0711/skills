#!/usr/bin/env bash
# kickoff.sh: open a herdr pane and run /plan-up there.
#
# Usage: kickoff.sh [--label L] [--dry-run] [--no-prompt] <issue-url> [#n ...] [on <pr-url>]
#
# <issue-url> #n ...: when the first issue has sub-issues it is the parent and
# the numbers are a run under it. When it has none, it is the first ticket of a
# set: plain issues with no shared parent, planned together in the order given.
#
# Exit 0: the pane is running /plan-up, one report line on stdout.
# Exit 1: something stopped us; the reason is the last line on stderr.
# Nothing is half done: no pane exists until every check passed.
# The tree is left as is: /plan-up reads its own copy of the base.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*" >&2; }

# ---------- args ----------
label=""; dry_run=0; no_prompt=0; args=(); sizes=()
set_model=""; set_effort=""; set_command=""
while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="$2"; shift 2 ;;
    --model) [ -n "${2:-}" ] || die "--model needs a name"; set_model="$2"; shift 2 ;;
    --effort)
      case "${2:-}" in low|medium|high|xhigh|max) ;; *) die "--effort must be low, medium, high, xhigh, or max, got: ${2:-nothing}" ;; esac
      set_effort="$2"; shift 2 ;;
    --command)
      case "${2:-}" in ship|plan-up) ;; *) die "--command must be ship or plan-up, got: ${2:-nothing}" ;; esac
      set_command="$2"; shift 2 ;;
    --size)
      [[ "${2:-}" =~ ^[0-9]+=([Xx][Ss]|[SsMmLl]|[Xx][Ll])$ ]] || die "--size takes <n>=XS|S|M|L|XL, got: ${2:-nothing}"
      sizes+=("$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"); shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-prompt) no_prompt=1; shift ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -ge 1 ] || die "usage: kickoff.sh <issue-url> [#n ...] [on <pr-url>]  (#n after a plain issue = a set, no parent needed)"

issue_url="${args[0]}"
[[ "$issue_url" =~ ^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)/?$ ]] \
  || die "first argument must be a GitHub issue URL, got: $issue_url"
owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
slug="$owner/$repo"

pr_url=""; tickets=()
i=1
while [ $i -lt "${#args[@]}" ]; do
  a="${args[$i]}"
  if [ "$a" = "on" ]; then
    pr_url="${args[$((i+1))]:-}"
    [[ "$pr_url" =~ ^https://github\.com/$owner/$repo/pull/([0-9]+)/?$ ]] \
      || die "'on' needs a PR URL in $slug, got: ${pr_url:-nothing}"
    pr_number="${BASH_REMATCH[1]}"
    i=$((i+2))
  elif [[ "$a" =~ ^#?([0-9]+)$ ]]; then
    tickets+=("${BASH_REMATCH[1]}"); i=$((i+1))
  else
    die "unexpected argument: $a"
  fi
done
prep_args="${args[*]}"

# ---------- issue ----------
issue_json="$(gh issue view "$number" --repo "$slug" --json number,title,labels,subIssues,state)" \
  || die "gh could not read $issue_url"
title="$(jq -r .title <<<"$issue_json")"
sub_count="$(jq '.subIssues.nodes | length' <<<"$issue_json")"

if [ -n "$pr_url" ]; then form="on"
elif [ "${#tickets[@]}" -gt 0 ]; then
  if [ "$sub_count" -gt 0 ]; then form="run"; else form="set"; fi
elif [ "$sub_count" -gt 0 ]; then form="epic"
else form="issue"; fi

# ---------- model, effort, command ----------
# size_of <label>: XS, S, M, L, or XL when the label names a size, matched
# loosely (`size/S`, `Size: Medium`, `effort-large`), else nothing.
size_of() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/(size|scope|effort)//g; s/[^a-z]//g')" in
    xs|xsmall|extrasmall) echo XS ;;
    s|small) echo S ;;
    m|med|medium) echo M ;;
    l|large) echo L ;;
    xl|xlarge|extralarge) echo XL ;;
  esac
}

# guess_of <n>: the size a --size flag gave ticket n, else nothing.
guess_of() {
  local s
  for s in ${sizes[@]+"${sizes[@]}"}; do
    if [ "${s%%=*}" = "$1" ]; then echo "${s#*=}"; fi
  done
}

# add_ticket <issue json>: counts one ticket. The biggest ticket picks the
# row, and a ticket with no size is the biggest. Only a target whose every
# ticket is ready-to-build takes the sonnet row. A guessed size wins over a
# label.
all_ready=1; top=0; top_size=""; top_guessed=0
add_ticket() {
  local lab size="" ready=0 rank guess
  while IFS= read -r lab; do
    if [ "$(printf '%s' "$lab" | tr '[:upper:]' '[:lower:]')" = ready-to-build ]; then ready=1; fi
    [ -n "$size" ] || size="$(size_of "$lab")"
  done < <(jq -r '.labels[].name' <<<"$1")
  [ "$ready" -eq 1 ] || all_ready=0
  guess="$(guess_of "$(jq -r .number <<<"$1")")"
  if [ -n "$guess" ]; then size="$guess"; fi
  # ready-to-build goes only on XS and S tickets, so one with no size is S.
  [ -n "$size" ] || [ "$ready" -eq 0 ] || size=S
  case "$size" in XS) rank=1 ;; S) rank=2 ;; M) rank=3 ;; L) rank=4 ;; XL) rank=5 ;; *) rank=9 ;; esac
  if [ "$rank" -gt "$top" ]; then
    top=$rank; top_size="$size"; top_guessed=0
    if [ -n "$guess" ]; then top_guessed=1; fi
  fi
}

# The tickets the target holds: a run's #n, a set's issue and #n, an epic's
# open sub-issues, else the issue. A manual ticket is a person's work, so it
# does not count.
case "$form" in
  run) list=("${tickets[@]}") ;;
  set) list=("$number" "${tickets[@]}") ;;
  epic) list=(); while IFS= read -r n; do list+=("$n"); done \
          < <(jq -r '.subIssues.nodes[] | select(.state == "OPEN") | .number' <<<"$issue_json") ;;
  *) list=("$number") ;;
esac
counted=0
for n in ${list[@]+"${list[@]}"}; do
  if [ "$n" = "$number" ]; then json="$issue_json"
  else json="$(gh issue view "$n" --repo "$slug" --json number,labels)" || die "gh could not read #$n in $slug"; fi
  jq -e '[.labels[].name | ascii_downcase] | index("manual")' <<<"$json" >/dev/null && continue
  add_ticket "$json"; counted=$((counted+1))
done
[ "$counted" -gt 0 ] || die "#$number has no open ticket for an agent"
for s in ${sizes[@]+"${sizes[@]}"}; do
  case " ${list[*]} " in *" ${s%%=*} "*) ;; *) die "--size names #${s%%=*}, which is not in this target" ;; esac
done

if [ "$all_ready" -eq 1 ]; then model=sonnet; effort=high; command=ship; reason="ready-to-build"
else
  if [ "$top" -le 2 ]; then model=opus; effort=medium; command=ship
  elif [ "$top" -eq 3 ]; then model=opus; effort=medium; command=plan-up
  else model=opus; effort=high; command=plan-up; fi
  if [ "$top" -eq 9 ]; then reason="no size"; else reason="size $top_size"; fi
fi
if [ "$counted" -gt 1 ]; then reason="$reason of $counted tickets"; fi
if [ "$top_guessed" -eq 1 ]; then reason="$reason, guessed"; fi

# A value the user named wins over the row.
model_from=default; effort_from=default
if [ -n "$set_model" ]; then model="$set_model"; model_from=set; fi
if [ -n "$set_effort" ]; then effort="$set_effort"; effort_from=set; fi
if [ -n "$set_command" ]; then command="$set_command"; fi

# ---------- base ----------
if [ -n "$pr_url" ]; then
  base="$(gh pr view "$pr_number" --repo "$slug" --json headRefName -q .headRefName)" || die "gh could not read $pr_url"
else
  base="$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name)" || die "gh could not read repo $slug"
fi

# ---------- repo path ----------
# The checkout resolver finds the main checkout; its stop line is ours.
found="$(bash "$here/../../../shared-skill-core/checkout.sh" main "$slug")" || exit 1
path_from="${found%% *}"; path_from="${path_from#FROM=}"; path="${found#* MAIN=}"

# ---------- label ----------
# The issue numbers: i42, i42-43, i42-on-80, and i70 for a whole epic. Too
# long: the whole numbers that fit in 27 characters, then -more.
if [ -z "$label" ]; then
  case "$form" in
    run) nums=("${tickets[@]}") ;;
    set) nums=("$number" "${tickets[@]}") ;;
    *) nums=("$number") ;;
  esac
  label="i$(IFS=-; printf '%s' "${nums[*]}")"
  if [ "${#label}" -gt 32 ]; then
    label="i${nums[0]}"
    for n in "${nums[@]:1}"; do
      [ $(( ${#label} + ${#n} + 1 )) -le 27 ] || break
      label="${label}-$n"
    done
    label="${label}-more"
  fi
  if [ "$form" = on ]; then label="${label}-on-${pr_number}"; fi
fi
label="$(printf '%s' "$label" | sed -E 's/^[^a-z]+//; s/[^a-z0-9_-]//g' | cut -c1-32)"
[ -n "$label" ] || label="prep-$number"

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

if [ "$dry_run" -eq 1 ]; then
  place="new tab"; [ -n "$target_tab" ] && place="split $split_pane in $target_tab"
  printf 'dry-run: #%s %s · form %s · /%s · model %s · effort %s · %s · repo %s (%s) · %s · label %s · %s · prep args: %s\n' \
    "$number" "$title" "$form" "$command" "$model" "$effort" "$reason" "$path" "$path_from" "base $base" "$label" "$place" "$prep_args"
  exit 0
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

if [ "$no_prompt" -eq 1 ]; then
  printf '#%s %s → %s/%s/%s · model %s · effort %s · %s · %s · %s · no prompt sent\n' \
    "$number" "$title" "$ws" "$target_tab" "$new_pane" "$model" "$effort" "$reason" "base $base" "$placed"
  exit 0
fi

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

printf '#%s %s → %s/%s/%s · /%s · model %s (%s) · effort %s (%s) · %s · %s · %s\n' \
  "$number" "$title" "$ws" "$target_tab" "$new_pane" "$command" "$model" "$model_from" "$effort" "$effort_from" "$reason" "base $base" "$placed"
