#!/usr/bin/env bash
# ready.sh: the readiness module. One readiness verdict for a PR, with its reason.
#
#   ready.sh <owner/repo> <number> [--me <login>]
#            [--watch <sha>] [--settle-sec 60] [--timeout-sec 1800] [--poll-sec 60]
#
# Every check on the head counts the same: a CI check run, a commit status,
# and a review bot's check (Devin Review, CodeRabbit, Cursor Bugbot, Greptile
# Review, Macroscope), with no list of names, so a new, renamed, or skipped bot
# needs nothing here.
#
# Ready means, all at once: the PR is open and not a draft; no review thread
# waits for the author; no review asks for changes; GitHub says MERGEABLE
# with a merge state of CLEAN, HAS_HOOKS, or BEHIND; at least one check or
# status is on the head; every check the base branch requires is on the head;
# and no check on the head is red or pending. A merge state of BLOCKED counts
# as ready only when the one thing missing is an approving review. A merge
# state of UNKNOWN is GitHub still computing: it is asked again a few times
# before it counts.
#
# A review bot starts its check seconds after a push and ends it after its
# comments, and one that finds problems ends grey (neutral), not red. So
# --watch <sha> first sleeps --settle-sec, for the checks to start, then reads
# the head's checks and threads every --poll-sec until none is pending, the
# head is no longer <sha>, or --timeout-sec passed; then the verdict. A red
# check does not end the watch. Each poll prints one line per red check and
# per waiting thread it has not printed yet, in the order they come:
#   RED <name> · workflow <workflow> · step <failed step> · <state> · <url>
#   THREAD <thread line, as below>
# A check is known by its URL, so a rerun's new attempt prints again; one with
# no URL is known by its name. The failed step comes from the Actions job the
# URL names; `-` for a check from outside Actions, an unknown workflow, or a
# failed lookup. The watch polls an API, so it costs no model tokens; in
# Claude Code run it under a Monitor, so each line wakes the session.
#
# Each reason it is not ready is `waiting` when time alone clears it (a check
# still pending, no checks yet, GitHub still computing, a required check not
# posted while a check is pending, a head that moved during --watch) and `blocked` when it needs work or a
# person. Prints line 1 the verdict, line 2 the reason, then one line per
# review thread that waits for the author:
#   <thread node id> <path>:<line> last=<login> :: <first comment, 120 chars>
# A thread waits when it is not resolved and its last comment is not by --me
# (default: the login `gh api user` prints). Devin resolves a thread itself
# once a push fixes it, with a `✅ Resolved` reply, so those never wait.
# The verdict and its exit code:
#   READY <url>                          0  the reason is `checks: <n> green on <sha7>
#   READY <url> (waiting for approval)   0  · open threads: 0 · merge state: <state>`
#   BLOCKED <url>                        1  the reason lists every reason, `; ` between;
#   WAITING <url>                        2  (no blocked reason among them) red and pending
#                                           checks are named, as in `1 check(s) red: test`
# A gh call that fails is BLOCKED with the reason `gh failed: <its last error
# line>`: in the watch after five fails in a row, anywhere else on the first.
# A bad flag or argument is `stop: …` on stderr, exit 64. Never merges.
set -euo pipefail

repo=""; num=""; me=""; watch_sha=""; settle=60; timeout=1800; poll=60
while [ $# -gt 0 ]; do
  case "$1" in
    --me) me="${2:-}"; shift 2 ;;
    --watch) watch_sha="${2:-}"; shift 2 ;;
    --timeout-sec) timeout="${2:-}"; shift 2 ;;
    --settle-sec) settle="${2:-}"; shift 2 ;;
    --poll-sec) poll="${2:-}"; shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 64 ;;
    *) if [ -z "$repo" ]; then repo="$1"; elif [ -z "$num" ]; then num="$1"; else printf 'stop: unexpected argument %s\n' "$1" >&2; exit 64; fi; shift ;;
  esac
done
[ -n "$repo" ] && [ -n "$num" ] || { echo 'usage: ready.sh <owner/repo> <number> [--me <login>] [--watch <sha>] [--settle-sec N] [--timeout-sec N] [--poll-sec N]' >&2; exit 64; }

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

