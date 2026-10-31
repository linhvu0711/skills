#!/usr/bin/env bash
# decide.sh: work out what kickoff starts, for kickoff-herdr, kickoff-t3, and the orchestrator's check.
#
# Usage: decide.sh [--label L] [--model M] [--effort E]
#                  [--command ship|plan-up|triage|grill|ready-pr] [--mode review|ready|merge]
#                  [--size n=SIZE ...] <issue-url> [#n ...] [on <pr-url>]
#
# <issue-url> #n ...: when the first issue has sub-issues it is the parent and
# the numbers are a run under it. When it has none, it is the first ticket of a
# set: plain issues with no shared parent, planned together in the order given.
#
# The model and effort come from the tickets' size and ready-to-build labels
# unless a flag names them; --size gives a ticket with no size label the size
# the agent guessed, and a guess for a ticket with a size label is ignored.
# The command is ship unless --command names another.
# plan-up, triage, grill, and ready-pr come only from --command, and triage,
# grill, and ready-pr each have their own model and effort row. --mode sets
# /ship's ship mode; with none, the /ship thread picks it.
#
# Exit 0: one JSON line on stdout with number, title, form, args, command,
# command_from, mode, model, model_from, effort, effort_from, reason, base,
# path, label, heading, and message: the thread's first prompt, as
# `/ship --merge #42`, which every launcher sends as it is. The message names
# the target by number, or by URL when gh in the checkout sees another repo.
# Under --command ready-pr, args is the one open PR that closes the issue.
# Exit 1: a stop that is this target's: a bad flag, no open ticket, no open
# PR, no checkout. Exit 2: gh could not read GitHub. Either way the reason is
# the last line on stderr, and nothing launched, so the caller's launch starts
# only after every check here passed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=labels.sh
. "$here/labels.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
gh_die() { printf 'stop: %s\n' "$*" >&2; exit 2; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------- args ----------
label=""; args=(); sizes=()
set_model=""; set_effort=""; set_command=""; mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="$2"; shift 2 ;;
    --model) [ -n "${2:-}" ] || die "--model needs a name"; set_model="$2"; shift 2 ;;
    --effort)
      case "${2:-}" in low|medium|high|xhigh|max) ;; *) die "--effort must be low, medium, high, xhigh, or max, got: ${2:-nothing}" ;; esac
      set_effort="$2"; shift 2 ;;
    --command)
      case "${2:-}" in ship|plan-up|triage|grill|ready-pr) ;; *) die "--command must be ship, plan-up, triage, grill, or ready-pr, got: ${2:-nothing}" ;; esac
      set_command="$2"; shift 2 ;;
    --mode)
      case "${2:-}" in review|ready|merge) ;; *) die "--mode must be review, ready, or merge, got: ${2:-nothing}" ;; esac
      mode="$2"; shift 2 ;;
    --size)
      [[ "${2:-}" =~ ^[0-9]+=([Xx][Ss]|[SsMmLl]|[Xx][Ll])$ ]] || die "--size takes <n>=XS|S|M|L|XL, got: ${2:-nothing}"
      sizes+=("$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"); shift 2 ;;
    -*) die "unexpected argument: $1" ;;
    *) args+=("$1"); shift ;;
  esac
done
[ -z "$mode" ] || [ -z "$set_command" ] || [ "$set_command" = ship ] || die "--mode goes only with --command ship"
[ "${#args[@]}" -ge 1 ] || die "usage: decide.sh [--label L] [--model M] [--effort E] [--command ship|plan-up|triage|grill|ready-pr] [--mode review|ready|merge] [--size n=SIZE ...] <issue-url> [#n ...] [on <pr-url>]  (#n after a plain issue = a set, no parent needed)"

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
  || gh_die "gh could not read $issue_url"
title="$(jq -r .title <<<"$issue_json")"
sub_count="$(jq '.subIssues.nodes | length' <<<"$issue_json")"

if [ -n "$pr_url" ]; then form="on"
elif [ "${#tickets[@]}" -gt 0 ]; then
  if [ "$sub_count" -gt 0 ]; then form="run"; else form="set"; fi
