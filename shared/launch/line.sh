#!/usr/bin/env bash
# line.sh: the launch line for one thread: the checkout it runs in and its
# first message. The orchestrator asks it after the Router picked the step;
# launch-t3.md then starts the thread from the line.
#
# Usage: line.sh <issue-url> <step> [#n ...] [on <pr-url>] [--mode review|ready|merge] [--pr <pr-url>]
#
# <step> is ship, triage, grill, ready-pr, or complete-task. --mode is
# /ship's ship mode; with none, the /ship thread picks it. ready-pr needs
# --pr, the open PR that closes the issue. Only ship takes more words, in
# /ship's forms: #n adds a ticket after <issue-url>, a run under that epic
# or a set after that first ticket, and `on <pr-url>` makes the issue a new
# layer on that PR's stack.
#
# Exit 0: one JSON line: path, command, mode, slash_command, message.
# slash_command is the step as the thread runs it, with its ship mode or
# --ready, as `/ship --merge`; message is slash_command, a space, and the
# target, as `/ship --merge #42` or `/ship #70 #12 #14`. The target is a number when gh in the
# checkout names the issue's repo, else the URL.
# Exit 1: no checkout of the repo, or a CLI it needs is not installed, its
# reason the last `stop:` line on stderr. Exit 64: a wrong command line, with the usage after the reason.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../route/labels.sh
. "$here/../route/labels.sh"
. "$here/../gh.sh"
. "$here/../die.sh"
step_list='ship|triage|grill|ready-pr|complete-task'
usage="usage: line.sh <issue-url> $step_list [#n ...] [on <pr-url>] [--mode $ship_mode_list] [--pr <pr-url>]"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

for c in git gh jq; do command -v "$c" >/dev/null || die "$c is not installed"; done

args=(); mode=""; pr_url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      one_of "$ship_mode_list" "${2:-}" || die_usage "$usage" "--mode must be $(spelled "$ship_mode_list"), got: ${2:-nothing}"
      mode="$2"; shift 2 ;;
    --pr) [ -n "${2:-}" ] || die_usage "$usage" "--pr needs a PR URL"; pr_url="$2"; shift 2 ;;
    -*) die_usage "$usage" "unexpected argument: $1" ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -ge 2 ] || die_usage "$usage"
issue_url="${args[0]}"; step="${args[1]}"
[[ "$issue_url" =~ ^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)/?$ ]] \
  || die_usage "$usage" "first argument must be a GitHub issue URL, got: $issue_url"
slug="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
one_of "$step_list" "$step" || die_usage "$usage" "step must be $(spelled "$step_list"), got: $step"
[ -z "$mode" ] || [ "$step" = ship ] || die_usage "$usage" "--mode goes only with ship"
[ "$step" != ready-pr ] || [ -n "$pr_url" ] || die_usage "$usage" "ready-pr needs --pr <pr-url>"

# /ship's extra words: tickets after the first, or the stack PR.
tickets=(); on_url=""; on_number=""
i=2
while [ "$i" -lt "${#args[@]}" ]; do
  [ "$step" = ship ] || die_usage "$usage" "#n and on go only with ship"
  a="${args[$i]}"
  if [ "$a" = on ]; then
    on_url="${args[$((i+1))]:-}"
    [[ "$on_url" =~ ^https://github\.com/$slug/pull/([0-9]+)/?$ ]] || die_usage "$usage" "on needs a PR URL in $slug, got: ${on_url:-nothing}"
    on_number="${BASH_REMATCH[1]}"; i=$((i+2))
  elif [[ "$a" =~ ^#?([0-9]+)$ ]]; then
    tickets+=("${BASH_REMATCH[1]}"); i=$((i+1))
  else
    die_usage "$usage" "unexpected argument: $a"
  fi
done
[ -z "$on_url" ] || [ "${#tickets[@]}" -eq 0 ] || die_usage "$usage" "on takes one issue"

# The checkout resolver finds the main checkout; its stop line is ours.
found="$(bash "$here/../checkout.sh" main "$slug")" || exit 1
path="${found#* MAIN=}"

# The thread runs in that checkout, and a skill reads a number as an issue
# of the repo gh sees there. A fork clone can make gh see its upstream, so
# the URLs stay unless gh there names this repo.
target="${pr_url:-$issue_url}"
url_rest=""; num_rest=""
for t in ${tickets[@]+"${tickets[@]}"}; do url_rest="$url_rest #$t"; num_rest="$num_rest #$t"; done
[ -z "$on_url" ] || { url_rest=" on $on_url"; num_rest=" on #$on_number"; }
[ -n "$pr_url" ] || target="$target$url_rest"
here_repo="$(cd "$path" && gh_out repo view --json nameWithOwner -q .nameWithOwner && printf '%s' "$out")" || here_repo=""
if [ "$(lower "$here_repo")" = "$(lower "$slug")" ]; then
  if [ -n "$pr_url" ]; then
    # A PR in another repo keeps its URL: a bare number would name a PR here.
    [ "$(lower "${pr_url%/pull/*}")" != "$(lower "https://github.com/$slug")" ] || target="#$(basename "$pr_url")"
  else
    target="#$number$num_rest"
  fi
fi

jq -cn --arg path "$path" --arg command "$step" --arg mode "$mode" --arg target "$target" \
  '("/\($command)" + (if $mode != "" then " --\($mode)" elif $command == "complete-task" then " --ready" else "" end)) as $slash
   | {path: $path, command: $command, mode: $mode, slash_command: $slash, message: "\($slash) \($target)"}'
