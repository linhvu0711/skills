#!/usr/bin/env bash
# kickoff.sh: read issues, ask the Router what each one's thread runs, and
# build the line that starts a thread, for run-in-t3.
#
# Usage: kickoff.sh route <owner/repo> [--model M] [--effort E] [--pick <n>=<step>]...
#                   [--answer <n>=<word>]... [--size <n>=<size>]... <n>...
#        kickoff.sh thread <owner/repo> [--heading H] [--mode review|ready|merge]
#                   [--model M] [--effort E] [--pick <n>=<step>]...
#                   [--answer <n>=<word>]... [--size <n>=<size>]...
#                   [--on <pr-n>] <step> <n>...
#        kickoff.sh label <owner/repo> <n> <word> [--size <size>]
#
# --pick is a step the user named for issue <n>, a word of pick_list in
# shared/route/labels.sh; it wins over the labels.
# --answer is the user's answer to a Proposal for issue <n>, a word of
# route_list in shared/route/labels.sh, and --size its size when the word is
# ship. Each goes to the Router for that issue only; a label always wins.
#
# route: one JSON line per issue, in the order named: number, title,
# parent, and the Router's line (shared/route/router.sh). An open epic's
# line is followed by one line per open sub-issue; one in another repo gets
# no step. parent is null for a parent in another repo. It writes nothing.
#
# thread: the line one thread starts from: step, model, model_from, effort,
# effort_from, reason, path, slash_command, message, thread_title, and
# project (`found` or `added`). The Router must give every issue <step>.
# Only ship takes several issues: tickets that share one parent go as a run
# under it, else as a set in the order given, and one epic named alone is
# the whole epic. A ship thread skips a ticket that is a task, waits, or is
# done, as /ship's plan lists tasks itself. The thread's effort is the
# highest of its issues. --on <pr-n> makes one ticket a new layer on that
# PR's stack; the PR must be open.
# label: write the answer <word> to issue <n> as the label that fits
# (answer_label in labels.sh), through shared/route/edit-labels.sh. One
# line: `labeled #<n> <label>`, with ` (made the label)` when the repo
# lacked it; `not labeled #<n>: <why>` when its labels already route it or
# GitHub refused. An answer with no label prints nothing.
#
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
usage="usage: kickoff.sh route <owner/repo> [--model M] [--effort E] [--pick <n>=<step>]... [--answer <n>=<word>]... [--size <n>=<size>]... <n>...
       kickoff.sh thread <owner/repo> [--heading H] [--mode $ship_mode_list] [--model M] [--effort E] [--pick <n>=<step>]... [--answer <n>=<word>]... [--size <n>=<size>]... [--on <pr-n>] <step> <n>...
       kickoff.sh label <owner/repo> <n> <word> [--size <size>]"

# The T3 check comes first, so nothing is read outside T3 Code.
bash "$core/t3-cli.sh" >/dev/null || exit 1
for c in jq gh; do command -v "$c" >/dev/null || die "$c is not installed"; done

cmd="${1:-}"
case "$cmd" in route|thread|label) shift ;; *) die_usage "$usage" ;; esac
slug="${1:-}"
[[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die_usage "$usage" "first argument must be <owner/repo>, got: ${slug:-nothing}"
shift

heading=""; mode=""; on=""; router_flags=(); nums=(); picks=(); answers=(); sizes=(); label_size=""
while [ $# -gt 0 ]; do
  case "$1" in
    --heading) [ "$cmd" = thread ] && [ -n "${2:-}" ] || die_usage "$usage" "--heading needs text, with thread"; heading="$2"; shift 2 ;;
    --mode)
      [ "$cmd" = thread ] && one_of "$ship_mode_list" "${2:-}" || die_usage "$usage" "--mode must be $(spelled "$ship_mode_list"), with thread, got: ${2:-nothing}"
      mode="$2"; shift 2 ;;
    --on) [ "$cmd" = thread ] && [[ "${2:-}" =~ ^#?[0-9]+$ ]] || die_usage "$usage" "--on needs a PR number, with thread"; on="${2#\#}"; shift 2 ;;
    --model|--effort) [ "$cmd" != label ] && [ -n "${2:-}" ] || die_usage "$usage" "$1 needs a value, with route or thread"; router_flags+=("$1" "$2"); shift 2 ;;
    --pick)
      a="${2:-}"; a="${a#\#}"
      [ "$cmd" != label ] && [[ "$a" =~ ^[0-9]+= ]] && one_of "$pick_list" "${a#*=}" \
        || die_usage "$usage" "--pick takes <n>=$(spelled "$pick_list"), with route or thread, got: ${2:-nothing}"
      picks+=("$a"); shift 2 ;;
    --answer)
      a="${2:-}"; a="${a#\#}"
      [ "$cmd" != label ] && [[ "$a" =~ ^[0-9]+= ]] && one_of "$route_list" "${a#*=}" \
        || die_usage "$usage" "--answer takes <n>=$(spelled "$route_list"), with route or thread, got: ${2:-nothing}"
      answers+=("$a"); shift 2 ;;
    --size)
      z="$(printf '%s' "${2:-}" | tr '[:lower:]' '[:upper:]')"
      if [ "$cmd" = label ]; then
        one_of "$size_list" "$z" || die_usage "$usage" "--size must be $(spelled "$size_list"), got: ${2:-nothing}"
        label_size="$z"
      else
        z="${z#\#}"
        [[ "$z" =~ ^[0-9]+= ]] && one_of "$size_list" "${z#*=}" || die_usage "$usage" "--size takes <n>=$size_list, got: ${2:-nothing}"
        sizes+=("$z")
      fi
      shift 2 ;;
    -*) die_usage "$usage" "unexpected argument: $1" ;;
    *) nums+=("$1"); shift ;;
  esac