elif [ "$sub_count" -gt 0 ]; then form="epic"
else form="issue"; fi

# ---------- model, effort, command ----------
# guess_of <n>: the size a --size flag gave ticket n, else nothing.
guess_of() {
  local s
  for s in ${sizes[@]+"${sizes[@]}"}; do
    if [ "${s%%=*}" = "$1" ]; then echo "${s#*=}"; fi
  done
}

# add_ticket <issue json>: counts one ticket. The biggest ticket picks the
# row, and a ticket with no size is the biggest. Only a target whose every
# ticket is ready-to-build takes the ready-to-build row at any size. A size
# label always wins: a guess counts only for a ticket with no size label, and
# each guess that counts is counted for the report.
all_ready=1; top=0; top_size=""; guessed=0
add_ticket() {
  local lab size="" ready=0 rank guess
  while IFS= read -r lab; do
    if [ "$(printf '%s' "$lab" | tr '[:upper:]' '[:lower:]')" = ready-to-build ]; then ready=1; fi
    [ -n "$size" ] || size="$(size_of "$lab")"
  done < <(jq -r '.labels[].name' <<<"$1")
  [ "$ready" -eq 1 ] || all_ready=0
  guess="$(guess_of "$(jq -r .number <<<"$1")")"
  if [ -n "$guess" ] && [ -z "$size" ]; then size="$guess"; guessed=$((guessed+1)); fi
  # ready-to-build goes only on XS and S tickets, so one with no size is S.
  [ -n "$size" ] || [ "$ready" -eq 0 ] || size=S
  case "$size" in XS) rank=1 ;; S) rank=2 ;; M) rank=3 ;; L) rank=4 ;; XL) rank=5 ;; *) rank=9 ;; esac
  if [ "$rank" -gt "$top" ]; then top=$rank; top_size="$size"; fi
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
  else json="$(gh issue view "$n" --repo "$slug" --json number,labels)" || gh_die "gh could not read #$n in $slug"; fi
  jq -e '[.labels[].name | ascii_downcase] | index("manual")' <<<"$json" >/dev/null && continue
  add_ticket "$json"; counted=$((counted+1))
done
[ "$counted" -gt 0 ] || die "#$number has no open ticket for an agent"
for s in ${sizes[@]+"${sizes[@]}"}; do
  case " ${list[*]} " in *" ${s%%=*} "*) ;; *) die "--size names #${s%%=*}, which is not in this target" ;; esac
done

command=ship
if [ "$all_ready" -eq 1 ]; then model=opus; effort=medium; reason="ready-to-build"
else
  if [ "$top" -le 2 ]; then model=opus; effort=medium
  elif [ "$top" -le 4 ]; then model=opus; effort=high
  else model=opus; effort=xhigh; fi
  if [ "$top" -eq 9 ]; then reason="no size"; else reason="size $top_size"; fi
fi
case "$set_command" in
  triage|grill) model=opus; effort=high; reason="command $set_command" ;;
  ready-pr) model=opus; effort=medium; reason="command ready-pr" ;;
esac
if [ "$counted" -gt 1 ]; then
  reason="$reason of $counted tickets"
  if [ "$guessed" -gt 0 ]; then reason="$reason, $guessed guessed"; fi
elif [ "$guessed" -gt 0 ]; then reason="$reason, guessed"; fi

# A value the user named wins over the row.
model_from=default; effort_from=default; command_from=default
if [ -n "$set_model" ]; then model="$set_model"; model_from=set; fi
if [ -n "$set_effort" ]; then effort="$set_effort"; effort_from=set; fi
if [ -n "$set_command" ]; then command="$set_command"; command_from=set; fi
# A ship mode the user named sets the command's form, so it reads as set.
if [ -n "$mode" ]; then command_from=set; fi

