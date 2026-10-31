#!/usr/bin/env bash
# orchestrate.sh: the orchestrator's check, and the one writer of a run's state file.
#
# Usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>...
#        orchestrate.sh check <owner/repo>
#        orchestrate.sh started <owner/repo> <n> <stage> <thread-id> <link>
#        orchestrate.sh started <owner/repo> <n> <stage> --failed <why>
#        orchestrate.sh proposed <owner/repo> <n> grill|triage|ship|ready-pr|task|close|unsure [--size S]
#        orchestrate.sh change <owner/repo> add <n>... | remove <n>... | restart <n>
#                          | ship review|ready|merge <n>|all | use <n>|all [--model M] [--effort E]
#                          | answer <n>|all yes|skip|grill|triage|ship|ready-pr|task|close
#        orchestrate.sh timer <owner/repo> --every <min> | pause | resume | stop
#        orchestrate.sh resume <owner/repo> --thread <thread-id> --env <environment-id>
#        orchestrate.sh watch <owner/repo> [--once [--token <t>] | --loop <run-dir> <token>]
#
# A run lives in ${ORCHESTRATE_HOME:-~/.agents/orchestrate}/<owner>-<repo>/<run-id>/,
# outside every checkout, and holds one state.json: only what GitHub and T3
# do not hold. Every command works on the repo's newest run. A good check
# also writes board.json there, the board page's data, and start and resume
# copy the page in as board.html, so one folder serves both.
#
# check reads every issue of the set from GitHub and the threads from T3,
# puts each issue in its stage, and prints the threads to start. Each start
# is claimed in the state file before it is printed, so a second check never
# starts it again. It launches nothing: the agent starts each thread with
# T3's tools and records it with `started`. It also lists the unlabeled
# issues with no proposal yet; the agent proposes a route and a size for
# each and records them with `proposed`. Each issue row, and the line, say
# `changed` against what the last good check saw, so the timer can stay quiet.
# It also finds each open PR with conflicts whose thread finished its turn,
# once per head; a watcher check claims it in the state file like a start and
# sends that thread `/ready-pr <pr-url>` itself.
#
# watch starts the watcher, a background loop that runs one watcher check
# every few minutes, with no chat turn, and wakes the orchestrator thread
# only when the agent must act. watch --once is one watcher check: it reads
# the run as check does, claims nothing, and records only the check time, so
# the agent's own check still claims the starts, joins the new issues, and
# marks what changed.
#
# A live run is running or paused; a repo has at most one. A stopped run goes
# on with resume; a done run is over.
#
# Exit 0: one JSON line on stdout for start, check, proposed, timer, and
# resume; nothing for started and change.
# Exit 1: something stopped us; the reason is the last line on stderr.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$here/../../../shared"
. "$core/kickoff/labels.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

usage="usage: orchestrate.sh start|check|started|proposed|change|timer|resume|watch <owner/repo> ..."
[ $# -ge 2 ] || die "$usage"
cmd="$1"; slug="$2"; shift 2
[[ "$slug" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]] || die "the repo must be owner/repo, got: $slug"
owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
runs="${ORCHESTRATE_HOME:-$HOME/.agents/orchestrate}/$owner-$repo"

# in_t3: T3 Code sets T3CODE_CLI_PATH to its own t3 command in every chat.
in_t3() {
  t3="${T3CODE_CLI_PATH:-}"
  [ -n "$t3" ] && [ -x "$t3" ] || die "not inside T3 Code"
}

# ---------- state ----------
# The run-id is the UTC start time, so the newest run sorts last.
newest_run() {
  local d
  d="$(find "$runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)"
  [ -n "$d" ] || die "no run in $slug; say /orchestrate <set>"
  run="$d"; lock_run; S="$(cat "$run/state.json")"
}

# lock_run: the run's lock, held until this script exits, so the watcher
# and the agent's commands never write state.json at once. mkdir is the
# atomic step; the pid inside lets a later command take over the lock of a
# process that died holding it. A holder that has not written its pid yet
# counts as alive.
lock_run() {
  local i pid
  for i in $(seq 600); do
    if mkdir "$run/.lock" 2>/dev/null; then
      echo $$ > "$run/.lock/pid"; locked="$run/.lock"; return
    fi
    pid="$(cat "$run/.lock/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$run/.lock"; continue; fi
    sleep 0.2
  done
  die "the run of $slug is busy: another orchestrate.sh holds its lock"
}

# save: the whole state, under a temp name, then renamed into place, so a
# crash never leaves half a file.
save() {
  local tmp
  tmp="$(mktemp "$run/.state.XXXXXX")"
  jq . <<<"$S" > "$tmp"
  mv "$tmp" "$run/state.json"
}

# copy_page: the board page into the run folder, the same way, so a resume
# brings a newer page to an old run. The page names its run: serve.sh reuses
# a server that gives back the same bytes, so two runs' pages, of any repo, must differ.
copy_page() {
  local tmp
  tmp="$(mktemp "$run/.board.XXXXXX")"
  sed "s#<meta name=\"orchestrate-run\" content=\"\">#<meta name=\"orchestrate-run\" content=\"$slug/$(basename "$run")\">#" \
    "$here/../assets/board.html" > "$tmp"
  mv "$tmp" "$run/board.html"
}

# ---------- GitHub ----------
fields='number title state createdAt labels(first:50){nodes{name}} subIssues(first:100){nodes{number state}} blockedBy(first:50){nodes{number state}} closedByPullRequestsReferences(first:20,includeClosedPrs:false){nodes{number url state createdAt body mergeable headRefOid}}'

# read_issues <n>...: one GraphQL call for all of them, printed as one
# object keyed by number. A failed call leaves gh's stderr in errf.
read_issues() {
  local q="" n out
  for n in "$@"; do q="$q i$n: issue(number: $n) { ...F }"; done
  # shellcheck disable=SC2016 # the $ names are GraphQL variables
  if ! out="$(gh api graphql -f query='query($o: String!, $r: String!) { repository(owner: $o, name: $r) {'"$q"' } } fragment F on Issue { '"$fields"' }' \
      -F o="$owner" -F r="$repo" 2>"$errf")"; then
    return 1
  fi
  jq -c --args '.data.repository as $r | [$ARGS.positional[] | {key: ., value: $r["i" + .]}] | from_entries' "$@" <<<"$out"
}
errf="$(mktemp)"; locked=""; trap 'rm -f "$errf"; [ -z "$locked" ] || rm -rf "$locked"' EXIT