done

step=""
if [ "$cmd" = thread ]; then
  step="${nums[0]:-}"
  one_of 'ship|triage|grill|ready-pr|complete-task' "$step" || die_usage "$usage" "step must be ship, triage, grill, ready-pr, or complete-task, got: ${step:-nothing}"
  nums=("${nums[@]:1}")
  [ "${#nums[@]}" -le 1 ] || [ "$step" = ship ] || die_usage "$usage" "only ship takes several issues"
  [ -z "$mode" ] || [ "$step" = ship ] || die_usage "$usage" "--mode goes only with ship"
  [ -z "$on" ] || { [ "$step" = ship ] && [ "${#nums[@]}" -eq 1 ]; } || die_usage "$usage" "--on goes only with ship and one issue"
fi
word=""
if [ "$cmd" = label ]; then
  [ "${#nums[@]}" -eq 2 ] || die_usage "$usage" "label takes one issue and one word"
  word="${nums[1]}"; nums=("${nums[0]}")
  one_of "$route_list" "$word" || die_usage "$usage" "the word must be $(spelled "$route_list"), got: $word"
  [ "$word" != ship ] || [ -n "$label_size" ] || die_usage "$usage" "a ship answer needs --size"
fi
[ "${#nums[@]}" -gt 0 ] || die_usage "$usage" "name at least one issue"
for n in "${nums[@]}"; do
  [[ "$n" =~ ^#?[0-9]+$ ]] || die_usage "$usage" "an issue is a number, got: $n"
done
nums=("${nums[@]#\#}")

# read_issues <n>...: the issues in one GraphQL call, in the shape the Router
# reads, printed as one object keyed by number.
fields='number title state url parent { number repository { nameWithOwner } } labels(first:50){nodes{name}} subIssues(first:100){nodes{number title state repository { nameWithOwner }}} closedByPullRequestsReferences(first:20,includeClosedPrs:false){nodes{url state}}'
read_issues() {
  local q="" n
  for n in "$@"; do q="$q i$n: issue(number: $n) { $fields }"; done
  # shellcheck disable=SC2016 # the $ names are GraphQL variables
  gh_out api graphql -f query='query($o: String!, $r: String!) { repository(owner: $o, name: $r) {'"$q"' } }' \
    -F o="${slug%/*}" -F r="${slug#*/}" \
    || { printf 'stop: gh could not read %s: %s\n' "$slug" "$err" >&2; exit 2; }
  jq -c '.data.repository | with_entries(.key |= ltrimstr("i"))' <<<"$out"
}

# issue_of <issues> <n>: one issue of a read_issues answer, or a stop.
issue_of() {
  local i
  i="$(jq -c --arg n "$2" '.[$n]' <<<"$1")"
  [ "$i" != null ] || die "no issue #$2 in $slug"
  printf '%s\n' "$i"
}

# given_for <n> <n=value>...: the value a --pick, --answer, or --size gave
# issue n.
given_for() {
  local n="$1" a; shift
  for a in "$@"; do [ "${a%%=*}" != "$n" ] || { echo "${a#*=}"; return; }; done
}

# check_given <n>...: every --pick, --answer, and --size names one of these
# issues.
check_given() {
  local a
  for a in ${picks[@]+"${picks[@]}"} ${answers[@]+"${answers[@]}"} ${sizes[@]+"${sizes[@]}"}; do
    case " $* " in *" ${a%%=*} "*) ;; *) die_usage "$usage" "--pick, --answer, or --size names #${a%%=*}, which is not in this call" ;; esac
  done
}

