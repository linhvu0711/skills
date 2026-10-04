#!/usr/bin/env bash
# ready.sh: is this PR ready to merge? One verdict, every fact behind it.
#
#   ready.sh <owner/repo> <number> [--me <login>] [--no-devin]
#
# Ready means, all at once: the PR is open and not a draft; Devin Review
# is `success` on the head commit (or --no-devin was given because the repo
# has none); no review thread waits for the author; no review asks for changes;
# GitHub says MERGEABLE with a merge state of CLEAN, HAS_HOOKS, or BEHIND;
# at least one check or status is on the head, with or without --no-devin;
# and no other check on the head is red or pending. A merge state of
# BLOCKED counts as ready only when the one thing missing is an approving
# review. A merge state of UNKNOWN is GitHub still computing: it is asked
# again a few times before it counts.
#
# Prints the facts, then `READY <url>`, or `READY <url> (waiting for
# approval)` when only a person's approval is left (exit 0), or
# `NOT READY <url>: <why>` (exit 1). Never merges.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo=""; num=""; me=""; no_devin=0
while [ $# -gt 0 ]; do
  case "$1" in
    --me) me="${2:-}"; shift 2 ;;
    --no-devin) no_devin=1; shift ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 1 ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$num" ]; then num="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 1; fi; shift ;;
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

threads="$(bash "$here/open-threads.sh" "$repo" "$num" --me "$me")"
open="$(head -1 <<<"$threads" | cut -d= -f2)"

printf '%s\n' "$facts"
printf 'OPEN_THREADS=%s\n' "$open"

why=(); blocked=0
[ "$(get STATE)" = "OPEN" ] || why+=("state is $(get STATE)")
[ "$(get DRAFT)" != "true" ] || why+=("draft")
checks=$(( $(get CHECKS_RED) + $(get CHECKS_PENDING) + $(get CHECKS_GREEN) ))
if [ "$(get DEVIN)" = "none" ] && [ "$checks" -eq 0 ]; then
  why+=("no checks on $(get SHA | cut -c1-7) yet")
elif [ "$no_devin" -eq 0 ]; then
  case "$(get DEVIN)" in
    SUCCESS) ;;
    none) why+=("no Devin Review status on $(get SHA | cut -c1-7)") ;;
    *) why+=("Devin Review is $(get DEVIN)") ;;
  esac
fi
[ "$open" = "0" ] || why+=("$open review thread(s) wait for the author")
[ "$(get MERGEABLE)" = "MERGEABLE" ] || why+=("mergeable is $(get MERGEABLE)")
case "$(get MERGE_STATE)" in
  CLEAN|HAS_HOOKS|BEHIND) ;;
  DRAFT) ;;  # the draft line says it
  BLOCKED) blocked=1 ;;
  *) why+=("merge state is $(get MERGE_STATE)") ;;
esac
[ "$(get CHECKS_RED)" = "0" ] || why+=("$(get CHECKS_RED) other check(s) red")
[ "$(get CHECKS_PENDING)" = "0" ] || why+=("$(get CHECKS_PENDING) other check(s) pending")
[ "$(get REVIEW_DECISION)" != "CHANGES_REQUESTED" ] || why+=("changes requested")

# BLOCKED with no other reason: a missing approval is the one thing a person
# still owes, so that is ready; anything else blocks unseen.
if [ "${#why[@]}" -eq 0 ] && [ "$blocked" -eq 1 ]; then
  if [ "$(get REVIEW_DECISION)" = "REVIEW_REQUIRED" ]; then
    printf 'READY %s (waiting for approval)\n' "$url"; exit 0
  fi
  why+=("merge state is BLOCKED")
fi
if [ "${#why[@]}" -eq 0 ]; then
  printf 'READY %s\n' "$url"; exit 0
fi
printf 'NOT READY %s: %s\n' "$url" "$(IFS=';'; printf '%s' "${why[*]}" | sed 's/;/; /g')"
exit 1