# size_label <issue json>: the issue's size, from its first size label.
size_label() {
  local lab s
  while IFS= read -r lab; do
    s="$(size_of "$lab")"; [ -z "$s" ] || { echo "$s"; return; }
  done < <(jq -r '.labels.nodes[].name' <<<"$1")
}

# label_kind <issue json>: the issue's kind, from its labels in one order:
# task (manual), bug, seed, sized (a size label), or unlabeled.
label_kind() {
  local labels
  labels="$(jq -r '.labels.nodes[].name | ascii_downcase' <<<"$1")"
  if grep -qx manual <<<"$labels"; then echo task
  elif grep -qx bug <<<"$labels"; then echo bug
  elif grep -qx seed <<<"$labels"; then echo seed
  elif [ -n "$(size_label "$1")" ]; then echo sized
  else echo unlabeled; fi
}

# chip <issue json>: the card's chip, the issue's kind, and for a sized
# issue its type and size. A ticket's type is its title's leading word,
# `[fix] x` or `fix(scope): x`, as issue-rules.md § Title writes it.
chip() {
  local kind type
  kind="$(label_kind "$1")"
  case "$kind" in
    sized)
      type="$(jq -r '.title | (capture("^\\[(?<t>[A-Za-z]+)\\]") // capture("^(?<t>[A-Za-z]+)(\\([^)]*\\))?!?:") // {t: "ticket"}).t | ascii_downcase' <<<"$1")"
      echo "$type · $(size_label "$1")" ;;
    *) echo "$kind" ;;
  esac
}

# stage <issue json> <run start>: where the issue is: closed, a task,
# an epic, and an open PR first, then the kind. Closed comes first, since a
# closed seed keeps its label. A PR counts only when it was open before the
# run: a PR the run's own thread opened is that thread's work.
stage() {
  local kind
  kind="$(label_kind "$1")"
  if [ "$(jq -r .state <<<"$1")" = CLOSED ]; then echo done
  elif [ "$kind" = task ]; then echo task
  elif [ "$(jq '.subIssues.nodes | length' <<<"$1")" -gt 0 ]; then echo epic
  elif [ "$(jq --arg t "$2" '[.closedByPullRequestsReferences.nodes[] | select(.state == "OPEN" and .createdAt < $t)] | length' <<<"$1")" -gt 0 ]; then echo pr
  else
    case "$kind" in
      sized) echo ticket ;;
      *) echo "$kind" ;;
    esac
  fi
}

# skill <stage>: the command a thread at that stage starts with, or
# nothing. A ticket starts /ship; ship_mode says how far it goes.
skill() {
  case "$1" in
    seed) echo grill ;;
    bug) echo triage ;;
    ticket) echo ship ;;
    pr) echo ready-pr ;;
  esac
}

# The ship mode the user set for issue $n, or "" when the /ship thread picks
# it. A run started before /ship holds `full` or `ready`; `full` reads as
# merge, so a live run never starts a skill that is gone.
# shellcheck disable=SC2016 # the $ names are jq variables
ship_mode_jq='def ship_mode($n): (.ship[$n] // .ship.default // "") | if . == "full" then "merge" else . end;'
ship_mode() { jq -r --arg n "$1" "$ship_mode_jq"' ship_mode($n)' <<<"$S"; }

# answer_skill <word>: the skill an answer or a proposed route names, or
# nothing for one that starts no thread.
answer_skill() {
  case "$1" in
    grill|triage|ship|ready-pr) echo "$1" ;;
  esac
}

# decide_for <n> <skill>: decide.sh's line for #n's thread, with the
# ship mode the user set for a /ship thread and
# run's model and effort picks, so a proposal and its launch read the same
# row. The proposal's size goes every time: decide.sh ignores it for a ticket
# with a size label, so the label picks the row. Its stop line is left in errf.
decide_for() {
  local flags=() model effort size="" mode
  model="$(jq -r --arg n "$1" '.use[$n].model // .use.all.model // empty' <<<"$S")"
  effort="$(jq -r --arg n "$1" '.use[$n].effort // .use.all.effort // empty' <<<"$S")"
  size="$(jq -r --arg n "$1" '(.proposals // {})[$n].size // empty' <<<"$S")"
  [ -z "$model" ] || flags+=(--model "$model")
  [ -z "$effort" ] || flags+=(--effort "$effort")
  [ -z "$size" ] || flags+=(--size "$1=$size")
  if [ "$2" = ship ]; then
    mode="$(ship_mode "$1")"
    [ -z "$mode" ] || flags+=(--mode "$mode")
  fi
  bash "$core/kickoff/decide.sh" --command "$2" ${flags[@]+"${flags[@]}"} "https://github.com/$slug/issues/$1" 2>"$errf"
}

