#!/usr/bin/env bash
# orchestrate.sh: the orchestrator's check, and the one writer of a run's state file.
#
# Usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>...
#        orchestrate.sh check <owner/repo>
#        orchestrate.sh started <owner/repo> <n> <stage> <thread-id> <link>
#        orchestrate.sh started <owner/repo> <n> <stage> --failed <why>
#        orchestrate.sh proposed <owner/repo> <n> grill|triage|ship|ready-pr|task|close|unsure
#        orchestrate.sh change <owner/repo> add <n>... | remove <n>... | restart <n>
#                          | ship full|ready <n>|all | use <n>|all [--model M] [--effort E]
#                          | answer <n>|all yes|skip|grill|triage|ship|ready-pr|task|close
#        orchestrate.sh timer <owner/repo> --task <id> | --every <min> | pause | resume | stop
#        orchestrate.sh resume <owner/repo> --thread <thread-id> --env <environment-id>
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
# issues with no proposal yet; the agent proposes a route for each and
# records it with `proposed`.
#
# A live run is running or paused; a repo has at most one. A stopped run goes
# on with resume; a done run is over.
#
# Exit 0: one JSON line on stdout for start, check, timer, and resume;
# nothing for started, proposed, and change.
# Exit 1: something stopped us; the reason is the last line on stderr.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$here/../../../shared"
. "$core/kickoff/labels.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

usage="usage: orchestrate.sh start|check|started|proposed|change|timer|resume <owner/repo> ..."
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
  run="$d"; S="$(cat "$run/state.json")"
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
fields='number title state createdAt labels(first:50){nodes{name}} subIssues(first:100){nodes{number state}} blockedBy(first:50){nodes{number state}} closedByPullRequestsReferences(first:20,includeClosedPrs:false){nodes{number url state createdAt body}}'

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
errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT

# size_label <issue json>: the issue's size, from its first size label.
size_label() {
  local lab s
  while IFS= read -r lab; do
    s="$(size_of "$lab")"; [ -z "$s" ] || { echo "$s"; return; }
  done < <(jq -r '.labels.nodes[].name' <<<"$1")
}

# chip <issue json>: the card's chip, the kind and the size, by the labels
# in the order stage reads them. A ticket's type is its title's leading
# word, `[fix] x` or `fix(scope): x`, as issue-rules.md § Title writes it.
chip() {
  local labels size type
  labels="$(jq -r '.labels.nodes[].name | ascii_downcase' <<<"$1")"
  if grep -qx manual <<<"$labels"; then echo task
  elif grep -qx bug <<<"$labels"; then echo bug
  elif grep -qx seed <<<"$labels"; then echo seed
  elif size="$(size_label "$1")" && [ -n "$size" ]; then
    type="$(jq -r '.title | (capture("^\\[(?<t>[A-Za-z]+)\\]") // capture("^(?<t>[A-Za-z]+)(\\([^)]*\\))?!?:") // {t: "ticket"}).t | ascii_downcase' <<<"$1")"
    echo "$type · $size"
  else echo unlabeled; fi
}

# stage <issue json> <run start>: where the issue is. Closed comes first,
# since a closed seed keeps its label. A PR counts only when it was open
# before the run: a PR the run's own thread opened is that thread's work.
stage() {
  local labels
  labels="$(jq -r '.labels.nodes[].name | ascii_downcase' <<<"$1")"
  if [ "$(jq -r .state <<<"$1")" = CLOSED ]; then echo done
  elif grep -qx manual <<<"$labels"; then echo task
  elif [ "$(jq '.subIssues.nodes | length' <<<"$1")" -gt 0 ]; then echo epic
  elif [ "$(jq --arg t "$2" '[.closedByPullRequestsReferences.nodes[] | select(.state == "OPEN" and .createdAt < $t)] | length' <<<"$1")" -gt 0 ]; then echo pr
  elif grep -qx bug <<<"$labels"; then echo bug
  elif grep -qx seed <<<"$labels"; then echo seed
  elif [ -n "$(size_label "$1")" ]; then echo ticket
  else echo unlabeled; fi
}