# pr_facts: sets facts, one KEY=value per line, read only through get. Keys:
# URL STATE DRAFT SHA MERGEABLE MERGE_STATE REVIEW_DECISION CHECKS_RED
# CHECKS_PENDING CHECKS_GREEN RED_NAMES PENDING_NAMES REQUIRED_MISSING. The
# CHECKS_* counts cover every status and check run on the head, and the
# *_NAMES list the red and the pending ones, comma separated. REQUIRED_MISSING lists,
# comma separated, the checks that the base branch requires (branch protection
# and rulesets) and the head does not have at all. It also sets reds, one
# tab-separated line per red check: key, name, workflow, state, url. A failed
# gh call sets err, returns 1.
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
    def all: [.statusCheckRollup[]?];
    def red: ["FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"];
    def green: ["SUCCESS","NEUTRAL","SKIPPED"];
    def is_red: st as $s | red | index($s);
    def is_pending: st as $s | (red + green) | index($s) | not;
    "URL=\(.url)",
    "STATE=\(.state)",
    "DRAFT=\(.isDraft)",
    "SHA=\(.headRefOid)",
    "MERGEABLE=\(.mergeable)",
    "MERGE_STATE=\(.mergeStateStatus)",
    "REVIEW_DECISION=\(.reviewDecision // "")",
    "CHECKS_RED=" + ([all[] | select(is_red)] | length | tostring),
    "CHECKS_PENDING=" + ([all[] | select(is_pending)] | length | tostring),
    "CHECKS_GREEN=" + ([all[] | select(st as $s | green | index($s))] | length | tostring),
    "RED_NAMES=" + ([all[] | select(is_red) | .context // .name] | join(", ")),
    "PENDING_NAMES=" + ([all[] | select(is_pending) | .context // .name] | join(", ")),
    "REQUIRED_MISSING=" + ([.statusCheckRollup[]? | .context // .name] as $have
      | ($prot + $rules) | unique | map(select(. as $c | $have | index($c) | not)) | join(","))
  ' <<<"$json")"
  reds="$(jq -r '
    def st: (.state // .conclusion // .status // "UNKNOWN") | ascii_upcase;
    def red: ["FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"];
    .statusCheckRollup[]? | st as $s | select(red | index($s))
    | (.detailsUrl // .targetUrl // "" | if . == "" then "-" else . end) as $u
    | (.context // .name) as $n
    | [(if $u == "-" then $n else $u end), $n, (.workflowName // "" | if . == "" then "-" else . end), $s, $u]
    | @tsv
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

# failed_step <url>: the first failed step of the Actions job the URL names,
# or `-`.
failed_step() {
  local job
  [[ "$1" =~ /actions/runs/[0-9]+/job/([0-9]+) ]] || { echo -; return; }
  job="${BASH_REMATCH[1]}"
  if gh_out api "repos/$repo/actions/jobs/$job" -q '[.steps[]? | select(.conclusion == "failure") | .name][0] // "-"'; then
    printf '%s\n' "${out:--}"
  else
    echo -
  fi
}

# print_reds and print_threads: each red check, or each waiting thread, not
# printed yet, one line each; seen holds the keys printed so far.
print_reds() {
  local key name workflow state link
  while IFS=$'\t' read -r key name workflow state link; do
    [ -n "$key" ] || continue
    grep -Fxq -- "red $key" <<<"$seen" && continue
    seen+=$'\n'"red $key"
    printf 'RED %s · workflow %s · step %s · %s · %s\n' "$name" "$workflow" "$(failed_step "$link")" "$state" "$link"
  done <<<"$reds"
}
print_threads() {
  local id line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line%% *}"
    grep -Fxq -- "thread $id" <<<"$seen" && continue
    seen+=$'\n'"thread $id"
    printf 'THREAD %s\n' "$line"
  done < <(tail -n +2 <<<"$threads")
}

if [ -z "$me" ]; then gh_out api user -q .login || gh_failed "$err"; me="$out"; fi

if [ -n "$watch_sha" ]; then
  sleep "$settle"
  waited=0; fails=0; seen=""
  while :; do
    # A failed thread list must not hold back the red checks already read.
    if pr_facts && { print_reds; open_threads; }; then
      fails=0
      print_threads
      [ "$(get SHA)" = "$watch_sha" ] || break
      [ "$(get CHECKS_PENDING)" != "0" ] || break
      [ "$waited" -lt "$timeout" ] || break
    else
      fails=$((fails + 1))
      [ "$fails" -lt 5 ] || gh_failed "$err"
    fi
    sleep "$poll"; waited=$((waited + poll))
  done
fi
facts=""
for _ in 1 2 3 4; do
  pr_facts || gh_failed "$err"
  grep -q '^MERGE_STATE=UNKNOWN$' <<<"$facts" || break
  sleep 5
done
url="$(get URL)"
sha7="$(get SHA | cut -c1-7)"

open_threads || gh_failed "$err"
open="$(head -1 <<<"$threads" | cut -d= -f2)"

# blocked <reason> / waiting <reason>: add a reason, in check order.
why=(); has_blocked=0; has_waiting=0; approval=0
blocked() { why+=("$1"); has_blocked=1; }
waiting() { why+=("$1"); has_waiting=1; }

[ "$(get STATE)" = "OPEN" ] || blocked "state is $(get STATE)"
# A push after the watched sha: its checks are new, so the pending ones
# are not a timeout. The caller pulls and watches the new head.
[ -z "$watch_sha" ] || [ "$(get SHA)" = "$watch_sha" ] || waiting "head moved to $sha7"
[ "$(get DRAFT)" != "true" ] || blocked "draft"
checks=$(( $(get CHECKS_RED) + $(get CHECKS_PENDING) + $(get CHECKS_GREEN) ))
[ "$checks" -ne 0 ] || waiting "no checks on $sha7 yet"
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
[ "$(get CHECKS_RED)" = "0" ] || blocked "$(get CHECKS_RED) check(s) red: $(get RED_NAMES)"
[ "$(get CHECKS_PENDING)" = "0" ] || waiting "$(get CHECKS_PENDING) check(s) pending: $(get PENDING_NAMES)"
# A required check not posted yet may still come while a check runs, or
# before anything at all has posted.
if [ -n "$(get REQUIRED_MISSING)" ]; then
  missing="required check(s) not posted: $(get REQUIRED_MISSING | sed 's/,/, /g')"
  if [ "$(get CHECKS_PENDING)" != "0" ] || [ "$checks" -eq 0 ]; then
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
  reason="checks: $(get CHECKS_GREEN) green on $sha7 · open threads: $open · merge state: $(get MERGE_STATE)"
else
  reason="$(IFS=';'; printf '%s' "${why[*]}" | sed 's/;/; /g')"
fi

printf '%s\n%s\n' "$verdict" "$reason"
tail -n +2 <<<"$threads"
exit "$code"