# joins: a jq program on the issues just read, with the state as $S: the
# numbers they bring that are neither in the set nor removed. A follow-up is
# a `#<n>:` line under `## Follow-ups` in the PR body, as pr-shape.md writes
# it; /capture puts no other link on the issue.
# shellcheck disable=SC2016 # the $ names are jq variables
joins='
  def followups: split("\n") | reduce .[] as $l ({in: false, out: []};
    if ($l | test("^## ")) then .in = ($l | test("^## Follow-ups\\s*$"))
    elif .in and ($l | test("^\\s*(?:[-*]\\s+)?#[0-9]+:")) then .out += [$l | capture("#(?<n>[0-9]+):").n | tonumber]
    else . end) | .out[];
  [ .[] | (.subIssues.nodes[] | select(.state == "OPEN") | .number),
          (.closedByPullRequestsReferences.nodes[] | .body // "" | followups) ]
  | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)
  | map(select(. as $x | ($S.set | index([$x]) | not) and ($S.removed | index([$x]) | not)))'

# thread_link <name> <thread-id>: the orchestrator thread's link, as T3 writes a
# thread's link once the thread has the title `orchestrate: <name>`.
thread_link() { printf '[orchestrate: %s](t3-thread://v1/%s)' "$1" "$2"; }

# ---------- board ----------
# board: a jq program on null, with the state as $S and the check's rows as
# $rows, what only the board needs as $cards, keyed by number, and T3's
# threads as $ts, keyed by id: the board page's data. An epic is no card: its sub-issues are.
# shellcheck disable=SC2016 # the $ names are jq variables
board='
  def column: if .stage == "done" then "done"
    elif any(.prs[]; .state == "OPEN") then "review"
    elif (.stage == "ticket" or .stage == "task" or .stage == "pr") then "build"
    else "shape" end;
  def you($a): {mark: "you", action: $a};
  def agent($a): {mark: "agent", action: $a};
  def held($a): {mark: "blocked", action: $a};
  # The first rule that holds names who has the ball and the one action.
  def owner($rec; $t):
    (.prs | map(select(.state == "OPEN")) | first) as $pr
    | if .stage == "done" then {mark: "done", action: "closed"}
      elif .blocked_by != [] then held("blocked by " + (.blocked_by | map("#\(.)") | join(" ")))
      elif $rec.status == "failed" then you("Launch failed: say restart #\(.number)")
      elif $rec.status == "pending" then agent("starting /\($rec.command // .skill)\(if ($rec.mode // "") != "" then " --\($rec.mode)" else "" end)")
      elif $t.status == "waiting" then you("Answer the thread")
      elif $t.status == "failed" then you("Thread failed: open it, or say restart #\(.number)")
      elif $t.status == "interrupted" then you("Thread interrupted: open it, or say restart #\(.number)")
      elif .wait then held("waits: \(.wait)")
      elif $pr and $t.status != "running" then you("Merge PR #\($pr.number)")
      elif $t.status == "completed" and $rec.stage == .stage then you("No change: say restart #\(.number)")
      elif $t.status == "running" then agent("/\($rec.command // .skill)\(if ($rec.mode // "") != "" then " --\($rec.mode)" else "" end)") + {since: $t.createdAt}
      elif .stage == "task" or (.stage == "unlabeled" and .answer == "task") then you("Do the task, then close it")
      elif .stage == "unlabeled" and .answer == null and .proposal == null then agent("proposing a route")
      elif .stage == "unlabeled" and .answer == null then you("Answer the proposal" + ({grill: ": /grill", triage: ": /triage",
          ship: ": /ship", "ready-pr": ": /ready-pr", task: ": yours", close: ": close it"}[.proposal] // ""))
      elif .stage == "unlabeled" and .answer == "close" then you("Close it")
      elif .stage == "unlabeled" and .answer == "skip" then held("skipped")
      elif $S.status == "paused" then held("paused: starts on resume")
      else held("starts at the next check") end;
  def rank($xs): . as $x | $xs | index([$x]);
  {repo: $S.repo, name: $S.name, checked_at: $S.timer.checked_at,
   issues: [$rows | to_entries[] | .key as $i | .value | select(.stage != "epic")
     | .number as $n
     | ([$S.threads[] | select(.number == $n)] | last) as $rec
     | (if $rec.thread then $ts[$rec.thread] // {} else {} end) as $t
     | {number, title, url: "https://github.com/\($S.repo)/issues/\(.number)", column: column,
        chip: $cards[$n | tostring].chip, since: null}
       + owner($rec; $t)
       + {thread: (if $rec.thread then {id: $rec.thread, url: "t3code://threads/\($S.env)/\($rec.thread)", status: $t.status} else null end),
          pr: (.prs | map(select(.state == "OPEN")) | first | if . then {number, url} else null end),
          blocked_by, order: $i, stage, skill, model: $rec.model, effort: $rec.effort,
          journey: ([{at: $S.started_at, step: "joined"}]
            + [$S.threads[] | select(.number == $n)
               | {at, stage, command, status: ((if .thread then $ts[.thread].status else null end) // .status),
                  thread_url: (if .thread then "t3code://threads/\($S.env)/\(.thread)" else null end)}]),
          removed: ($S.removed | index([$n]) != null), made: ($S.made // [] | index([$n]) != null),
          ship_mode: (if .stage == "ticket" then ($S | ship_mode($n | tostring)) else "" end)}]
   | sort_by((.column | rank(["shape", "build", "review", "done"])), (.mark | rank(["you", "agent", "blocked", "done"])), .order)
   | map(del(.order))}'

# write_board <rows> <cards> <threads>: board.json in the run folder, under a temp name, then
# renamed into place, as save writes the state. Only a good check calls it,
# so a failed one leaves the last good board.
write_board() {
  local tmp
  tmp="$(mktemp "$run/.board.XXXXXX")"
  jq -n --argjson S "$S" --argjson rows "$1" --argjson cards "$2" --argjson ts "$3" "$ship_mode_jq$board" > "$tmp"
  mv "$tmp" "$run/board.json"
}

# ---------- start ----------
cmd_start() {
  local name="" thread="" env="" nums=() a
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --thread) thread="${2:-}"; shift 2 ;;
      --env) env="${2:-}"; shift 2 ;;
      *) [[ "$1" =~ ^#?([0-9]+)$ ]] || die "unexpected argument: $1"; nums+=("${BASH_REMATCH[1]}"); shift ;;
    esac
  done
  [ -n "$name" ] && [ -n "$thread" ] && [ -n "$env" ] && [ "${#nums[@]}" -gt 0 ] \
    || die "usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>..."
  in_t3
  local d st found path got
  for d in "$runs"/*/; do
    [ -f "$d/state.json" ] || continue
    st="$(jq -r .status "$d/state.json")"
    case "$st" in running|paused) die "a live run in $slug: $(jq -r .link "$d/state.json")" ;; esac
  done
  got="$(read_issues "${nums[@]}")" || die "gh could not read the set: $(tail -1 "$errf")"
  [ "$(jq '[.[] | select(.state == "OPEN" or any(.subIssues.nodes[]; .state == "OPEN"))] | length' <<<"$got")" -gt 0 ] \
    || die "$name has no open issue"
  found="$(bash "$core/checkout.sh" main "$slug")" || exit 1
  path="${found#* MAIN=}"
  run="$runs/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$runs"; mkdir "$run" || die "a run of $slug started this second; try again"
  S="$(jq -n --arg repo "$slug" --arg name "$name" --arg env "$env" --arg thread "$thread" --arg link "$(thread_link "$name" "$thread")" --arg path "$path" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson set "$(printf '%s\n' "${nums[@]}" | jq -s 'map(tonumber) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)')" \
    '{repo: $repo, name: $name, env: $env, thread: $thread, link: $link, path: $path, started_at: $at, status: "running",
      set: $set, removed: [], made: [], ship: {}, use: {}, proposals: {},
      threads: [], timer: {every: 5, fails: 0}}')"
  save
  copy_page
  jq -cn --arg run "$run" --argjson set "$(jq -c .set <<<"$S")" '{run: $run, set: $set}'
}

# ---------- check ----------
# fail_check <line>: a check that read too little to start anything. Only the
# failure count of the state as it was is written; after 3 in a row the user
# must act.
fail_check() {
  local fails
  S="$(jq -c --arg why "$1" '.timer.fails += 1 | .timer.why = $why' <<<"$S0")"; save
  fails="$(jq .timer.fails <<<"$S")"
  if [ "$fails" -ge 3 ]; then die "check failed $fails times in a row: $1. You must act, then say check now."; fi
  die "check failed: $1"
}

# observe: read the run as it is now, from the state, GitHub, and T3, for
# check and for a watcher check, so the two never read a run two ways. It
# keeps the state as read in S0, adds the issues it joins to S, and leaves
# issues, joined, statuses, starts, claims, sends, sent, rows, gone_rows,
# cards, propose, and done for its caller. A read that fails calls "$on_fail" <why>.
observe() {
  S0="$S"
  # The set first, then each round of issues it brings: the open sub-issues
  # of an issue in it, and the follow-ups a PR that closes one lists.
  local got todo new t3list
  issues="{}"; joined="[]"
  todo="$(jq -c .set <<<"$S")"
  while [ "$todo" != "[]" ]; do
    # shellcheck disable=SC2046 # one word per number
    got="$(read_issues $(jq -r '.[]' <<<"$todo"))" || "$on_fail" "$(tail -1 "$errf")"
    issues="$(jq -c --argjson g "$got" '. + $g' <<<"$issues")"
    new="$(jq -c --argjson S "$S" "$joins" <<<"$got")"
    S="$(jq -c --argjson new "$new" '.set += $new | .made = (.made // []) + $new' <<<"$S")"
    joined="$(jq -c --argjson new "$new" '. + $new' <<<"$joined")"
    todo="$new"
  done
  # The removed issues too, for the board alone: they never start or join,
  # so a failed read, or one deleted since, only leaves their cards out.
  if [ "$(jq '.removed | length' <<<"$S")" -gt 0 ]; then
    # shellcheck disable=SC2046 # one word per number
    got="$(read_issues $(jq -r '.removed[]' <<<"$S"))" || got="{}"
    issues="$(jq -c --argjson g "$got" '. + ($g | with_entries(select(.value != null)))' <<<"$issues")"
  fi
  t3list="$("$t3" thread list --project "$(jq -r .path <<<"$S")" --json 2>"$errf")" || "$on_fail" "$(tail -1 "$errf")"
  statuses="$(jq -c 'map({key: .threadId, value: {status, createdAt}}) | from_entries' <<<"$t3list")"

  local n j st sk free blocked rec prop line wait rc gone row conf owners
  starts="[]"; rows="[]"; claims="[]"; cards="{}"; gone_rows="[]"; sends="[]"; sent="[]"
  # owners: each PR's owner, the first issue in set order that it closes. A
  # shared PR's conflict goes only to its owner's thread, so no two threads
  # rebase one branch, even when the owner's thread is busy or just starting.
  owners="$(jq -c --argjson set "$(jq -c .set <<<"$S")" \
    '. as $is | [$set[] | $is[tostring] // empty | .number as $i
      | .closedByPullRequestsReferences.nodes[] | {key: (.number | tostring), value: $i}] | reverse | from_entries' <<<"$issues")"
  for n in $(jq -r '.set[], .removed[]' <<<"$S"); do
    gone="$(jq --argjson n "$n" '.removed | index([$n]) != null' <<<"$S")"
    j="$(jq -c --arg n "$n" '.[$n]' <<<"$issues")"
    [ "$gone" = false ] || [ "$j" != null ] || continue
    st="$(stage "$j" "$(jq -r .started_at <<<"$S")")"
    # The stage stays unlabeled; the user's answer only picks the skill.
    if [ "$st" = unlabeled ]; then
      sk="$(answer_skill "$(jq -r --arg n "$n" '(.proposals // {})[$n].answer // empty' <<<"$S")")"
    else
      sk="$(skill "$st")"
    fi
    blocked="$(jq -c '[.blockedBy.nodes[] | select(.state == "OPEN") | .number]' <<<"$j")"
    if [ "$blocked" = "[]" ]; then free=true; else free=false; fi
    rec="$(jq -c --argjson n "$n" '[.threads[] | select(.number == $n)] | last' <<<"$S")"
    # A run started before proposals existed has no key; it reads as none.
    prop="$(jq -c --arg n "$n" '(.proposals // {})[$n]' <<<"$S")"
    line=""; wait=""
    [ "$gone" = false ] || wait="removed from the set"
    if [ "$gone" = false ] && [ -n "$sk" ] && [ "$free" = true ] && [ "$(jq -r .status <<<"$S")" = running ] \
       && [ "$(jq --argjson n "$n" --arg s "$st" '[.threads[] | select(.number == $n and .stage == $s)] | length' <<<"$S")" -eq 0 ]; then
      # decide.sh exits 2 when gh failed, and that fails the check; any
      # other stop is this issue's alone, and it waits.
      rc=0; line="$(decide_for "$n" "$sk")" || rc=$?
      if [ "$rc" -ne 0 ]; then
        wait="$(tail -1 "$errf" | sed 's/^stop: //')"; line=""
        [ "$rc" -ne 2 ] || "$on_fail" "$wait"
      fi
    fi
    if [ -n "$line" ]; then
      starts="$(jq -c --argjson l "$line" --arg st "$st" \
        '. + [$l + {stage: $st, thread_title: "\($l.heading) \($l.title)", runtime_mode: "auto"}]' <<<"$starts")"
      claims="$(jq -c --argjson n "$n" --arg st "$st" --argjson l "$line" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [{number: $n, stage: $st, thread: null, link: null, status: "pending", why: null,
               at: $at, command: $l.command, mode: $l.mode, model: $l.model, effort: $l.effort}]' <<<"$claims")"
    fi
    # A conflict goes back to the thread that works on the issue, and only
    # once that thread finished its turn: a running thread is mid-turn, and a
    # waiting one waits on the user (ADR 0013, ADR 0015). An issue that starts
    # a thread now leaves the conflict to it. One PR per thread per check.
    if [ "$gone" = false ] && [ -z "$line" ] && [ "$(jq -r .status <<<"$S")" = running ] \
       && [ "$(jq -r '.status // ""' <<<"$rec")" = started ] \
       && [ "$(jq -r --argjson ts "$statuses" 'if .thread then $ts[.thread].status // "" else "" end' <<<"$rec")" = completed ]; then
      conf="$(jq -c --argjson S "$S" --argjson rec "$rec" --argjson owners "$owners" '
        [.closedByPullRequestsReferences.nodes[]
         | select(.state == "OPEN" and .mergeable == "CONFLICTING")
         | . as $p | select(($S.conflicts // []) | any(.pr == $p.number and .head == $p.headRefOid) | not)
         | select($owners[$p.number | tostring] == $rec.number)
         | {number: $rec.number, pr: .number, url, head: .headRefOid, thread: $rec.thread, link: $rec.link,
            message: "/ready-pr \(.url)"}][:1]' <<<"$j")"
      sends="$(jq -c --argjson c "$conf" '. + $c' <<<"$sends")"
      sent="$(jq -c --argjson c "$conf" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [$c[] | {number, pr, head, thread, at: $at}]' <<<"$sent")"
    fi
    cards="$(jq -c --arg n "$n" --arg chip "$(chip "$j")" '.[$n] = {chip: $chip}' <<<"$cards")"
    row="$(jq -cn --argjson j "$j" --arg st "$st" --arg sk "$sk" --argjson free "$free" --argjson b "$blocked" \
      --argjson rec "$rec" --argjson ts "$statuses" --arg wait "$wait" --argjson prop "$prop" \
      '{number: $j.number, title: $j.title, stage: $st, free: $free, blocked_by: $b,
             skill: (if $sk == "" then null else $sk end),
             thread: $rec.thread, thread_status: (if $rec.thread then $ts[$rec.thread].status else null end),
             claim: $rec.status, why: $rec.why,
             prs: [$j.closedByPullRequestsReferences.nodes[] | {number, url, state}],
             proposal: $prop.route, answer: $prop.answer}
           + (if $wait == "" then {} else {wait: $wait} end)')"
    if [ "$gone" = true ]; then gone_rows="$(jq -c --argjson r "$row" '. + [$r]' <<<"$gone_rows")"
    else rows="$(jq -c --argjson r "$row" '. + [$r]' <<<"$rows")"; fi
  done

  # Done: every issue closed, an epic once its sub-issues are, and no PR
  # that closes one still open. The orchestrator never closes an epic itself.
  done="$(jq --argjson rows "$rows" --argjson is "$issues" '
    $rows != [] and all($rows[];
      (.stage == "done" or (.stage == "epic" and all($is[.number | tostring].subIssues.nodes[]; .state == "CLOSED")))
      and all(.prs[]; .state != "OPEN"))' <<<"null")"
  # propose: the unlabeled issues with no proposal yet.
  propose="$(jq -c --argjson rows "$rows" '. as $S | [$rows[] | select(.stage == "unlabeled" and (($S.proposals // {})[.number | tostring] == null)) | .number]' <<<"$S")"
}

cmd_check() {
  in_t3
  newest_run
  [ "$(jq -r .status <<<"$S")" != stopped ] || die "the run in $slug is stopped; say /orchestrate resume"
  on_fail=fail_check
  observe

  # seen: the rows and status of this check, so the next one can tell the
  # timer whether anything moved. A run from before it has none: all changed.
  S="$(jq -c --argjson c "$claims" --argjson done "$done" --argjson rows "$rows" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.threads += $c | .timer.fails = 0 | .timer.alerted = false | .timer.why = null | .timer.checked_at = $at
     | if $done then .status = "done" else . end
     | .seen = {status: .status, issues: ($rows | map({key: (.number | tostring), value: .}) | from_entries)}' <<<"$S")"
  save
  write_board "$(jq -c --argjson g "$gone_rows" '. + $g' <<<"$rows")" "$cards" "$statuses"
  # A start counts as a change even on a row that did not move, as after a
  # resume: the post must link the new thread. The conflicts are the
  # watcher's to send, so the line lists none.
  jq -cn --arg run "$run" --argjson S "$S" --argjson starts "$starts" --argjson rows "$rows" \
    --argjson joined "$joined" --argjson done "$done" --argjson propose "$propose" --argjson seen "$(jq -c '.seen // {}' <<<"$S0")" '
    ($rows | map(. as $r | . + {changed: (($starts | any(.number == $r.number))
      or (($seen.issues // {})[$r.number | tostring] != $r))})) as $marked
    | {run: $run, status: $S.status, starts: $starts, issues: $marked, joined: $joined, done: $done,
       propose: $propose}
    | . + {changed: (any($marked[]; .changed) or $joined != [] or .propose != [] or $done or $seen.status != $S.status)}
    + if $done then {summary: [$rows[] | .number as $n | {number, title,
        stages: (reduce ($S.threads[] | select(.number == $n) | .stage) as $x ([]; if index([$x]) then . else . + [$x] end)),
        prs, threads: [$S.threads[] | select(.number == $n and .link != null) | .link]}],
        # The retro reads everything the run did; analysis gets the row decide.sh gives grill and triage.
        retro: {model: ($S.use.all.model // "opus"), effort: ($S.use.all.effort // "high"), path: $S.path,
          thread_title: "retro: \($S.name)", message: "/retro run \($run)", runtime_mode: "auto"}} else {} end'
}

# ---------- started ----------
# started <n> <stage> <thread-id> <link>, or <n> <stage> --failed <why>: the
# claim of that stage becomes the thread the agent launched, or a failed
# launch. A failed one is never started again; `restart` clears it.
cmd_started() {
  [ $# -eq 4 ] || die "usage: orchestrate.sh started <owner/repo> <n> <stage> <thread-id> <link> | --failed <why>"
  newest_run
  local n="$1" st="$2" upd
  [ "$(jq --argjson n "$n" --arg s "$st" '[.threads[] | select(.number == $n and .stage == $s and .status == "pending")] | length' <<<"$S")" -gt 0 ] \
    || die "#$n has no pending thread at stage $st"
  if [ "$3" = --failed ]; then
    upd="$(jq -cn --arg why "$4" '{status: "failed", why: $why}')"
  else
    upd="$(jq -cn --arg id "$3" --arg link "$4" '{thread: $id, link: $link, status: "started"}')"
  fi
  S="$(jq -c --argjson n "$n" --arg s "$st" --argjson u "$upd" '
    (.threads | map(.number == $n and .stage == $s and .status == "pending") | rindex(true)) as $i
    | .threads[$i] += $u' <<<"$S")"
  save
}

# ---------- proposed ----------
# proposed <n> <route> [--size S]: the route the agent proposed for unlabeled
# #n, and the size it read from the code, kept with any answer the user
# already gave. `unsure` is a proposal with no route. A ship needs the size;
# a task and a close take none, since neither builds code. Prints the model
# and effort the thread would get; a decide stop keeps the proposal and
# prints its reason as `why`.
cmd_proposed() {
  local pusage="usage: orchestrate.sh proposed <owner/repo> <n> grill|triage|ship|ready-pr|task|close|unsure [--size XS|S|M|L|XL]"
  [ $# -ge 2 ] && [[ "$1" =~ ^#?([0-9]+)$ ]] && [[ "$2" =~ ^(grill|triage|ship|ready-pr|task|close|unsure)$ ]] || die "$pusage"
  local n="${1#\#}" route="$2" size="" sk line why=""
  shift 2
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --size ] && [[ "$2" =~ ^([Xx][Ss]|[SsMmLl]|[Xx][Ll])$ ]] || die "$pusage"
    size="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
  fi
  case "$route" in
    ship) [ -n "$size" ] || die "a ship proposal needs --size XS|S|M|L|XL" ;;
    task|close) [ -z "$size" ] || die "a $route proposal takes no --size" ;;
  esac
  newest_run
  [ "$(jq --argjson n "$n" '.set | index([$n]) != null' <<<"$S")" = true ] || die "#$n is not in the set"
  S="$(jq -c --arg n "$n" --arg r "$route" --arg z "$size" \
    '.proposals[$n] = {route: $r, answer: ((.proposals // {})[$n].answer)} + (if $z == "" then {} else {size: $z} end)' <<<"$S")"
  save
  sk="$(answer_skill "$route")"
  line="null"
  if [ -n "$sk" ] && ! line="$(decide_for "$n" "$sk")"; then
    line="null"; why="$(tail -1 "$errf" | sed 's/^stop: //')"
  fi
  jq -cn --argjson n "$n" --arg r "$route" --arg z "$size" --argjson l "$line" --arg why "$why" \
    '{number: $n, route: $r, size: (if $z == "" then null else $z end), model: $l.model, effort: $l.effort}
     + (if $why == "" then {} else {why: $why} end)'
}

# ---------- change ----------
# change add <n>... and remove <n>...: the set. A removed issue keeps its
# thread records and never joins again by itself.
# change restart <n>: drop #n's newest thread record, so the next check
# starts a fresh thread at #n's stage.
# change ship review|ready|merge <n>|all: the ship mode a ticket's /ship
# thread starts with; with none set, the thread picks it. It reaches only
# issues whose ticket thread has not started: for `all`, each started one
# keeps the old default as its own, "" when the thread picked. An unlabeled issue answered `ship` started its
# ticket thread at stage unlabeled.
# change answer <n>|all <word>: the user's answer to a proposal. `yes` takes
# the proposed route; `all` takes only `yes` or `skip`, and fills only the
# proposals with no answer yet, so a per-issue answer given first stays.
# change use <n>|all: the model and effort a thread gets, for one issue or
# for all; one issue's value wins, field by field.
cmd_change() {
  newest_run
  local what="${1:-}" nums a
  case "$what" in
    add|remove)
      shift; [ $# -gt 0 ] || die "usage: orchestrate.sh change <owner/repo> $what <n>..."
      for a in "$@"; do [[ "$a" =~ ^#?[0-9]+$ ]] || die "unexpected argument: $a"; done
      nums="$(printf '%s\n' "$@" | tr -d '#' | jq -cs .)"
      if [ "$what" = add ]; then
        S="$(jq -c --argjson a "$nums" '.set += [$a[] as $x | select(.set | index([$x]) | not) | $x] | .removed -= $a' <<<"$S")"
      else
        S="$(jq -c --argjson a "$nums" '.set -= $a | .removed += [$a[] as $x | select(.removed | index([$x]) | not) | $x]' <<<"$S")"
      fi
      ;;
    restart)
      [[ "${2:-}" =~ ^#?([0-9]+)$ ]] || die "usage: orchestrate.sh change <owner/repo> restart <n>"
      local n="${BASH_REMATCH[1]}"
      [ "$(jq --argjson n "$n" '[.threads[] | select(.number == $n)] | length' <<<"$S")" -gt 0 ] \
        || die "#$n has no thread to restart"
      S="$(jq -c --argjson n "$n" '(.threads | map(.number == $n) | rindex(true)) as $i | .threads |= del(.[$i])' <<<"$S")"
      ;;
    ship)
      [[ "${2:-}" =~ ^(review|ready|merge)$ ]] && [[ "${3:-}" =~ ^(all|#?[0-9]+)$ ]] \
        || die "usage: orchestrate.sh change <owner/repo> ship review|ready|merge <n>|all"
      local mode="$2" who="${3#\#}"
      # shellcheck disable=SC2016 # the $ names are jq variables
      local shipped='(.stage == "ticket" or (.stage == "unlabeled" and ($S.proposals // {})[.number | tostring].answer == "ship"))'
      if [ "$who" = all ]; then
        S="$(jq -c --arg m "$mode" '
          . as $S | (.ship.default // "") as $d
          | reduce (.threads[] | select('"$shipped"') | .number | tostring) as $n (.; .ship[$n] //= $d)
          | .ship.default = $m' <<<"$S")"
      else
        [ "$(jq --argjson n "$who" '. as $S | [.threads[] | select(.number == $n and '"$shipped"')] | length' <<<"$S")" -eq 0 ] \
          || die "#$who has started; it ships with /ship$(m="$(ship_mode "$who")"; [ -z "$m" ] || printf ' --%s' "$m")"
        S="$(jq -c --arg n "$who" --arg m "$mode" '.ship[$n] = $m' <<<"$S")"
      fi
      ;;
    use)
      [[ "${2:-}" =~ ^(all|#?[0-9]+)$ ]] || die "usage: orchestrate.sh change <owner/repo> use <n>|all [--model M] [--effort E]"
      local key="${2#\#}" pick="{}"
      shift 2
      while [ $# -gt 0 ]; do
        case "$1" in
          --model) [ -n "${2:-}" ] || die "--model needs a name"; pick="$(jq -c --arg v "$2" '.model = $v' <<<"$pick")"; shift 2 ;;
          --effort)
            case "${2:-}" in low|medium|high|xhigh|max) ;; *) die "--effort must be low, medium, high, xhigh, or max, got: ${2:-nothing}" ;; esac
            pick="$(jq -c --arg v "$2" '.effort = $v' <<<"$pick")"; shift 2 ;;
          *) die "unexpected argument: $1" ;;
        esac
      done
      S="$(jq -c --arg k "$key" --argjson p "$pick" '.use[$k] = ((.use[$k] // {}) + $p)' <<<"$S")"
      ;;
    answer)
      local ausage="usage: orchestrate.sh change <owner/repo> answer <n>|all yes|skip|grill|triage|ship|ready-pr|task|close"
      [ $# -eq 3 ] && [[ "$2" =~ ^(all|#?[0-9]+)$ ]] && [[ "$3" =~ ^(yes|skip|grill|triage|ship|ready-pr|task|close)$ ]] || die "$ausage"
      local who="${2#\#}" word="$3"
      if [ "$who" = all ]; then
        case "$word" in yes|skip) ;; *) die "$ausage" ;; esac
        S="$(jq -c --arg w "$word" '.proposals = ((.proposals // {}) | map_values(
          if .answer != null then .
          elif $w == "skip" then .answer = "skip"
          elif .route != null and .route != "unsure" then .answer = .route
          else . end))' <<<"$S")"
      else
        [ "$(jq --argjson n "$who" '.set | index([$n]) != null' <<<"$S")" = true ] || die "#$who is not in the set"
        if [ "$word" = yes ]; then
          word="$(jq -r --arg n "$who" '(.proposals // {})[$n].route // "unsure"' <<<"$S")"
          [ "$word" != unsure ] || die "#$who has no proposal to say yes to; name a skill"
        fi
        S="$(jq -c --arg n "$who" --arg w "$word" '.proposals[$n] = ((.proposals // {})[$n] // {}) + {route: ((.proposals // {})[$n].route), answer: $w}' <<<"$S")"
      fi
      ;;
    *) die "usage: orchestrate.sh change <owner/repo> add|remove|restart|ship|use|answer ..." ;;
  esac
  save
}

# ---------- timer ----------
# timer --every <min> | pause | resume | stop: how often the watcher checks,
# and the run's status. Pause and stop end the watcher; the watcher reads the
# interval before each wait. Prints the status and interval as one JSON line.
cmd_timer() {
  newest_run
  case "${1:-}" in
    --every)
      [[ "${2:-}" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] || die "check every takes 1 minute or more"
      S="$(jq -c --argjson e "$2" '.timer.every = $e' <<<"$S")" ;;
    pause|resume|stop)
      case "$(jq -r .status <<<"$S")" in done) die "the run in $slug is done" ;; esac
      case "$1" in pause) st=paused; stop_watcher ;; resume) st=running ;; stop) st=stopped; stop_watcher ;; esac
      S="$(jq -c --arg s "$st" '.status = $s' <<<"$S")" ;;
    *) die "usage: orchestrate.sh timer <owner/repo> --every <min> | pause | resume | stop" ;;
  esac
  save
  jq -c '{status, every: .timer.every}' <<<"$S"
}

# ---------- resume ----------
# resume --thread <id> --env <id>: the newest run of the repo that is not done goes on
# from that thread. Prints the run's name, which the thread takes as its
# title, and the old timer's task, which the agent deletes before it starts
# a new one, so a run has one timer.
cmd_resume() {
  [ "${1:-}" = --thread ] && [ -n "${2:-}" ] && [ "${3:-}" = --env ] && [ -n "${4:-}" ] \
    || die "usage: orchestrate.sh resume <owner/repo> --thread <thread-id> --env <environment-id>"
  in_t3
  local d
  run=""
  while IFS= read -r d; do
    [ "$(jq -r .status "$d/state.json")" = done ] || { run="$d"; break; }
  done < <(find "$runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
  [ -n "$run" ] || die "no run to resume in $slug"
  lock_run
  S="$(cat "$run/state.json")"
  S="$(jq -c --arg l "$(thread_link "$(jq -r .name <<<"$S")" "$2")" --arg thread "$2" --arg env "$4" \
    '.thread = $thread | .link = $l | .env = $env | .status = "running" | .timer.fails = 0 | .timer.alerted = false' <<<"$S")"
  save
  copy_page
  jq -cn --arg run "$run" --argjson S "$S" '{run: $run, name: $S.name, old_task: ($S.timer.task // null), every: $S.timer.every}'
}

# ---------- watch ----------
# watch_fail <line>: a watcher check that read too little. It counts the
# failure as fail_check does; at 3 in a row it wakes the orchestrator thread,
# once a streak, since no one reads a watcher's stop line.
watch_fail() {
  S="$(jq -c --arg why "$1" '.timer.fails += 1 | .timer.why = $why' <<<"$S0")"
  if [ "$(jq '.timer.fails >= 3 and .timer.alerted != true' <<<"$S")" = true ] && [ "$(wake)" = true ]; then
    S="$(jq -c '.timer.alerted = true' <<<"$S")"
  fi
  save
  die "check failed: $1"
}

# wake: send the orchestrator thread `/orchestrate check`, unless T3 shows it
# busy: mid-turn, or waiting on the user, where a message would land as the
# answer to its question. Prints true when it sent. A failed send is left on
# stderr and not recorded, so the next watcher check tries again.
wake() {
  local thread st
  thread="$(jq -r '.thread // ""' <<<"$S0")"
  st="$(jq -r --arg t "$thread" '.[$t].status // ""' <<<"${statuses:-"{}"}")"
  case "$st" in
    preparing|queued|starting|running|waiting) echo false; return ;;
  esac
  if "$t3" thread send "$thread" "/orchestrate check" >/dev/null 2>"$errf"; then echo true
  else printf 'wake failed: %s\n' "$(tail -1 "$errf")" >&2; echo false; fi
}

# stop_watcher: end the run's watcher and forget it. A pid whose command is
# not a watcher is a reused pid and is left alone.
stop_watcher() {
  local pid i what=""
  pid="$(jq -r '.timer.watcher.pid // empty' <<<"$S")"
  [ -z "$pid" ] || what="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$what" == *"orchestrate.sh watch"* ]]; then
    kill "$pid" 2>/dev/null || true
    for i in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  fi
  S="$(jq -c '.timer.watcher = null' <<<"$S")"
}

# watch_loop <run-dir> <token>: the watcher. It waits the run's interval,
# read each time, then runs one watcher check, and ends when the run is not
# running or another watcher took its place. Its log keeps only the checks
# that woke, sent, or failed.
watch_loop() {
  local dir="$1" token="$2" every line rc
  while :; do
    every="$(jq -r --arg t "$token" 'if .status == "running" and .timer.watcher.token == $t then .timer.every else "" end' "$dir/state.json")"
    [ -n "$every" ] || exit 0
    sleep $((every * 60))
    rc=0; line="$(bash "$here/orchestrate.sh" watch "$slug" --once --token "$token")" || rc=$?
    [ "$rc" -ne 3 ] || exit 0
    if [ "$rc" -ne 0 ]; then printf '%s exit %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rc"
    elif jq -e '.woke or .sent != []' <<<"$line" >/dev/null; then printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$line"; fi
  done
}

# watch_start: a new watcher for a running run, in place of any old one,
# detached so it outlives this shell and the chat turn. Its token is in the
# state before it runs, so its first check finds itself the live watcher.
watch_start() {
  in_t3
  newest_run
  local st token pid
  st="$(jq -r .status <<<"$S")"
  [ "$st" = running ] || die "the run in $slug is $st; say resume"
  stop_watcher
  token="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
  S="$(jq -c --arg t "$token" '.timer.watcher = {token: $t, pid: null}' <<<"$S")"
  save
  nohup bash "$here/orchestrate.sh" watch "$slug" --loop "$run" "$token" </dev/null >>"$run/watch.log" 2>&1 &
  pid=$!
  S="$(jq -c --argjson p "$pid" '.timer.watcher.pid = $p' <<<"$S")"
  save
  jq -cn --argjson p "$pid" '{pid: $p}'
}

# watch starts the watcher. watch --once is one watcher check; a run that is
# not running, or a --token that is not the live watcher's, exits 3 with no
# output. The board gets what this check read, the issues it joined too; the
# state keeps only the time, so the agent's check still claims, joins, and
# marks what changed. It wakes the orchestrator thread when the agent must
# act: a thread to start, a proposal to make, or the run done. It sends
# `/ready-pr` to each thread whose PR has conflicts. Prints what it woke and
# sent as one JSON line.
cmd_watch() {
  local wusage="usage: orchestrate.sh watch <owner/repo> [--once [--token <t>] | --loop <run-dir> <token>]"
  case "${1:-}" in
    "") watch_start; return ;;
    --loop) [ $# -eq 3 ] || die "$wusage"; watch_loop "$2" "$3" ;;
    --once) [ $# -eq 1 ] || { [ $# -eq 3 ] && [ "$2" = --token ]; } || die "$wusage" ;;
    *) die "$wusage" ;;
  esac
  in_t3
  newest_run
  [ "$(jq -r .status <<<"$S")" = running ] || exit 3
  [ $# -eq 1 ] || [ "$(jq -r '.timer.watcher.token // ""' <<<"$S")" = "$3" ] || exit 3
  on_fail=watch_fail
  observe
  local at view reasons woke=false
  at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  view="$(jq -c --arg at "$at" '.timer.fails = 0 | .timer.alerted = false | .timer.why = null | .timer.checked_at = $at' <<<"$S")"
  # A conflict is claimed before it is sent, so a failed send is never tried again.
  S="$(jq -c --arg at "$at" --argjson sent "$sent" \
    '.conflicts = ((.conflicts // []) + $sent) | .timer.fails = 0 | .timer.alerted = false | .timer.why = null | .timer.checked_at = $at' <<<"$S0")"
  save
  S="$view"
  write_board "$(jq -c --argjson g "$gone_rows" '. + $g' <<<"$rows")" "$cards" "$statuses"
  local c
  while IFS= read -r c; do
    "$t3" thread send "$(jq -r .thread <<<"$c")" "$(jq -r .message <<<"$c")" >/dev/null 2>"$errf" \
      || printf 'ready-pr send failed: #%s PR #%s: %s\n' "$(jq -r .number <<<"$c")" "$(jq -r .pr <<<"$c")" "$(tail -1 "$errf")" >&2
  done < <(jq -c '.[]' <<<"$sends")
  reasons="$(jq -cn --argjson starts "$starts" --argjson propose "$propose" --argjson done "$done" '
    [$starts[] | "start #\(.number)"] + [$propose[] | "propose #\(.)"] + (if $done then ["done"] else [] end)')"
  [ "$reasons" = "[]" ] || woke="$(wake)"
  jq -cn --argjson w "$reasons" --argjson woke "$woke" --argjson sends "$sends" \
    '{wake: $w, woke: $woke, sent: [$sends[] | {number, pr, thread}]}'
}

case "$cmd" in
  start) cmd_start "$@" ;;
  check) cmd_check ;;
  started) cmd_started "$@" ;;
  proposed) cmd_proposed "$@" ;;
  change) cmd_change "$@" ;;
  timer) cmd_timer "$@" ;;
  resume) cmd_resume "$@" ;;
  watch) cmd_watch "$@" ;;
  *) die "$usage" ;;
esac
