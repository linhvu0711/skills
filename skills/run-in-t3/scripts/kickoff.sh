#!/usr/bin/env bash
# kickoff.sh: read issues, ask the Router what each one's thread runs, and
# build the line that starts a thread, for run-in-t3.
#
# Usage: kickoff.sh route <owner/repo> [--model M] [--effort E] <n>...
#        kickoff.sh thread <owner/repo> [--heading H] [--mode review|ready|merge]
#                   [--model M] [--effort E] <step> <n>
#
# route: one JSON line per issue, in the order named: number, title,
# parent, and the Router's line (shared/route/router.sh). It writes nothing.
#
# thread: the line one thread starts from: step, model, model_from, effort,
# effort_from, reason, path, slash_command, message, thread_title, and
# project (`found` or `added`). The Router must give the issue <step>.
# The agent starts the thread from this line with T3's tools, per
# shared/launch/launch-t3.md: `t3 thread start` takes no effort, and a
# script cannot call T3's tools.
#
# Exit 1: a stop that is this target's (outside T3 Code, no such issue, a
# step that does not fit, no checkout, no project), its reason the last
# `stop:` line on stderr. Exit 2: gh could not read GitHub. Exit 64: a wrong
# command line, with the usage after the reason. Nothing launches here.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
core="$here/../../../shared"
. "$core/route/labels.sh"
. "$core/gh.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
usage="usage: kickoff.sh route <owner/repo> [--model M] [--effort E] <n>...
       kickoff.sh thread <owner/repo> [--heading H] [--mode $ship_mode_list] [--model M] [--effort E] <step> <n>"

# The T3 check comes first, so nothing is read outside T3 Code.
bash "$core/t3-cli.sh" >/dev/null || exit 1
for c in jq gh; do command -v "$c" >/dev/null || die "$c is not installed"; done

cmd="${1:-}"
case "$cmd" in route|thread) shift ;; *) die_usage "$usage" ;; esac
slug="${1:-}"
[[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die_usage "$usage" "first argument must be <owner/repo>, got: ${slug:-nothing}"
shift

heading=""; mode=""; router_flags=(); nums=()
while [ $# -gt 0 ]; do
  case "$1" in
    --heading) [ "$cmd" = thread ] && [ -n "${2:-}" ] || die_usage "$usage" "--heading needs text, with thread"; heading="$2"; shift 2 ;;
    --mode)
      [ "$cmd" = thread ] && one_of "$ship_mode_list" "${2:-}" || die_usage "$usage" "--mode must be $(spelled "$ship_mode_list"), with thread, got: ${2:-nothing}"
      mode="$2"; shift 2 ;;
    --model|--effort) [ -n "${2:-}" ] || die_usage "$usage" "$1 needs a value"; router_flags+=("$1" "$2"); shift 2 ;;
    -*) die_usage "$usage" "unexpected argument: $1" ;;
    *) nums+=("$1"); shift ;;
  esac
done

step=""
if [ "$cmd" = thread ]; then
  step="${nums[0]:-}"
  one_of 'ship|triage|grill|ready-pr|complete-task' "$step" || die_usage "$usage" "step must be ship, triage, grill, ready-pr, or complete-task, got: ${step:-nothing}"
  nums=("${nums[@]:1}")
  [ "${#nums[@]}" -eq 1 ] || die_usage "$usage" "thread takes one issue"
  [ -z "$mode" ] || [ "$step" = ship ] || die_usage "$usage" "--mode goes only with ship"
fi
[ "${#nums[@]}" -gt 0 ] || die_usage "$usage" "name at least one issue"
for n in "${nums[@]}"; do
  [[ "$n" =~ ^#?[0-9]+$ ]] || die_usage "$usage" "an issue is a number, got: $n"
done
nums=("${nums[@]#\#}")

# read_issues <n>...: the issues in one GraphQL call, in the shape the Router
# reads, printed as one object keyed by number.
fields='number title state url parent { number } labels(first:50){nodes{name}} subIssues(first:100){nodes{number state}} closedByPullRequestsReferences(first:20,includeClosedPrs:false){nodes{url state}}'
read_issues() {
  local q="" n
  for n in "$@"; do q="$q i$n: issue(number: $n) { $fields }"; done
  # shellcheck disable=SC2016 # the $ names are GraphQL variables
  gh_out api graphql -f query='query($o: String!, $r: String!) { repository(owner: $o, name: $r) {'"$q"' } }' \
    -F o="${slug%/*}" -F r="${slug#*/}" \
    || { printf 'stop: gh could not read %s: %s\n' "$slug" "$err" >&2; exit 2; }
  jq -c '.data.repository | with_entries(.key |= ltrimstr("i"))' <<<"$out"
}

# route_one <issue json>: the issue's route line.
route_one() {
  local line
  line="$(bash "$core/route/router.sh" ${router_flags[@]+"${router_flags[@]}"} <<<"$1")" || exit
  jq -c --argjson r "$line" '{number, title, parent: (.parent.number // null)} + $r' <<<"$1"
}

issues="$(read_issues "${nums[@]}")"
lines=()
for n in "${nums[@]}"; do
  i="$(jq -c --arg n "$n" '.[$n]' <<<"$issues")"
  [ "$i" != null ] || die "no issue #$n in $slug"
  lines+=("$(route_one "$i")")
done

if [ "$cmd" = route ]; then
  printf '%s\n' "${lines[@]}"
  exit 0
fi

# ---------- thread ----------
r="${lines[0]}"; n="${nums[0]}"
got="$(jq -r '.step // ""' <<<"$r")"
[ "$(jq -r .stop <<<"$r")" != true ] || die "$(jq -r .reason <<<"$r")"
[ -n "$got" ] || die "#$n has no step: $(jq -r .reason <<<"$r")"
[ "$got" = "$step" ] || die "#$n goes to /$got, not /$step"

url="$(jq -r --arg n "$n" '.[$n].url' <<<"$issues")"
title="$(jq -r .title <<<"$r")"
lflags=()
[ -z "$mode" ] || lflags+=(--mode "$mode")
[ "$step" != ready-pr ] || lflags+=(--pr "$(jq -r .pr <<<"$r")")
launch="$(bash "$core/launch/line.sh" "$url" "$step" ${lflags[@]+"${lflags[@]}"})" || exit
path="$(jq -r .path <<<"$launch")"
project="$(bash "$core/launch/project.sh" "$path")" || exit

[ -n "$heading" ] || heading="#$n"
jq -cn --argjson r "$r" --argjson l "$launch" --arg title "$heading $title" --arg project "$project" \
  '{step: $r.step, model: $r.model, model_from: $r.model_from, effort: $r.effort, effort_from: $r.effort_from,
    reason: $r.reason, path: $l.path, slash_command: $l.slash_command, message: $l.message,
    thread_title: $title, project: $project}'