# ---------- ready-pr ----------
# /ready-pr takes the open PR that closes the issue. GitHub lists merged PRs
# here even with includeClosedPrs: false, so only OPEN ones count.
if [ "$command" = ready-pr ]; then
  # shellcheck disable=SC2016 # the $ names are GraphQL variables
  q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){closedByPullRequestsReferences(first:20,includeClosedPrs:false){nodes{url state}}}}}'
  prs="$(gh api graphql -f query="$q" -F o="$owner" -F r="$repo" -F n="$number" \
    -q '.data.repository.issue.closedByPullRequestsReferences.nodes[] | select(.state == "OPEN") | .url')" \
    || gh_die "gh could not read the PRs of #$number"
  pr_count="$(grep -c . <<<"$prs" || true)"
  [ "$pr_count" -gt 0 ] || die "#$number has no open PR"
  [ "$pr_count" -eq 1 ] || die "#$number has $pr_count open PRs: $(tr '\n' ' ' <<<"$prs" | sed 's/ $//')"
  prep_args="$prs"
fi

# ---------- base ----------
if [ -n "$pr_url" ]; then
  base="$(gh pr view "$pr_number" --repo "$slug" --json headRefName -q .headRefName)" || gh_die "gh could not read $pr_url"
else
  base="$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name)" || gh_die "gh could not read repo $slug"
fi

# ---------- repo path ----------
# The checkout resolver finds the main checkout; its stop line is ours.
found="$(bash "$here/../checkout.sh" main "$slug")" || exit 1
path="${found#* MAIN=}"

# The thread runs in that checkout, and /plan-up reads a number as an issue
# of the repo gh sees there. A fork clone can make gh see its upstream, so
# the URLs stay unless gh there names this repo.
here_repo="$(cd "$path" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
if [ "$(lower "$here_repo")" = "$(lower "$slug")" ]; then
  if [ "$command" = ready-pr ]; then prep_args="#${prs##*/}"
  else
    prep_args="#$number"
    for t in ${tickets[@]+"${tickets[@]}"}; do prep_args="$prep_args #$t"; done
    [ -z "$pr_url" ] || prep_args="$prep_args on #$pr_number"
  fi
fi

# ---------- label and heading ----------
# The label names a herdr pane and agent, and herdr takes only
# [a-z][a-z0-9_-]{0,31} there: i42, i42-43, i42-on-80, and i70 for a whole
# epic. Too long: the whole numbers that fit in 27 characters, then -more.
# The heading starts a T3 thread title, which takes any text: #42, #42 #43,
# #42 on #80, and #70. Too long: the numbers that fit in 27 characters, then
# +<the rest>. A label the user named is the heading as given.
heading="$label"
if [ -z "$label" ]; then
  case "$form" in
    run) nums=("${tickets[@]}") ;;
    set) nums=("$number" "${tickets[@]}") ;;
    *) nums=("$number") ;;
  esac
  heading="#${nums[0]}"; k=1
  while [ "$k" -lt "${#nums[@]}" ] && [ $(( ${#heading} + ${#nums[$k]} + 2 )) -le 27 ]; do
    heading="$heading #${nums[$k]}"; k=$((k+1))
  done
  if [ "$k" -lt "${#nums[@]}" ]; then heading="$heading +$(( ${#nums[@]} - k ))"; fi
  if [ "$form" = on ]; then heading="$heading on #$pr_number"; fi
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

jq -cn --argjson number "$number" --arg title "$title" --arg form "$form" --arg args "$prep_args" \
  --arg command "$command" --arg command_from "$command_from" --arg mode "$mode" \
  --arg model "$model" --arg model_from "$model_from" \
  --arg effort "$effort" --arg effort_from "$effort_from" \
  --arg reason "$reason" --arg base "$base" --arg path "$path" --arg label "$label" --arg heading "$heading" \
  '{number: $number, title: $title, form: $form, args: $args, command: $command, command_from: $command_from,
    mode: $mode, model: $model, model_from: $model_from, effort: $effort, effort_from: $effort_from,
    reason: $reason, base: $base, path: $path, label: $label, heading: $heading,
    message: "/\($command)\(if $mode == "" then "" else " --\($mode)" end) \($args)"}'
