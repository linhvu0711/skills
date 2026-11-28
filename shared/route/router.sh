#!/usr/bin/env bash
# router.sh: the Router. It reads one issue and gives the step its next
# thread runs and the effort, or no step and the reason. run-in-t3 and the
# orchestrator ask it; it never calls GitHub, so a caller that holds many
# issues reads them once and asks for each.
#
# Usage: router.sh [--pick <step>] [--answer <word>] [--size XS|S|M|L|XL] [--model M] [--effort E] < <issue json>
#
# stdin: one issue in the shape GitHub's GraphQL API gives it: number,
# state, labels {nodes {name}}, subIssues {nodes}, and
# closedByPullRequestsReferences {nodes {url state}}. The caller passes only
# the PRs it counts: the orchestrator leaves out the ones its own threads
# opened.
#
# --pick is a step the user named for this issue, a word of pick_list in
# labels.sh: it wins over every label, but not over a closed issue or an epic.
# --answer is the user's answer to a proposal, a word of route_list in
# labels.sh, and --size goes with --answer ship. An answer counts only when
# no label routes the issue: a label always wins. --model and --effort are
# the user's, and win over the row.
#
# The rows, the first that holds:
#   closed                      done      no step
#   has sub-issues              epic      no step: the caller routes its open ones
#   a pick                      picked    the picked step; ready-pr needs one open PR
#   manual and waiting          waiting   no step
#   manual                      task      /complete-task
#   one open PR                 pr        /ready-pr <that PR>; two or more: no step, a stop
#   bug                         bug       /triage
#   seed                        seed      /grill
#   an XXL size label           too-big   no step: cut it with /file-epic
#   a size label, ready-to-build ticket   /ship
#   an answer                   unlabeled the answer's step, if it has one
#   none of these               unlabeled no step: propose one
#
# Exit 0: one JSON line: stage, step, stop, model, model_from, effort,
# effort_from, reason, pr. A null step has null model and effort. stop is
# true when a step should run and cannot, so the caller shows the reason as
# a wait: two or more open PRs, or a ready-pr pick or answer with no open PR.
# Exit 1: jq is not installed, `stop: jq is not installed` on stderr.
# Exit 64: a wrong command line, or stdin that is not one issue, with the
# usage after the reason on stderr.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=labels.sh
. "$here/labels.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
usage="usage: router.sh [--pick $pick_list] [--answer $route_list] [--size $size_list] [--model M] [--effort E] < <issue json>"

command -v jq >/dev/null || die "jq is not installed"

pick=""; answer=""; size=""; set_model=""; set_effort=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pick)
      one_of "$pick_list" "${2:-}" || die_usage "$usage" "--pick must be $(spelled "$pick_list"), got: ${2:-nothing}"
      pick="$2"; shift 2 ;;
    --answer)
      one_of "$route_list" "${2:-}" || die_usage "$usage" "--answer must be $(spelled "$route_list"), got: ${2:-nothing}"
      answer="$2"; shift 2 ;;
    --size)
      size="$(printf '%s' "${2:-}" | tr '[:lower:]' '[:upper:]')"
      one_of "$size_list" "$size" || die_usage "$usage" "--size must be $(spelled "$size_list"), got: ${2:-nothing}"
      shift 2 ;;
    --model) [ -n "${2:-}" ] || die_usage "$usage" "--model needs a name"; set_model="$2"; shift 2 ;;
    --effort)
      one_of "$effort_list" "${2:-}" || die_usage "$usage" "--effort must be $(spelled "$effort_list"), got: ${2:-nothing}"
      set_effort="$2"; shift 2 ;;
    *) die_usage "$usage" "unexpected argument: $1" ;;
  esac
done
[ "$answer" != ship ] || [ -n "$size" ] || die_usage "$usage" "--answer ship needs --size $size_list"
[ -z "$size" ] || [ "$answer" = ship ] || die_usage "$usage" "--size goes only with --answer ship"

issue="$(cat)"
jq -e 'type == "object" and has("number") and has("state")' <<<"$issue" >/dev/null 2>&1 \
  || die_usage "$usage" "stdin must be one issue as JSON"
