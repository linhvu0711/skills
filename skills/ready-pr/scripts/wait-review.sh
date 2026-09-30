#!/usr/bin/env bash
# wait-review.sh: block until Devin Review has reported on one commit.
#
#   wait-review.sh <owner/repo> <sha> [--timeout-sec 1800] [--none-sec 600] [--poll-sec 60]
#
# Devin Review is a commit status with context `Devin Review`. It appears
# as pending soon after a push and turns success after a few minutes,
# whether or not it found anything. It posts a review only when it did.
#
# Prints one line, `DEVIN=<state> SHA=<sha> WAITED=<s>`, and exits:
#   0  success
#   1  failure or error
#   2  still pending when --timeout-sec ran out
#   3  no status at all for --none-sec seconds (Devin Review is not on this repo, or is late)
# Polls an API, so it costs no model tokens while it waits. In Claude Code
# run it in the background; the tool wakes the session when it ends.
set -euo pipefail

repo=""; sha=""; timeout=1800; none_sec=600; poll=60
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-sec) timeout="${2:-}"; shift 2 ;;
    --none-sec) none_sec="${2:-}"; shift 2 ;;
    --poll-sec) poll="${2:-}"; shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 1 ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$sha" ]; then sha="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 1; fi; shift ;;
  esac
done
[ -n "$repo" ] && [ -n "$sha" ] || { echo 'usage: wait-review.sh <owner/repo> <sha> [--timeout-sec N] [--none-sec N] [--poll-sec N]' >&2; exit 64; }

state_of() {
  local s
  s="$(gh api "repos/$repo/commits/$sha/status" -q '[.statuses[] | select(.context=="Devin Review") | .state] | first // empty' 2>/dev/null || true)"
  if [ -z "$s" ]; then
    s="$(gh api "repos/$repo/commits/$sha/check-runs" -q '[.check_runs[] | select(.name=="Devin Review") | (.conclusion // .status)] | first // empty' 2>/dev/null || true)"
  fi
  printf '%s' "$s" | tr '[:upper:]' '[:lower:]'
}

waited=0
while :; do
  s="$(state_of)"
  case "$s" in
    success)
      printf 'DEVIN=success SHA=%s WAITED=%s\n' "$sha" "$waited"; exit 0 ;;
    failure|error|timed_out|cancelled|action_required)
      printf 'DEVIN=%s SHA=%s WAITED=%s\n' "$s" "$sha" "$waited"; exit 1 ;;
    "")
      if [ "$waited" -ge "$none_sec" ]; then printf 'DEVIN=none SHA=%s WAITED=%s\n' "$sha" "$waited"; exit 3; fi ;;
    *)
      if [ "$waited" -ge "$timeout" ]; then printf 'DEVIN=pending SHA=%s WAITED=%s\n' "$sha" "$waited"; exit 2; fi ;;
  esac
  sleep "$poll"; waited=$((waited + poll))
done
