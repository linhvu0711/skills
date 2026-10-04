#!/usr/bin/env bash
# ready.sh: the readiness module. One readiness verdict for a PR, with its reason.
#
#   ready.sh <owner/repo> <number> [--me <login>] [--no-devin]
#            [--wait <sha>] [--timeout-sec 1800] [--none-sec 600] [--poll-sec 60]
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
# Devin Review is a commit status, or a check run, named `Devin Review`. It
# turns pending soon after a push and success a few minutes later, whether or
# not it found anything; it posts a review only when it did. devin_state is
# the one place that reads it. --wait <sha> first polls it on that commit,
# every --poll-sec, until it is success or red, until it was absent for
# --none-sec, or until it was pending for --timeout-sec; then the verdict. The
# wait polls an API, so it costs no model tokens; in Claude Code run it in the
# background, and the tool wakes the session when it ends.
#
# Each reason it is not ready is `waiting` when time alone clears it (Devin
# Review or a check still pending, no checks yet, GitHub still computing, a
# required check not posted while anything is pending) and `blocked` when it
# needs work or a person. Prints line 1 the verdict, line 2 the reason, then
# one line per review thread that waits for the author:
#   <thread node id> <path>:<line> last=<login> :: <first comment, 120 chars>
# A thread waits when it is not resolved and its last comment is not by --me
# (default: the login `gh api user` prints). Devin resolves a thread itself
# once a push fixes it, with a `✅ Resolved` reply, so those never wait.
# The verdict and its exit code:
#   READY <url>                          0  the reason is `Devin Review: <state>
#   READY <url> (waiting for approval)   0  on <sha> · open threads: 0 · merge state: <state>`
#   BLOCKED <url>                        1  the reason lists every reason, `; ` between
#   WAITING <url>                        2  (no blocked reason among them)
# A gh call that fails is BLOCKED with the reason `gh failed: <its last error
# line>`: in the wait after five fails in a row, anywhere else on the first.
# A bad flag or argument is `stop: …` on stderr, exit 64. Never merges.
set -euo pipefail

repo=""; num=""; me=""; no_devin=0; wait_sha=""; timeout=1800; none_sec=600; poll=60
while [ $# -gt 0 ]; do
  case "$1" in
    --me) me="${2:-}"; shift 2 ;;
    --no-devin) no_devin=1; shift ;;
    --wait) wait_sha="${2:-}"; shift 2 ;;
    --timeout-sec) timeout="${2:-}"; shift 2 ;;
    --none-sec) none_sec="${2:-}"; shift 2 ;;
    --poll-sec) poll="${2:-}"; shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 64 ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$num" ]; then num="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 64; fi; shift ;;
  esac
done
[ -n "$repo" ] && [ -n "$num" ] || { echo 'usage: ready.sh <owner/repo> <number> [--me <login>] [--no-devin] [--wait <sha>] [--timeout-sec N] [--none-sec N] [--poll-sec N]' >&2; exit 64; }
owner="${repo%%/*}"; name="${repo##*/}"
url="https://github.com/$repo/pull/$num"  # gh pr view's URL replaces it once read

# gh_out <args>: gh's answer in `out`; when it fails, its last line in `err`
# and return 1.
gh_out() {
  if out="$(gh "$@" 2>&1)"; then return 0; fi
  err="$(printf '%s\n' "$out" | tail -1)"; return 1
}

# gh_failed <err>: the BLOCKED verdict for a gh call that failed.
gh_failed() { printf 'BLOCKED %s\ngh failed: %s\n' "$url" "$1"; exit 1; }

# devin_state <sha>: sets s to the Devin Review state on that commit, upper
# case (SUCCESS, PENDING, FAILURE, …), or empty when there is none. The commit
# status first, read across every page, then the check runs asked for by
# name. A failed gh call sets err, returns 1.
devin_state() {
  gh_out api "repos/$repo/commits/$1/status" --paginate -q '[.statuses[] | select(.context=="Devin Review") | .state] | first // empty' || return 1
  if [ -z "$out" ]; then
    gh_out api "repos/$repo/commits/$1/check-runs?check_name=Devin%20Review" -q '[.check_runs[] | select(.name=="Devin Review") | (.conclusion // .status)] | first // empty' || return 1
  fi
  s="$(printf '%s' "$out" | head -1 | tr '[:lower:]' '[:upper:]')"
}
devin_red() { case "$1" in FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED|STARTUP_FAILURE) return 0 ;; esac; return 1; }