number="$(jq -r .number <<<"$issue")"
labels="$(jq -r '(.labels.nodes // [])[].name | ascii_downcase' <<<"$issue")"
has() { grep -qxF "$1" <<<"$labels"; }
label_size=""
while IFS= read -r lab; do
  [ -n "$label_size" ] || label_size="$(size_of "$lab")"
done <<<"$labels"
prs="$(jq -r '(.closedByPullRequestsReferences.nodes // [])[] | select(.state == "OPEN") | .url' <<<"$issue")"
pr_count="$(grep -c . <<<"$prs" || true)"

# effort_of <step> <size> <ready>: the effort row for a step.
effort_of() {
  case "$1" in
    ship)
      if [ "$3" = 1 ]; then echo medium; return; fi
      case "$2" in XS|S) echo medium ;; M|L) echo high ;; XL) echo xhigh ;; esac ;;
    triage|grill) echo "$analysis_effort" ;;
    ready-pr|complete-task) echo medium ;;
  esac
}

# out <stage> <step> <reason> [stop] [pr] [size] [ready]: the line, with the
# model and effort for a step.
out() {
  local model="" effort="" model_from="" effort_from=""
  if [ -n "$2" ]; then
    model="$analysis_model"; model_from=default
    effort="$(effort_of "$2" "${6:-}" "${7:-0}")"; effort_from=default
    if [ -n "$set_model" ]; then model="$set_model"; model_from=set; fi
    if [ -n "$set_effort" ]; then effort="$set_effort"; effort_from=set; fi
  fi
  jq -cn --arg stage "$1" --arg step "$2" --arg reason "$3" --arg stop "${4:-false}" --arg pr "${5:-}" \
    --arg model "$model" --arg model_from "$model_from" --arg effort "$effort" --arg effort_from "$effort_from" \
    'def n: if . == "" then null else . end;
     {stage: $stage, step: ($step | n), stop: ($stop == "true"), model: ($model | n), model_from: ($model_from | n),
      effort: ($effort | n), effort_from: ($effort_from | n), reason: $reason, pr: ($pr | n)}'
  exit 0
}

[ "$(jq -r .state <<<"$issue")" != CLOSED ] || out done "" closed
[ "$(jq '(.subIssues.nodes // []) | length' <<<"$issue")" -eq 0 ] || out epic "" "has sub-issues: the caller routes its open ones"
case "$pick" in
  triage|grill) out picked "$pick" "you picked /$pick" ;;
  ready-pr)
    if [ "$pr_count" -eq 1 ]; then out picked ready-pr "you picked /ready-pr: open PR $prs" false "$prs"; fi
    if [ "$pr_count" -gt 1 ]; then out picked "" "#$number has $pr_count open PRs: $(tr '\n' ' ' <<<"$prs" | sed 's/ $//')" true; fi
    out picked "" "#$number has no open PR" true ;;
esac
if has manual; then
  if has waiting; then out waiting "" "a task that waits outside"; fi
  out task complete-task manual
fi
if [ "$pr_count" -eq 1 ]; then out pr ready-pr "open PR $prs" false "$prs"; fi
if [ "$pr_count" -gt 1 ]; then out pr "" "#$number has $pr_count open PRs: $(tr '\n' ' ' <<<"$prs" | sed 's/ $//')" true; fi
if has bug; then out bug triage bug; fi
if has seed; then out seed grill seed; fi
if [ "$label_size" = XXL ]; then out too-big "" "XXL: cut it with /file-epic"; fi
if has ready-to-build; then out ticket ship ready-to-build false "" "$label_size" 1; fi
if [ -n "$label_size" ]; then out ticket ship "size $label_size" false "" "$label_size"; fi
case "$answer" in
  grill|triage) out unlabeled "$answer" "answer $answer" ;;
  ship) out unlabeled ship "answer ship, size $size" false "" "$size" ;;
  ready-pr) out unlabeled "" "#$number has no open PR" true ;;
  task) out unlabeled "" "answer task: yours" ;;
  close) out unlabeled "" "answer close: yours to close" ;;
  xxl) out unlabeled "" "answer xxl: cut it with /file-epic" ;;
esac
out unlabeled "" "no label picks a step: propose one"