# route_one <issue json>: the issue's route line, with the user's pick and
# answer for it, if any.
route_one() {
  local line n p a z flags=()
  n="$(jq -r .number <<<"$1")"
  p="$(given_for "$n" ${picks[@]+"${picks[@]}"})"
  [ -z "$p" ] || flags+=(--pick "$p")
  a="$(given_for "$n" ${answers[@]+"${answers[@]}"})"; z="$(given_for "$n" ${sizes[@]+"${sizes[@]}"})"
  [ -z "$a" ] || flags+=(--answer "$a")
  [ -z "$z" ] || [ "$a" != ship ] || flags+=(--size "$z")
  line="$(bash "$core/route/router.sh" ${router_flags[@]+"${router_flags[@]}"} ${flags[@]+"${flags[@]}"} <<<"$1")" || exit
  jq -c --argjson r "$line" --arg s "$slug" \
    '{number, title, parent: (if (.parent.repository.nameWithOwner // "" | ascii_downcase) == ($s | ascii_downcase) then .parent.number else null end)} + $r' <<<"$1"
}

# open_subs <issue json>: the numbers of its open sub-issues in this repo,
# one per line. An issue number names an issue only within its repo; GitHub
# matches a repo name in any case.
open_subs() { jq -r --arg s "$slug" '(.subIssues.nodes // [])[] | select(.state == "OPEN" and (.repository.nameWithOwner | ascii_downcase) == ($s | ascii_downcase)) | .number' <<<"$1"; }

# elsewhere <issue json>: one route line, with no step, per open sub-issue
# in another repo, as it is started from there.
elsewhere() {
  jq -c --arg s "$slug" '.number as $p | (.subIssues.nodes // [])[] | select(.state == "OPEN" and (.repository.nameWithOwner | ascii_downcase) != ($s | ascii_downcase))
    | {number, title, parent: $p, stage: null, step: null, stop: false, model: null, model_from: null,
       effort: null, effort_from: null, reason: "in \(.repository.nameWithOwner): start it from there", pr: null}' <<<"$1"
}

issues="$(read_issues "${nums[@]}")"

if [ "$cmd" = route ]; then
  lines=(); routed=()
  for n in "${nums[@]}"; do
    i="$(issue_of "$issues" "$n")"
    line="$(route_one "$i")"; lines+=("$line"); routed+=("$n")
    [ "$(jq -r .stage <<<"$line")" = epic ] || continue
    subs=(); while IFS= read -r s; do [ -z "$s" ] || subs+=("$s"); done < <(open_subs "$i")
    if [ "${#subs[@]}" -gt 0 ]; then
      sub_issues="$(read_issues "${subs[@]}")"
      for s in "${subs[@]}"; do lines+=("$(route_one "$(issue_of "$sub_issues" "$s")")"); routed+=("$s"); done
    fi
    while IFS= read -r line; do [ -z "$line" ] || lines+=("$line"); done < <(elsewhere "$i")
  done
  check_given "${routed[@]}"
  printf '%s\n' "${lines[@]}"
  exit 0
fi

# ---------- label ----------
if [ "$cmd" = label ]; then
  n="${nums[0]}"
  lab="$(answer_label "$slug" "$word" "$label_size")" || exit 1
  [ -n "$lab" ] || exit 0
  i="$(issue_of "$issues" "$n")"
  if jq -e --arg l "$lab" 'any(.labels.nodes[]?; (.name | ascii_downcase) == ($l | ascii_downcase))' <<<"$i" >/dev/null; then
    echo "labeled #$n $lab"; exit 0
  fi
  r="$(route_one "$i")"
  if [ "$(jq -r .stage <<<"$r")" != unlabeled ]; then
    echo "not labeled #$n: its labels route it: $(jq -r .reason <<<"$r")"; exit 0
  fi
  errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
  if edited="$(bash "$core/route/edit-labels.sh" "$slug" "$n" --add "$lab" 2>"$errf")"; then
    if [ "$edited" = made ]; then echo "labeled #$n $lab (made the label)"; else echo "labeled #$n $lab"; fi
  else
    e="$(tail -1 "$errf")"; echo "not labeled #$n: ${e#stop: }"
  fi
  exit 0
fi

# ---------- thread ----------
first="$(issue_of "$issues" "${nums[0]}")"
title="$(jq -r .title <<<"$first")"
epic=""
counted=()
if [ "$(jq '(.subIssues.nodes // []) | length' <<<"$first")" -gt 0 ]; then
  [ "${#nums[@]}" -eq 1 ] && [ "$step" = ship ] && [ -z "$on" ] || die_usage "$usage" "name an epic alone, or its tickets"
  epic="${nums[0]}"
  [ "$(jq -r .state <<<"$first")" = OPEN ] || die "#$epic is closed"
  [ -z "$(elsewhere "$first")" ] || die "#$epic has tickets in other repos: name its tickets in $slug"
  while IFS= read -r s; do [ -z "$s" ] || counted+=("$s"); done < <(open_subs "$first")
  [ "${#counted[@]}" -gt 0 ] || die "#$epic has no open ticket for /ship"
  issues="$(read_issues "${counted[@]}")"