# skill <stage> <ship mode>: the command a thread at that stage starts
# with, or nothing. A ticket ships by the mode, `ready` or `full`.
skill() {
  case "$1" in
    seed) echo grill ;;
    bug) echo triage ;;
    ticket) echo "ship-$2" ;;
    pr) echo ready-pr ;;
  esac
}

# answer_stage <answer>: the stage whose skill an answered unlabeled issue
# starts with, or nothing for an answer that starts no thread.
answer_stage() {
  case "$1" in
    grill) echo seed ;;
    triage) echo bug ;;
    ship) echo ticket ;;
    ready-pr) echo pr ;;
  esac
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
      elif $rec.status == "pending" then agent("starting /\($rec.command // .skill)")
      elif $t.status == "waiting" then you("Answer the thread")
      elif $t.status == "failed" then you("Thread failed: open it, or say restart #\(.number)")
      elif $t.status == "interrupted" then you("Thread interrupted: open it, or say restart #\(.number)")
      elif .wait then held("waits: \(.wait)")
      elif $pr and $t.status != "running" then you("Merge PR #\($pr.number)")
      elif $t.status == "completed" and $rec.stage == .stage then you("No change: say restart #\(.number)")
      elif $t.status == "running" then agent("/\($rec.command // .skill)") + {since: $t.createdAt}
      elif .stage == "task" or (.stage == "unlabeled" and .answer == "task") then you("Do the task, then close it")
      elif .stage == "unlabeled" and .answer == null and .proposal == null then agent("proposing a route")
      elif .stage == "unlabeled" and .answer == null then you("Answer the proposal" + ({grill: ": /grill", triage: ": /triage",
          ship: ": /ship-ready", "ready-pr": ": /ready-pr", task: ": yours", close: ": close it"}[.proposal] // ""))
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
          ship_full: (.stage == "ticket" and ($S.ship[$n | tostring] // $S.ship.default) == "full")}]
   | sort_by((.column | rank(["shape", "build", "review", "done"])), (.mark | rank(["you", "agent", "blocked", "done"])), .order)
   | map(del(.order))}'

# write_board <rows> <cards> <threads>: board.json in the run folder, under a temp name, then
# renamed into place, as save writes the state. Only a good check calls it,
# so a failed one leaves the last good board.
write_board() {
  local tmp
  tmp="$(mktemp "$run/.board.XXXXXX")"
  jq -n --argjson S "$S" --argjson rows "$1" --argjson cards "$2" --argjson ts "$3" "$board" > "$tmp"
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
  S="$(jq -n --arg repo "$slug" --arg name "$name" --arg env "$env" --arg link "$(thread_link "$name" "$thread")" --arg path "$path" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson set "$(printf '%s\n' "${nums[@]}" | jq -s 'map(tonumber) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)')" \
    '{repo: $repo, name: $name, env: $env, link: $link, path: $path, started_at: $at, status: "running",
      set: $set, removed: [], made: [], ship: {default: "ready"}, use: {}, proposals: {},
      threads: [], timer: {task: null, every: 5, fails: 0}}')"
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

cmd_check() {
  in_t3
  newest_run
  [ "$(jq -r .status <<<"$S")" != stopped ] || die "the run in $slug is stopped; say /orchestrate resume"
  S0="$S"
  # The set first, then each round of issues it brings: the open sub-issues
  # of an issue in it, and the follow-ups a PR that closes one lists.
  local issues="{}" got todo joined="[]" new t3list statuses
  todo="$(jq -c .set <<<"$S")"
  while [ "$todo" != "[]" ]; do
    # shellcheck disable=SC2046 # one word per number
    got="$(read_issues $(jq -r '.[]' <<<"$todo"))" || fail_check "$(tail -1 "$errf")"
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
  t3list="$("$t3" thread list --project "$(jq -r .path <<<"$S")" --json 2>"$errf")" || fail_check "$(tail -1 "$errf")"
  statuses="$(jq -c 'map({key: .threadId, value: {status, createdAt}}) | from_entries' <<<"$t3list")"

  local n j st sk free blocked rec prop line wait flags model effort starts="[]" rows="[]" claims="[]" cards="{}" gone row gone_rows="[]"
  for n in $(jq -r '.set[], .removed[]' <<<"$S"); do
    gone="$(jq --argjson n "$n" '.removed | index([$n]) != null' <<<"$S")"
    j="$(jq -c --arg n "$n" '.[$n]' <<<"$issues")"
    [ "$gone" = false ] || [ "$j" != null ] || continue
    st="$(stage "$j" "$(jq -r .started_at <<<"$S")")"
    sk="$(jq -r --arg n "$n" '.ship[$n] // .ship.default' <<<"$S")"
    # The stage stays unlabeled; the user's answer only picks the skill.
    if [ "$st" = unlabeled ]; then
      sk="$(skill "$(answer_stage "$(jq -r --arg n "$n" '(.proposals // {})[$n].answer // empty' <<<"$S")")" "$sk")"
    else
      sk="$(skill "$st" "$sk")"
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
      flags=()
      model="$(jq -r --arg n "$n" '.use[$n].model // .use.all.model // empty' <<<"$S")"
      effort="$(jq -r --arg n "$n" '.use[$n].effort // .use.all.effort // empty' <<<"$S")"
      [ -z "$model" ] || flags+=(--model "$model")
      [ -z "$effort" ] || flags+=(--effort "$effort")
      # A gh failure in decide.sh fails the check; any other stop is this
      # issue's alone, and it waits.
      if ! line="$(bash "$core/kickoff/decide.sh" --command "$sk" ${flags[@]+"${flags[@]}"} "https://github.com/$slug/issues/$n" 2>"$errf")"; then
        wait="$(tail -1 "$errf" | sed 's/^stop: //')"
        case "$wait" in "gh could not"*) fail_check "$wait" ;; esac
      fi
    fi
    if [ -n "$line" ]; then
      starts="$(jq -c --argjson l "$line" --arg st "$st" \
        '. + [$l + {stage: $st, message: "/\($l.command) \($l.args)", thread_title: "\($l.label) \($l.title)", runtime_mode: "auto"}]' <<<"$starts")"
      claims="$(jq -c --argjson n "$n" --arg st "$st" --argjson l "$line" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [{number: $n, stage: $st, thread: null, link: null, status: "pending", why: null,
               at: $at, command: $l.command, model: $l.model, effort: $l.effort}]' <<<"$claims")"
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
  local done
  done="$(jq --argjson rows "$rows" --argjson is "$issues" '
    $rows != [] and all($rows[];
      (.stage == "done" or (.stage == "epic" and all($is[.number | tostring].subIssues.nodes[]; .state == "CLOSED")))
      and all(.prs[]; .state != "OPEN"))' <<<"null")"

  S="$(jq -c --argjson c "$claims" --argjson done "$done" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.threads += $c | .timer.fails = 0 | .timer.why = null | .timer.checked_at = $at
     | if $done then .status = "done" else . end' <<<"$S")"
  save
  write_board "$(jq -c --argjson g "$gone_rows" '. + $g' <<<"$rows")" "$cards" "$statuses"
  jq -cn --arg run "$run" --argjson S "$S" --argjson starts "$starts" --argjson rows "$rows" \
    --argjson joined "$joined" --argjson done "$done" '
    {run: $run, status: $S.status, starts: $starts, issues: $rows, joined: $joined, done: $done,
     propose: [$rows[] | select(.stage == "unlabeled" and (($S.proposals // {})[.number | tostring] == null)) | .number]}
    + if $done then {summary: [$rows[] | .number as $n | {number, title,
        stages: (reduce ($S.threads[] | select(.number == $n) | .stage) as $x ([]; if index([$x]) then . else . + [$x] end)),
        prs, threads: [$S.threads[] | select(.number == $n and .link != null) | .link]}]} else {} end'
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
# proposed <n> <route>: the route the agent proposed for unlabeled #n, kept
# with any answer the user already gave. `unsure` is a proposal with no route.
cmd_proposed() {
  [ $# -eq 2 ] && [[ "$1" =~ ^#?([0-9]+)$ ]] && [[ "$2" =~ ^(grill|triage|ship|ready-pr|task|close|unsure)$ ]] \
    || die "usage: orchestrate.sh proposed <owner/repo> <n> grill|triage|ship|ready-pr|task|close|unsure"
  newest_run
  local n="${1#\#}"
  [ "$(jq --argjson n "$n" '.set | index([$n]) != null' <<<"$S")" = true ] || die "#$n is not in the set"
  S="$(jq -c --arg n "$n" --arg r "$2" '.proposals[$n] = {route: $r, answer: ((.proposals // {})[$n].answer)}' <<<"$S")"
  save
}

# ---------- change ----------
# change add <n>... and remove <n>...: the set. A removed issue keeps its
# thread records and never joins again by itself.
# change restart <n>: drop #n's newest thread record, so the next check
# starts a fresh thread at #n's stage.
# change ship full|ready <n>|all: how a ticket ships. It reaches only issues
# whose ticket thread has not started: for `all`, each started one keeps the
# old default as its own. An unlabeled issue answered `ship` started its
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
      [[ "${2:-}" =~ ^(full|ready)$ ]] && [[ "${3:-}" =~ ^(all|#?[0-9]+)$ ]] \
        || die "usage: orchestrate.sh change <owner/repo> ship full|ready <n>|all"
      local mode="$2" who="${3#\#}"
      # shellcheck disable=SC2016 # the $ names are jq variables
      local shipped='(.stage == "ticket" or (.stage == "unlabeled" and ($S.proposals // {})[.number | tostring].answer == "ship"))'
      if [ "$who" = all ]; then
        S="$(jq -c --arg m "$mode" '
          . as $S | .ship.default as $d
          | reduce (.threads[] | select('"$shipped"') | .number | tostring) as $n (.; .ship[$n] //= $d)
          | .ship.default = $m' <<<"$S")"
      else
        [ "$(jq --argjson n "$who" '. as $S | [.threads[] | select(.number == $n and '"$shipped"')] | length' <<<"$S")" -eq 0 ] \
          || die "#$who has started; its mode stays ship-$(jq -r --arg n "$who" '.ship[$n] // .ship.default' <<<"$S")"
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
        S="$(jq -c --arg n "$who" --arg w "$word" '.proposals[$n] = {route: ((.proposals // {})[$n].route), answer: $w}' <<<"$S")"
      fi
      ;;
    *) die "usage: orchestrate.sh change <owner/repo> add|remove|restart|ship|use|answer ..." ;;
  esac
  save
}

# ---------- timer ----------
# timer --task <id> | --every <min> | pause | resume | stop: the T3 scheduled
# task that runs the checks, and the run's status. Prints the timer and
# status as one JSON line.
cmd_timer() {
  newest_run
  case "${1:-}" in
    --task) [ -n "${2:-}" ] || die "--task needs an id"; S="$(jq -c --arg t "$2" '.timer.task = $t' <<<"$S")" ;;
    --every)
      [[ "${2:-}" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] || die "check every takes 1 minute or more"
      S="$(jq -c --argjson e "$2" '.timer.every = $e' <<<"$S")" ;;
    pause|resume|stop)
      case "$(jq -r .status <<<"$S")" in done) die "the run in $slug is done" ;; esac
      case "$1" in pause) st=paused ;; resume) st=running ;; stop) st=stopped ;; esac
      S="$(jq -c --arg s "$st" '.status = $s' <<<"$S")" ;;
    *) die "usage: orchestrate.sh timer <owner/repo> --task <id> | --every <min> | pause | resume | stop" ;;
  esac
  save
  jq -c '{status, task: .timer.task, every: .timer.every}' <<<"$S"
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
  S="$(cat "$run/state.json")"
  S="$(jq -c --arg l "$(thread_link "$(jq -r .name <<<"$S")" "$2")" --arg env "$4" \
    '.link = $l | .env = $env | .status = "running" | .timer.fails = 0' <<<"$S")"
  save
  copy_page
  jq -cn --arg run "$run" --argjson S "$S" '{run: $run, name: $S.name, old_task: $S.timer.task, every: $S.timer.every}'
}

case "$cmd" in
  start) cmd_start "$@" ;;
  check) cmd_check ;;
  started) cmd_started "$@" ;;
  proposed) cmd_proposed "$@" ;;
  change) cmd_change "$@" ;;
  timer) cmd_timer "$@" ;;
  resume) cmd_resume "$@" ;;
  *) die "$usage" ;;
esac