# pr_facts: sets facts, one KEY=value per line, read only through get. Keys:
# URL STATE DRAFT SHA MERGEABLE MERGE_STATE REVIEW_DECISION CHECKS_RED
# CHECKS_PENDING CHECKS_GREEN REQUIRED_MISSING. The CHECKS_* counts cover every
# status and check run on the head but Devin Review. REQUIRED_MISSING lists,
# comma separated, the checks that the base branch requires (branch protection
# and rulesets) and the head does not have at all. A failed gh call sets err,
# returns 1.
pr_facts() {
  local json base prot rules
  gh_out pr view "$num" --repo "$repo" --json url,state,isDraft,baseRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup || return 1
  json="$out"
  # Both read with plain read access; a repo with neither gives []. One path
  # segment: a slash in the branch name is sent as %2F.
  base="$(jq -r '.baseRefName | @uri' <<<"$json")"
  gh_out api "repos/$repo/branches/$base" -q '.protection.required_status_checks.contexts // []' || return 1
  prot="$out"
  gh_out api "repos/$repo/rules/branches/$base" -q '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' || return 1
  rules="$out"
  facts="$(jq -r --argjson prot "$prot" --argjson rules "$rules" '
    def st: (.state // .conclusion // .status // "UNKNOWN") | ascii_upcase;
    def is_devin: ((.context // .name // "") == "Devin Review");
    def others: [.statusCheckRollup[]? | select(is_devin | not)];
    def red: ["FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"];
    def green: ["SUCCESS","NEUTRAL","SKIPPED"];
    "URL=\(.url)",
    "STATE=\(.state)",
    "DRAFT=\(.isDraft)",
    "SHA=\(.headRefOid)",
    "MERGEABLE=\(.mergeable)",
    "MERGE_STATE=\(.mergeStateStatus)",
    "REVIEW_DECISION=\(.reviewDecision // "")",
    "CHECKS_RED=" + ([others[] | select(st as $s | red | index($s))] | length | tostring),
    "CHECKS_PENDING=" + ([others[] | select(st as $s | (red + green) | index($s) | not)] | length | tostring),
    "CHECKS_GREEN=" + ([others[] | select(st as $s | green | index($s))] | length | tostring),
    "REQUIRED_MISSING=" + ([.statusCheckRollup[]? | .context // .name] as $have
      | ($prot + $rules) | unique | map(select(. as $c | $have | index($c) | not)) | join(","))
  ' <<<"$json")"
}
get() { awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, ""); print; exit}' <<<"$facts"; }

# open_threads: sets threads, `OPEN=<n>` first, then one line per thread that
# waits for the author. A failed gh call sets err, returns 1.
open_threads() {
  local q all page after
  # shellcheck disable=SC2016 # the $ names are GraphQL variables
  q='query($o:String!,$r:String!,$n:Int!,$after:String){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100,after:$after){pageInfo{hasNextPage endCursor}nodes{id isResolved path line opener:comments(first:1){nodes{body}}latest:comments(last:1){nodes{author{login}body}}}}}}}'
  all='[]'; after=""
  while :; do
    gh_out api graphql -f query="$q" -F o="$owner" -F r="$name" -F n="$num" ${after:+-F after="$after"} -q '.data.repository.pullRequest.reviewThreads' || return 1
    page="$out"
    all="$(jq -c --argjson p "$page" '. + $p.nodes' <<<"$all")"
    [ "$(jq -r '.pageInfo.hasNextPage' <<<"$page")" = "true" ] || break
    after="$(jq -r '.pageInfo.endCursor' <<<"$page")"
  done
  threads="$(jq -r --arg me "$me" '
    [ .[] | select(.isResolved | not)
          | .latest.nodes[0] as $l
          | select($l.author.login != $me)
          | select($l.body | test("^\\s*✅ \\*\\*Resolved\\*\\*") | not) ]
    | "OPEN=\(length)",
      (.[] | "\(.id) \(.path):\(.line // "-") last=\(.latest.nodes[0].author.login) :: \(.opener.nodes[0].body | gsub("<!--[^>]*-->"; "") | gsub("\\s+"; " ") | .[:120])")
  ' <<<"$all")"
}

if [ -n "$wait_sha" ] && [ "$no_devin" -eq 0 ]; then
  waited=0; fails=0; s=""
  while :; do
    if devin_state "$wait_sha"; then
      fails=0
      if [ "$s" = SUCCESS ] || devin_red "$s"; then break; fi
      if [ -z "$s" ]; then [ "$waited" -lt "$none_sec" ] || break
      else [ "$waited" -lt "$timeout" ] || break
      fi
    else
      fails=$((fails + 1))
      [ "$fails" -lt 5 ] || gh_failed "$err"
    fi
    sleep "$poll"; waited=$((waited + poll))
  done
fi

if [ -z "$me" ]; then gh_out api user -q .login || gh_failed "$err"; me="$out"; fi
facts=""
for _ in 1 2 3 4; do
  pr_facts || gh_failed "$err"
  grep -q '^MERGE_STATE=UNKNOWN$' <<<"$facts" || break
  sleep 5
done
url="$(get URL)"
sha7="$(get SHA | cut -c1-7)"
devin_state "$(get SHA)" || gh_failed "$err"
devin="${s:-none}"

open_threads || gh_failed "$err"
open="$(head -1 <<<"$threads" | cut -d= -f2)"

# blocked <reason> / waiting <reason>: add a reason, in check order.
why=(); has_blocked=0; has_waiting=0; approval=0
blocked() { why+=("$1"); has_blocked=1; }
waiting() { why+=("$1"); has_waiting=1; }

[ "$(get STATE)" = "OPEN" ] || blocked "state is $(get STATE)"
[ "$(get DRAFT)" != "true" ] || blocked "draft"
checks=$(( $(get CHECKS_RED) + $(get CHECKS_PENDING) + $(get CHECKS_GREEN) ))
[ "$devin" != "none" ] || [ "$checks" -ne 0 ] || waiting "no checks on $sha7 yet"
if [ "$no_devin" -eq 0 ]; then
  case "$devin" in
    SUCCESS) ;;
    none) waiting "no Devin Review status on $sha7" ;;
    *) if devin_red "$devin"; then blocked "Devin Review is $devin"; else waiting "Devin Review is $devin"; fi ;;
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
# A required check not posted yet may still come while a check or Devin
# Review runs, or before anything at all has posted.
if [ -n "$(get REQUIRED_MISSING)" ]; then
  missing="required check(s) not posted: $(get REQUIRED_MISSING | sed 's/,/, /g')"
  if [ "$(get CHECKS_PENDING)" != "0" ] || { [ "$devin" = "none" ] && [ "$checks" -eq 0 ]; } \
    || { [ "$devin" != "SUCCESS" ] && [ "$devin" != "none" ] && ! devin_red "$devin"; }; then
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