else
  for n in "${nums[@]:1}"; do
    [ "$(jq '(.subIssues.nodes // []) | length' <<<"$(issue_of "$issues" "$n")")" -eq 0 ] || die_usage "$usage" "name an epic alone, or its tickets"
  done
  counted=("${nums[@]}")
fi

# rank <effort>: its place on the effort scale, so the highest wins.
rank() { case "$1" in low) echo 1 ;; medium) echo 2 ;; high) echo 3 ;; xhigh) echo 4 ;; max) echo 5 ;; *) echo 0 ;; esac; }

top=""; k=0; parents=""
for n in "${counted[@]}"; do
  i="$(issue_of "$issues" "$n")"
  r="$(route_one "$i")"
  if [ "$step" = ship ] && one_of 'task|waiting|done' "$(jq -r .stage <<<"$r")"; then continue; fi
  [ "$(jq -r .stop <<<"$r")" != true ] || die "$(jq -r .reason <<<"$r")"
  got="$(jq -r '.step // ""' <<<"$r")"
  [ -n "$got" ] || die "#$n has no step: $(jq -r .reason <<<"$r")"
  [ "$got" = "$step" ] || die "#$n goes to /$got, not /$step"
  k=$((k+1))
  parents="$parents$(jq -r '.parent // "none"' <<<"$r")"$'\n'
  if [ -z "$top" ] || [ "$(rank "$(jq -r .effort <<<"$r")")" -gt "$(rank "$(jq -r .effort <<<"$top")")" ]; then top="$r"; fi
done
[ "$k" -gt 0 ] || die "#${nums[0]} has no open ticket for /ship"
check_given "${counted[@]}"
[ "$k" -eq 1 ] || top="$(jq -c --arg k "$k" '.reason += " of \($k) tickets"' <<<"$top")"

# The /ship target: the whole epic, a run under the tickets' one parent, or
# a set in the order given.
issue_url() { printf 'https://github.com/%s/issues/%s' "$slug" "$1"; }
largs=()
if [ -n "$epic" ]; then
  largs=("$(issue_url "$epic")")
elif [ "${#nums[@]}" -gt 1 ]; then
  parent="$(sort -u <<<"$parents" | grep -v '^$')"
  if [ "$parent" != none ] && [ "$(grep -c . <<<"$parent")" -eq 1 ]; then
    largs=("$(issue_url "$parent")"); for n in "${nums[@]}"; do largs+=("#$n"); done
  else
    largs=("$(issue_url "${nums[0]}")"); for n in "${nums[@]:1}"; do largs+=("#$n"); done
  fi
else
  largs=("$(issue_url "${nums[0]}")")
  if [ -n "$on" ]; then
    gh_out pr view "$on" --repo "$slug" --json state \
      || { printf 'stop: gh could not read PR #%s in %s: %s\n' "$on" "$slug" "$err" >&2; exit 2; }
    [ "$(jq -r .state <<<"$out")" = OPEN ] || die "PR #$on is $(jq -r '.state | ascii_downcase' <<<"$out"), not open: nothing to stack on"
    largs+=(on "https://github.com/$slug/pull/$on")
  fi
fi
[ -z "$mode" ] || largs+=(--mode "$mode")
[ "$step" != ready-pr ] || largs+=(--pr "$(jq -r .pr <<<"$top")")
launch="$(bash "$core/launch/line.sh" "${largs[0]}" "$step" "${largs[@]:1}")" || exit
path="$(jq -r .path <<<"$launch")"
project="$(bash "$core/launch/project.sh" "$path")" || exit

# The heading starts a T3 thread title, which takes any text: #42, #42 #43,
# #42 on #80, and #70 for a whole epic. Too long: the numbers that fit in 27
# characters, then +<the rest>. A heading the user named is used as typed.
if [ -z "$heading" ]; then
  heading="#${nums[0]}"; j=1
  while [ "$j" -lt "${#nums[@]}" ] && [ $(( ${#heading} + ${#nums[$j]} + 2 )) -le 27 ]; do
    heading="$heading #${nums[$j]}"; j=$((j+1))
  done
  if [ "$j" -lt "${#nums[@]}" ]; then heading="$heading +$(( ${#nums[@]} - j ))"; fi
  [ -z "$on" ] || heading="$heading on #$on"
fi

jq -cn --argjson r "$top" --argjson l "$launch" --arg title "$heading $title" --arg project "$project" \
  '{step: $r.step, model: $r.model, model_from: $r.model_from, effort: $r.effort, effort_from: $r.effort_from,
    reason: $r.reason, path: $l.path, slash_command: $l.slash_command, message: $l.message,
    thread_title: $title, project: $project}'
