#!/usr/bin/env bash
# ready.sh: the readiness module. One readiness verdict for a PR, with its reason.
#
#   ready.sh <owner/repo> <number> [--me <login>] [--no-devin]
#
# Ready means, all at once: the PR is open and not a draft; Devin Review
# is `success` on the head commit (or --no-devin was given because the repo
# has none); no review thread waits for the author; no review asks for changes;
# GitHub says MERGEABLE with a merge state of CLEAN, HAS_HOOKS, or BEHIND;
# at least one check or status is on the head, with or without --no-devin;
# every check the base branch requires is on the head;
# and no other check on the head is red or pending. A merge state of
# BLOCKED counts as ready only when the one thing missing is an approving
# review. A merge state of UNKNOWN is GitHub still computing: it is asked
# again a few times before it counts.
#
# Each reason it is not ready is `waiting` when time alone clears it (Devin
# Review or a check still pending, no checks yet, GitHub still computing, a
# required check not posted while anything is pending) and `blocked` when it
# needs work or a person. Prints line 1 the verdict, line 2 the reason, then
# one line per review thread that waits for the author:
#   <thread node id> <path>:<line> last=<login> :: <first comment, 120 chars>
# The verdict and its exit code:
#   READY <url>                          0  the reason is `Devin Review: <state>
#   READY <url> (waiting for approval)   0  on <sha> · open threads: 0 · merge state: <state>`
#   BLOCKED <url>                        1  the reason lists every reason, `; ` between
#   WAITING <url>                        2  (no blocked reason among them)
# A bad flag or argument is `stop: …` on stderr, exit 64. Never merges.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo=""; num=""; me=""; no_devin=0
while [ $# -gt 0 ]; do
  case "$1" in
    --me) me="${2:-}"; shift 2 ;;
    --no-devin) no_devin=1; shift ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 64 ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$num" ]; then num="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 64; fi; shift ;;
  esac
done
[ -n "$repo" ] && [ -n "$num" ] || { echo 'usage: ready.sh <owner/repo> <number> [--me <login>] [--no-devin]' >&2; exit 64; }
[ -n "$me" ] || me="$(gh api user -q .login)"

facts=""
for _ in 1 2 3 4; do
  facts="$(bash "$here/pr-facts.sh" "$num" --repo "$repo")"
  grep -q '^MERGE_STATE=UNKNOWN$' <<<"$facts" || break
  sleep 5
done
get() { awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, ""); print; exit}' <<<"$facts"; }
url="$(get URL)"
sha7="$(get SHA | cut -c1-7)"

threads="$(bash "$here/open-threads.sh" "$repo" "$num" --me "$me")"
open="$(head -1 <<<"$threads" | cut -d= -f2)"

# blocked <reason> / waiting <reason>: add a reason, in check order.
why=(); has_blocked=0; has_waiting=0; approval=0
blocked() { why+=("$1"); has_blocked=1; }
waiting() { why+=("$1"); has_waiting=1; }

[ "$(get STATE)" = "OPEN" ] || blocked "state is $(get STATE)"
[ "$(get DRAFT)" != "true" ] || blocked "draft"
checks=$(( $(get CHECKS_RED) + $(get CHECKS_PENDING) + $(get CHECKS_GREEN) ))
devin="$(get DEVIN)"
if [ "$devin" = "none" ] && [ "$checks" -eq 0 ]; then
  waiting "no checks on $sha7 yet"
elif [ "$no_devin" -eq 0 ]; then
  case "$devin" in
    SUCCESS) ;;
    none) waiting "no Devin Review status on $sha7" ;;
    FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED|STARTUP_FAILURE) blocked "Devin Review is $devin" ;;
    *) waiting "Devin Review is $devin" ;;
  esac
fi
[ "$open" = "0" ] || blocked "$open review thread(s) wait for the author"
case "$(get MERGEABLE)" in
  MERGEABLE) ;;
  UNKNOWN) waiting "mergeable is UNKNOWN" ;;
  *) blocked "mergeable is $(get MERGEABLE)" ;;
esac
case "$(get MERGE_STATE)" in
  CLEAN|HAS_HOOKS|BEHIND) ;;
  DRAFT) ;;  # the draft line says it
  BLOCKED) approval=1 ;;
  UNKNOWN) waiting "merge state is UNKNOWN" ;;
  *) blocked "merge state is $(get MERGE_STATE)" ;;
esac
[ "$(get CHECKS_RED)" = "0" ] || blocked "$(get CHECKS_RED) other check(s) red"
[ "$(get CHECKS_PENDING)" = "0" ] || waiting "$(get CHECKS_PENDING) other check(s) pending"
# A required check not posted yet may still come while anything runs.
if [ -n "$(get REQUIRED_MISSING)" ]; then
  missing="required check(s) not posted: $(get REQUIRED_MISSING | sed 's/,/, /g')"
  if [ "$checks" -eq 0 ] || [ "$(get CHECKS_PENDING)" != "0" ] || { [ "$devin" != "SUCCESS" ] && [ "$devin" != "none" ]; }; then
    waiting "$missing"
  else
    blocked "$missing"
  fi
fi
[ "$(get REVIEW_DECISION)" != "CHANGES_REQUESTED" ] || blocked "changes requested"

# BLOCKED with no other reason: a missing approval is the one thing a person
# still owes, so that is ready; anything else blocks unseen.
if [ "${#why[@]}" -eq 0 ] && [ "$approval" -eq 1 ] && [ "$(get REVIEW_DECISION)" != "REVIEW_REQUIRED" ]; then
  blocked "merge state is BLOCKED"
fi

if [ "$has_blocked" -eq 1 ]; then verdict="BLOCKED $url"; code=1
elif [ "$has_waiting" -eq 1 ]; then verdict="WAITING $url"; code=2
elif [ "$approval" -eq 1 ]; then verdict="READY $url (waiting for approval)"; code=0
else verdict="READY $url"; code=0
fi
if [ "$code" -eq 0 ]; then
  if [ "$devin" = "none" ]; then d="none on this repo"; else d="$(tr '[:upper:]' '[:lower:]' <<<"$devin") on $sha7"; fi
  reason="Devin Review: $d · open threads: $open · merge state: $(get MERGE_STATE)"
else
  reason="$(IFS=';'; printf '%s' "${why[*]}" | sed 's/;/; /g')"
fi

printf '%s\n%s\n' "$verdict" "$reason"
tail -n +2 <<<"$threads"
exit "$code"
