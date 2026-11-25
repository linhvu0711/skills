#!/usr/bin/env bash
# orchestrate.sh: the orchestrator's check, and the one writer of a run's state file.
#
# Usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>...
#        orchestrate.sh check <owner/repo>
#        orchestrate.sh started <owner/repo> <n> <stage> <thread-id> <link>
#        orchestrate.sh started <owner/repo> <n> <stage> --failed <why>
#        orchestrate.sh settled <owner/repo> <thread-id> <run-id> [--kept <why>]
#        orchestrate.sh proposed <owner/repo> <n> grill|triage|ship|ready-pr|task|close|unsure [--size S]
#        orchestrate.sh change <owner/repo> add <n>... | remove <n>... | restart <n>
#                          | ship review|ready|merge <n>|all | use <n>|all [--model M] [--effort E]
#                          | answer <n>|all yes|skip|grill|triage|ship|ready-pr|task|close
#        orchestrate.sh timer <owner/repo> --every <min> | pause | resume | stop
#        orchestrate.sh resume <owner/repo> --thread <thread-id> --env <environment-id>
#        orchestrate.sh sync <owner/repo>
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
# And it lists each /grill or /triage thread that finished or failed, is not
# settled, and whose issue moved to a new stage; the agent settles or keeps it
# and records that with `settled`.
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
# resume; one line of text for sync; nothing for started and change.
# Exit 1: something stopped us; the reason is the last line on stderr.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$here/../../../shared"
. "$core/kickoff/labels.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

usage="usage: orchestrate.sh start|check|started|settled|proposed|change|timer|resume|sync|watch <owner/repo> ..."
[ $# -ge 2 ] || die "$usage"
cmd="$1"; slug="$2"; shift 2
[[ "$slug" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]] || die "the repo must be owner/repo, got: $slug"
owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
home="${ORCHESTRATE_HOME:-$HOME/.agents/orchestrate}"
runs="$home/$owner-$repo"

# in_t3: t3, the chat's t3 command, from the shared T3 lookup, which stops
# outside T3.
in_t3() { t3="$(bash "$core/t3-cli.sh")" || exit 1; }

# ---------- refs ----------
# A ref names one issue in any repo: owner/repo#n. The state keys every issue
# by its ref, since a run can hold issues of several repos.
#
# to_refs($repo): a state from before refs, with $repo's bare numbers made
# refs. It changes only numbers and keys of digits, so a state that holds
# refs already passes through unchanged.
# shellcheck disable=SC2016 # the $ names are jq variables
to_refs_jq='def to_refs($repo):
  def r: if type == "number" then "\($repo)#\(.)" else . end;
  def rk: with_entries(if (.key | test("^[0-9]+$")) then .key = "\($repo)#\(.key)" else . end);
  def rec: if (.number != null and .ref == null) then (.ref = "\($repo)#\(.number)" | del(.number)) else . end;
  (if .set then .set |= map(r) else . end)
  | (if .removed then .removed |= map(r) else . end)
  | (if .made then .made |= map(r) else . end)
  | (if .task_turn then .task_turn |= map(r) else . end)
  | (if .threads then .threads |= map(rec) else . end)
  | (if .conflicts then .conflicts |= map(rec) else . end)
  | (if .proposals then .proposals |= rk else . end)
  | (if .ship then .ship |= rk else . end)
  | (if .use then .use |= rk else . end)
  | (if .seen.issues then .seen.issues |= rk else . end);'

# ref_label($home): how a person reads a ref: #n in the home repo, else repo#n.
# shellcheck disable=SC2016 # the $ names are jq variables
label_jq='def ref_label($home): split("#") as [$r, $n] | if $r == $home then "#\($n)" else "\($r | split("/")[1])#\($n)" end;'

# label_of <ref>: the ref's label in this run.
label_of() { jq -rn --arg r "$1" --arg h "$slug" "$label_jq"'$r | ref_label($h)'; }

# issue_url <ref>: the issue's page on GitHub.
issue_url() { printf 'https://github.com/%s/issues/%s' "${1%#*}" "${1##*#}"; }

# to_ref <word>: the ref an issue word names: n or #n in this repo, or
# owner/repo#n.
to_ref() {
  if [[ "$1" =~ ^#?([0-9]+)$ ]]; then printf '%s#%s' "$slug" "${BASH_REMATCH[1]}"
  elif [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]]; then printf '%s' "$1"
  else die "not an issue: $1; say #n or owner/repo#n"; fi
}

# ---------- state ----------
# The run-id is the UTC start time, so the newest run sorts last.
newest_run() {
  local d
  d="$(find "$runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)"
  [ -n "$d" ] || die "no run in $slug; say /orchestrate <set>"
  run="$d"; lock_run; S="$(jq -c "$to_refs_jq"'to_refs(.repo)' "$run/state.json")"
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

# put <file> <command>...: the command's output as <file>, written under a
# temp name next to it, then renamed into place, so a crash never leaves half
# a file.
put() {
  local file="$1" tmp
  shift
  tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
  "$@" > "$tmp"
  mv "$tmp" "$file"
}

# save [<board state> <obs>]: the whole state, then the board: whole with the
# Run read's value, else only its run part.
save() {
  put "$run/state.json" jq . <<<"$S"
  write_board "${1:-$S}" "${2:-}"
}

# copy_page: the board page into the run folder, by put, so a resume
# brings a newer page to an old run. The page names its run: serve.sh reuses
# a server that gives back the same bytes, so two runs' pages, of any repo, must differ.
copy_page() {
  put "$run/board.html" sed "s#<meta name=\"orchestrate-run\" content=\"\">#<meta name=\"orchestrate-run\" content=\"$slug/$(basename "$run")\">#" \
    "$here/../assets/board.html"
}

# ---------- GitHub ----------
fields='number title state createdAt labels(first:50){nodes{name}} subIssues(first:100){nodes{number state}} blockedBy(first:50){nodes{number state}} closedByPullRequestsReferences(first:20,includeClosedPrs:false){nodes{number url state createdAt body mergeable headRefOid}}'

# read_issues <ref>...: one GraphQL call for all of them, printed as one
# object keyed by ref. A failed call leaves gh's stderr in errf.
read_issues() {
  local q="" r n out
  for r in "$@"; do n="${r##*#}"; q="$q i$n: issue(number: $n) { ...F }"; done
  # shellcheck disable=SC2016 # the $ names are GraphQL variables
  if ! out="$(gh api graphql -f query='query($o: String!, $r: String!) { repository(owner: $o, name: $r) {'"$q"' } } fragment F on Issue { '"$fields"' }' \
      -F o="$owner" -F r="$repo" 2>"$errf")"; then
    return 1
  fi
  jq -c --args '.data.repository as $d | [$ARGS.positional[] | {key: ., value: $d["i" + split("#")[1]]}] | from_entries' "$@" <<<"$out"
}
# obsf holds the Run read's own stop line: inside it, read_issues and
# decide_for write gh's stderr to errf.
errf="$(mktemp)"; obsf="$(mktemp)"; locked=""; trap 'rm -f "$errf" "$obsf"; [ -z "$locked" ] || rm -rf "$locked"' EXIT

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
# closed seed keeps its label. A task with the `waiting` label waits on
# someone outside: it starts nothing and holds no task turn. A PR counts
# only when it was open before the run: a PR the run's own thread opened is
# that thread's work.
stage() {
  local kind
  kind="$(label_kind "$1")"
  if [ "$(jq -r .state <<<"$1")" = CLOSED ]; then echo done
  elif [ "$kind" = task ] && jq -e '[.labels.nodes[].name | ascii_downcase] | index("waiting")' <<<"$1" >/dev/null; then echo waiting
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
# nothing. A ticket starts /ship; ship_mode says how far it goes. A task
# starts /complete-task, whose message from decide.sh waits for the user's go.
skill() {
  case "$1" in
    seed) echo grill ;;
    bug) echo triage ;;
    ticket) echo ship ;;
    pr) echo ready-pr ;;
    task) echo complete-task ;;
  esac
}

# The ship mode the user set for issue $n, or "" when the /ship thread picks it.
# shellcheck disable=SC2016 # the $ names are jq variables
ship_mode_jq='def ship_mode($n): .ship[$n] // .ship.default // "";'

# Failed Checks in a row before the user must act (ADR 0018).
fail_limit=3

# A check that read the run ends the failure streak and keeps its time.
# shellcheck disable=SC2016 # the $ names are jq variables
good_check_jq='def good_check($at): .timer.fails = 0 | .timer.alerted = false | .timer.why = null | .timer.checked_at = $at;'
ship_mode() { jq -r --arg n "$1" "$ship_mode_jq"' ship_mode($n)' <<<"$S"; }

# answer_skill <word>: the skill an answer or a proposed route names, or
# nothing for one that starts no thread.
answer_skill() {
  case "$1" in
    grill|triage|ship|ready-pr) echo "$1" ;;
  esac
}

# routes: the words a proposal or an answer names a route by.
routes='grill|triage|ship|ready-pr|task|close'

# decide_for <ref> <skill>: decide.sh's line for the issue's thread, with the
# ship mode the user set for a /ship thread and
# run's model and effort picks, so a proposal and its launch read the same
# row. The proposal's size goes every time: decide.sh ignores it for a ticket
# with a size label, so the label picks the row. Its stop line is left in errf.
decide_for() {
  local flags=() model effort size="" mode
  model="$(jq -r --arg r "$1" '.use[$r].model // .use.all.model // empty' <<<"$S")"
  effort="$(jq -r --arg r "$1" '.use[$r].effort // .use.all.effort // empty' <<<"$S")"
  size="$(jq -r --arg r "$1" '(.proposals // {})[$r].size // empty' <<<"$S")"
  [ -z "$model" ] || flags+=(--model "$model")
  [ -z "$effort" ] || flags+=(--effort "$effort")
  [ -z "$size" ] || flags+=(--size "${1##*#}=$size")
  if [ "$2" = ship ]; then
    mode="$(ship_mode "$1")"
    [ -z "$mode" ] || flags+=(--mode "$mode")
  fi
  bash "$core/kickoff/decide.sh" --command "$2" ${flags[@]+"${flags[@]}"} "$(issue_url "$1")" 2>"$errf"
}

# joins: a jq program on the issues just read, with the state as $S: the
# refs they bring that are neither in the set nor removed. A follow-up is
# a `#<n>:` line under `## Follow-ups` in the PR body, as pr-shape.md writes
# it; /capture puts no other link on the issue.
# shellcheck disable=SC2016 # the $ names are jq variables
joins='
  def followups: split("\n") | reduce .[] as $l ({in: false, out: []};
    if ($l | test("^## ")) then .in = ($l | test("^## Follow-ups\\s*$"))
    elif .in and ($l | test("^\\s*(?:[-*]\\s+)?#[0-9]+:")) then .out += [$l | capture("#(?<n>[0-9]+):").n]
    else . end) | .out[];
  [ .[] | (.subIssues.nodes[] | select(.state == "OPEN") | "\($S.repo)#\(.number)"),
          (.closedByPullRequestsReferences.nodes[] | .body // "" | followups | "\($S.repo)#\(.)") ]
  | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)
  | map(select(. as $x | ($S.set | index([$x]) | not) and ($S.removed | index([$x]) | not)))'

# thread_link <name> <thread-id>: the orchestrator thread's link, as T3 writes a
# thread's link once the thread has the title `🧭 <name>`.
thread_link() { printf '[🧭 %s](t3-thread://v1/%s)' "$1" "$2"; }

# ---------- task turn ----------
# The task turn: one task issue with a thread per Mac, since two tasks at
# once can fight over the browser and the user. This run holds it for a
# task whose task thread is pending or started; when it holds none, a
# running run of any repo may. A paused or stopped run has no watcher to
# free its turn, so only a running one counts. This part alone writes
# .task_turn and reads it from another run.
# shellcheck disable=SC2016 # the $ names are jq variables
turn_jq='def take_turn($holders): .task_turn = $holders; def free_turn($r): .task_turn = ((.task_turn // []) - [$r]);'

# turn_holders <stages>: the task issues of this run that hold the turn.
turn_holders() {
  jq -c --argjson st "$1" '. as $S | [.set[] | select($st[.] == "task") | . as $i
    | ([$S.threads[] | select(.ref == $i)] | last) as $r
    | select($r != null and $r.stage == "task" and ($r.status == "pending" or $r.status == "started"))]' <<<"$S"
}

# other_turn: the ref of the first other run's task that holds the turn, or
# nothing. Another run's file that does not parse holds no turn, so it never
# fails this check. Nor does a run whose watcher is gone, as after a restart:
# no check of its own would ever free its turn.
other_turn() {
  local f turn pid
  while IFS= read -r -d '' f; do
    read -r turn pid < <(jq -r "$to_refs_jq"'to_refs(.repo) | select(.status == "running" and ((.task_turn // []) != []))
      | "\(.task_turn[0]) \(.timer.watcher.pid // "")"' "$f" 2>/dev/null) || turn=""
    watcher_alive "${pid:-}" || turn=""
    [ -z "$turn" ] || { echo "$turn"; return; }
  done < <(find "$home" -mindepth 3 -maxdepth 3 -name state.json ! -path "$run/state.json" -print0 2>/dev/null | sort -z)
}

# ---------- board ----------
# run_part($limit): what the board shows of the run itself, from a state.
# shellcheck disable=SC2016 # the $ names are jq variables
board_run_jq='def run_part($limit): {repo, name, status, timer: {fails: (.timer.fails // 0), why: .timer.why,
  checked_at: .timer.checked_at, every: .timer.every, must_act: ((.timer.fails // 0) >= $limit)}};'

# board: a jq program on null, with the state as $S and the check's rows as
# $rows, what only the board needs as $cards, keyed by ref, and T3's
# threads as $ts, keyed by id: the board page's data. An epic is no card: its sub-issues are.
# shellcheck disable=SC2016 # the $ names are jq variables
board='
  def column: if .stage == "done" then "done"
    elif any(.prs[]; .state == "OPEN") then "review"
    elif (.stage == "ticket" or .stage == "task" or .stage == "waiting" or .stage == "pr") then "build"
    else "shape" end;
  def you($a): {mark: "you", action: $a};
  def agent($a): {mark: "agent", action: $a};
  def held($a): {mark: "blocked", action: $a};
  # quiet: the thread had no update for 10 minutes before this check, or T3
  # gave no time. A /ship thread ends its turn each time it waits for its
  # helpers, so a short pause is not a stop; 10 minutes is two watcher checks
  # at the 5 minute default (#279). T3 writes milliseconds, which
  # fromdateiso8601 refuses.
  def quiet($t): $t.updatedAt == null
    or (($S.timer.checked_at | fromdateiso8601) - ($t.updatedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= 600);
  # The first rule that holds names who has the ball and the one action.
  def owner($rec; $t):
    (.prs | map(select(.state == "OPEN")) | first) as $pr
    | if .stage == "done" then {mark: "done", action: "closed"}
      elif .blocked_by != [] then held("blocked by " + (.blocked_by | map(ref_label($S.repo)) | join(" ")))
      elif $rec.status == "failed" then you("Launch failed: say restart \(.label)")
      elif $rec.status == "pending" then agent("starting /\($rec.command // .skill)\(if ($rec.mode // "") != "" then " --\($rec.mode)" else "" end)")
      elif $t.status == "waiting" then you("Answer the thread")
      elif $t.status == "failed" then you("Thread failed: open it, or say restart \(.label)")
      elif $t.status == "interrupted" then you("Thread interrupted: open it, or say restart \(.label)")
      elif .wait then held("waits: \(.wait)")
      elif $pr and $t.status != "running" then you("Merge PR #\($pr.number)")
      elif .stage == "waiting" then you("Waits outside: say resume \(.label)")
      elif .stage == "task" and $rec.status == "started" and $t.status == "completed" then you("Open the thread: it waits for you")
      elif $t.status == "completed" and $rec.stage == .stage and quiet($t) then you("No change: say restart \(.label)")
      elif $t.status == "running" or ($t.status == "completed" and $rec.stage == .stage) then agent("/\($rec.command // .skill)\(if ($rec.mode // "") != "" then " --\($rec.mode)" else "" end)") + {since: $t.createdAt}
      elif .stage == "unlabeled" and .answer == "task" then you("Do the task, then close it")
      elif .stage == "unlabeled" and .answer == null and .proposal == null then agent("proposing a route")
      elif .stage == "unlabeled" and .answer == null then you("Answer the proposal" + ({grill: ": /grill", triage: ": /triage",
          ship: ": /ship", "ready-pr": ": /ready-pr", task: ": yours", close: ": close it"}[.proposal] // ""))
      elif .stage == "unlabeled" and .answer == "close" then you("Close it")
      elif .stage == "unlabeled" and .answer == "skip" then held("skipped")
      elif $S.status == "paused" then held("paused: starts on resume")
      else held("starts at the next check") end;
  def rank($xs): . as $x | $xs | index([$x]);
  ($S | run_part($limit)) + {checked_at: $S.timer.checked_at,
   issues: [$rows | to_entries[] | .key as $i | .value | select(.stage != "epic")
     | .ref as $r
     | ([$S.threads[] | select(.ref == $r)] | last) as $rec
     | (if $rec.thread then $ts[$rec.thread] // {} else {} end) as $t
     | {number, ref, label, title, url, column: column,
        chip: $cards[$r].chip, since: null}
       + owner($rec; $t)
       + {thread: (if $rec.thread then {id: $rec.thread, url: "t3code://threads/\($S.env)/\($rec.thread)", status: $t.status} else null end),
          pr: (.prs | map(select(.state == "OPEN")) | first | if . then {number, url} else null end),
          blocked_by: (.blocked_by | map(ref_label($S.repo))), order: $i, stage, skill, model: $rec.model, effort: $rec.effort,
          journey: ([{at: $S.started_at, step: "joined"}]
            + [$S.threads[] | select(.ref == $r)
               | {at, stage, command, status: ((if .thread then $ts[.thread].status else null end) // .status),
                  thread_url: (if .thread then "t3code://threads/\($S.env)/\(.thread)" else null end)}]),
          removed: ($S.removed | index([$r]) != null), made: ($S.made // [] | index([$r]) != null),
          ship_mode: (if .stage == "ticket" then ($S | ship_mode($r)) else "" end)}]
   | sort_by((.column | rank(["shape", "build", "review", "done"])), (.mark | rank(["you", "agent", "blocked", "done"])), .order)
   | map(del(.order))}'

# write_board <state> [obs]: board.json in the run folder, by put, the one
# writer of it. With the Run read's value, the whole board: its live and
# removed rows, its cards, and T3's threads. Without it, only the run part of
# the state, over the cards there: the run part follows every save, so the
# page never shows a status or a timer the state has left, and the cards
# change only on a good check.
write_board() {
  if [ -n "${2:-}" ]; then
    # shellcheck disable=SC2016 # the $ names are jq variables
    put "$run/board.json" jq -n --argjson S "$1" --argjson o "$2" --argjson limit "$fail_limit" \
      "$ship_mode_jq$board_run_jq$label_jq"'($o.rows + $o.gone_rows) as $rows | $o.cards as $cards | $o.statuses as $ts | '"$board"
  elif [ -f "$run/board.json" ]; then
    # shellcheck disable=SC2016 # the $ names are jq variables
    put "$run/board.json" jq --argjson S "$1" --argjson limit "$fail_limit" "$board_run_jq"'. + ($S | run_part($limit))' "$run/board.json"
  else
    # shellcheck disable=SC2016 # the $ names are jq variables
    put "$run/board.json" jq -n --argjson S "$1" --argjson limit "$fail_limit" "$board_run_jq"'$S | run_part($limit)'
  fi
}

# ---------- start ----------
cmd_start() {
  local name="" thread="" env="" refs=() a
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --thread) thread="${2:-}"; shift 2 ;;
      --env) env="${2:-}"; shift 2 ;;
      -*) die "unexpected argument: $1" ;;
      *) a="$(to_ref "$1")" || exit 1; refs+=("$a"); shift ;;
    esac
  done
  [ -n "$name" ] && [ -n "$thread" ] && [ -n "$env" ] && [ "${#refs[@]}" -gt 0 ] \
    || die "usage: orchestrate.sh start <owner/repo> --name <words> --thread <thread-id> --env <environment-id> <n>..."
  in_t3
  local d st found path got
  for d in "$runs"/*/; do
    [ -f "$d/state.json" ] || continue
    st="$(jq -r .status "$d/state.json")"
    case "$st" in running|paused) die "a live run in $slug: $(jq -r .link "$d/state.json")" ;; esac
  done
  got="$(read_issues "${refs[@]}")" || die "gh could not read the set: $(tail -1 "$errf")"
  [ "$(jq '[.[] | select(.state == "OPEN" or any(.subIssues.nodes[]; .state == "OPEN"))] | length' <<<"$got")" -gt 0 ] \
    || die "$name has no open issue"
  found="$(bash "$core/checkout.sh" main "$slug")" || exit 1
  path="${found#* MAIN=}"
  run="$runs/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$runs"; mkdir "$run" || die "a run of $slug started this second; try again"
  S="$(jq -n --arg repo "$slug" --arg name "$name" --arg env "$env" --arg thread "$thread" --arg link "$(thread_link "$name" "$thread")" --arg path "$path" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson set "$(printf '%s\n' "${refs[@]}" | jq -Rcs 'split("\n") | map(select(. != "")) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)')" \
    '{repo: $repo, name: $name, env: $env, thread: $thread, link: $link, path: $path, started_at: $at, status: "running",
      set: $set, removed: [], made: [], ship: {}, use: {}, proposals: {},
      threads: [], timer: {every: 5, fails: 0}}')"
  save
  copy_page
  jq -cn --arg run "$run" --argjson set "$(jq -c .set <<<"$S")" '{run: $run, set: $set}'
}

# ---------- run read ----------
# observe: the Run read: the run as it is now, from the state in S, GitHub,
# and T3, for check and for a watcher check, so the two never read a run two
# ways. Its callers run it in a subshell with set -e on, so nothing it sets
# reaches them. It prints one JSON value: state, S with the issues it joins;
# joined, statuses, starts, claims, sends, sent, rows, gone_rows, cards,
# propose, settles, done, holders, and task_turn. A read that fails stops it,
# with the reason as the last line on stderr.
observe() {
  # The set first, then each round of issues it brings: the open sub-issues
  # of an issue in it, and the follow-ups a PR that closes one lists.
  local got todo new t3list issues joined statuses
  issues="{}"; joined="[]"
  todo="$(jq -c .set <<<"$S")"
  while [ "$todo" != "[]" ]; do
    # shellcheck disable=SC2046 # one word per number
    got="$(read_issues $(jq -r '.[]' <<<"$todo"))" || die "$(tail -1 "$errf")"
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
  t3list="$("$t3" thread list --project "$(jq -r .path <<<"$S")" --json 2>"$errf")" || die "$(tail -1 "$errf")"
  statuses="$(jq -c 'map({key: .threadId, value: {status, createdAt, updatedAt, settled, run: .latestRunId}}) | from_entries' <<<"$t3list")"

  local r j st sk free blocked rec prop line wait rc gone row conf owners stages turn
  local starts rows claims cards gone_rows sends sent holders task_turn done propose settles
  starts="[]"; rows="[]"; claims="[]"; cards="{}"; gone_rows="[]"; sends="[]"; sent="[]"
  stages="{}"
  for r in $(jq -r '.set[], .removed[]' <<<"$S"); do
    j="$(jq -c --arg r "$r" '.[$r]' <<<"$issues")"
    [ "$j" != null ] || continue
    stages="$(jq -c --arg r "$r" --arg s "$(stage "$j" "$(jq -r .started_at <<<"$S")")" '.[$r] = $s' <<<"$stages")"
  done
  holders="$(turn_holders "$stages")"
  turn="$(jq -r 'if . == [] then empty else .[0] end' <<<"$holders")"
  [ -n "$turn" ] || turn="$(other_turn)"
  task_turn="$holders"
  # owners: each PR's owner, the first issue in set order that it closes,
  # keyed by the PR's URL, since two repos can each have a PR #9. A
  # shared PR's conflict goes only to its owner's thread, so no two threads
  # rebase one branch, even when the owner's thread is busy or just starting.
  owners="$(jq -c --argjson set "$(jq -c .set <<<"$S")" \
    '. as $is | [$set[] | . as $i | $is[$i] // empty
      | .closedByPullRequestsReferences.nodes[] | {key: .url, value: $i}] | reverse | from_entries' <<<"$issues")"
  for r in $(jq -r '.set[], .removed[]' <<<"$S"); do
    gone="$(jq --arg r "$r" '.removed | index([$r]) != null' <<<"$S")"
    j="$(jq -c --arg r "$r" '.[$r]' <<<"$issues")"
    [ "$gone" = false ] || [ "$j" != null ] || continue
    st="$(jq -r --arg r "$r" '.[$r]' <<<"$stages")"
    # The stage stays unlabeled; the user's answer only picks the skill.
    if [ "$st" = unlabeled ]; then
      sk="$(answer_skill "$(jq -r --arg r "$r" '(.proposals // {})[$r].answer // empty' <<<"$S")")"
    else
      sk="$(skill "$st")"
    fi
    blocked="$(jq -c --arg repo "$slug" '[.blockedBy.nodes[] | select(.state == "OPEN") | "\($repo)#\(.number)"]' <<<"$j")"
    if [ "$blocked" = "[]" ]; then free=true; else free=false; fi
    rec="$(jq -c --arg r "$r" '[.threads[] | select(.ref == $r)] | last' <<<"$S")"
    # A run started before proposals existed has no key; it reads as none.
    prop="$(jq -c --arg r "$r" '(.proposals // {})[$r]' <<<"$S")"
    line=""; wait=""
    [ "$gone" = false ] || wait="removed from the set"
    if [ "$gone" = false ] && [ -n "$sk" ] && [ "$free" = true ] && [ "$(jq -r .status <<<"$S")" = running ] \
       && [ "$(jq --arg r "$r" --arg s "$st" '[.threads[] | select(.ref == $r and .stage == $s)] | length' <<<"$S")" -eq 0 ]; then
      if [ "$st" = task ] && [ -n "$turn" ]; then
        wait="waits for the task turn: $turn"
      else
        # decide.sh exits 2 when gh failed, and that fails the check; any
        # other stop is this issue's alone, and it waits.
        rc=0; line="$(decide_for "$r" "$sk")" || rc=$?
        if [ "$rc" -ne 0 ]; then
          wait="$(tail -1 "$errf" | sed 's/^stop: //')"; line=""
          [ "$rc" -ne 2 ] || die "$wait"
        elif [ "$st" = task ]; then
          turn="$r"; task_turn="$(jq -c --arg r "$r" '. + [$r]' <<<"$task_turn")"
        fi
      fi
    fi
    if [ -n "$line" ]; then
      starts="$(jq -c --argjson l "$line" --arg st "$st" --arg r "$r" --arg label "$(label_of "$r")" \
        '. + [$l + {ref: $r, label: $label, stage: $st, thread_title: "\($l.heading) \($l.title)"}]' <<<"$starts")"
      claims="$(jq -c --arg r "$r" --arg st "$st" --argjson l "$line" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [{ref: $r, stage: $st, thread: null, link: null, status: "pending", why: null,
               at: $at, command: $l.command, mode: $l.mode, model: $l.model, effort: $l.effort}]' <<<"$claims")"
    fi
    # A conflict goes back to the thread that works on the issue, and only
    # once that thread finished its turn: a running thread is mid-turn, and a
    # waiting one waits on the user (ADR 0013, ADR 0015). An issue that starts
    # a thread now leaves the conflict to it. One PR per thread per check.
    if [ "$gone" = false ] && [ -z "$line" ] && [ "$(jq -r .status <<<"$S")" = running ] \
       && [ "$(jq -r '.status // ""' <<<"$rec")" = started ] \
       && [ "$(jq -r --argjson ts "$statuses" 'if .thread then $ts[.thread].status // "" else "" end' <<<"$rec")" = completed ]; then
      conf="$(jq -c --argjson S "$S" --argjson rec "$rec" --argjson owners "$owners" --arg label "$(label_of "$r")" '
        [.closedByPullRequestsReferences.nodes[]
         | select(.state == "OPEN" and .mergeable == "CONFLICTING")
         | . as $p | select(($S.conflicts // []) | any(.pr == $p.number and .head == $p.headRefOid) | not)
         | select($owners[$p.url] == $rec.ref)
         | {ref: $rec.ref, label: $label, pr: .number, url, head: .headRefOid, thread: $rec.thread, link: $rec.link,
            message: "/ready-pr \(.url)"}][:1]' <<<"$j")"
      sends="$(jq -c --argjson c "$conf" '. + $c' <<<"$sends")"
      sent="$(jq -c --argjson c "$conf" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [$c[] | {ref, pr, head, thread, at: $at}]' <<<"$sent")"
    fi
    cards="$(jq -c --arg r "$r" --arg chip "$(chip "$j")" '.[$r] = {chip: $chip}' <<<"$cards")"
    row="$(jq -cn --argjson j "$j" --arg st "$st" --arg sk "$sk" --argjson free "$free" --argjson b "$blocked" \
      --argjson rec "$rec" --argjson ts "$statuses" --arg wait "$wait" --argjson prop "$prop" \
      --arg r "$r" --arg label "$(label_of "$r")" --arg url "$(issue_url "$r")" \
      '{ref: $r, number: $j.number, repo: ($r | split("#")[0]), label: $label, url: $url,
             title: $j.title, stage: $st, free: $free, blocked_by: $b,
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
      (.stage == "done" or (.stage == "epic" and all($is[.ref].subIssues.nodes[]; .state == "CLOSED")))
      and all(.prs[]; .state != "OPEN"))' <<<"null")"
  # propose: the unlabeled issues with no proposal yet.
  propose="$(jq -c --argjson rows "$rows" '. as $S | [$rows[] | select(.stage == "unlabeled" and (($S.proposals // {})[.ref] == null)) | .ref]' <<<"$S")"
  # settles: the /grill and /triage threads whose issue moved to a new stage,
  # once they finished or failed, while T3 shows them not settled. A thread
  # the run settled stays the user's after that; one it kept waits for a new
  # turn. A removed issue has no row, so its threads are left out.
  settles="$(jq -c --argjson rows "$rows" --argjson ts "$statuses" '
    if .status != "running" then [] else
    [.threads[] | select(.status == "started" and .thread != null and (.command == "grill" or .command == "triage"))
     | . as $r | ($ts[$r.thread] // {}) as $t
     | ($rows[] | select(.ref == $r.ref)) as $row | $row.stage as $now
     | select($now != $r.stage and ($t.status == "completed" or $t.status == "failed") and ($t.settled // false) == false
         and ($r.settle.verdict // "") != "settled"
         and (($r.settle.verdict // "") != "kept" or $r.settle.run != $t.run))
     | {ref, label: $row.label, stage, command, thread, link, status: $t.status, run: $t.run, now: $now}] end' <<<"$S")"
  jq -cn --argjson state "$S" --argjson joined "$joined" --argjson statuses "$statuses" --argjson starts "$starts" \
    --argjson claims "$claims" --argjson sends "$sends" --argjson sent "$sent" --argjson rows "$rows" \
    --argjson gone_rows "$gone_rows" --argjson cards "$cards" --argjson propose "$propose" --argjson settles "$settles" \
    --argjson done "$done" --argjson holders "$holders" --argjson task_turn "$task_turn" \
    '$ARGS.named'
}

# read_run <at-limit>: the Run read into the caller's obs. A read that fails
# adds one to the failure streak and keeps why; at fail_limit in a row it runs
# <at-limit> <why>, which may change S and stop, the stop line. Then the state
# is saved and the command stops.
read_run() {
  local rc=0 why
  # A call under `||` would turn set -e off inside observe, so it runs as the
  # repo's test runner runs a case.
  set +e; obs="$(set -euo pipefail; observe 2>"$obsf")"; rc=$?; set -e
  [ "$rc" -ne 0 ] || return 0
  why="$(tail -1 "$obsf" | sed 's/^stop: //')"
  S="$(jq -c --arg why "$why" '.timer.fails += 1 | .timer.why = $why' <<<"$S")"
  stop="check failed: $why"
  # Run in this shell, not in $( ), so the step's S and stop reach save and die.
  [ "$(jq .timer.fails <<<"$S")" -lt "$fail_limit" ] || "$1" "$why"
  save
  die "$stop"
}

# check_at_limit <why>: no one wakes the agent's own check; its stop line says
# the user must act.
check_at_limit() {
  stop="check failed $(jq .timer.fails <<<"$S") times in a row: $1. You must act, then say check now."
}

# watch_at_limit <why>: no one reads a watcher's stop line, so it wakes the
# orchestrator thread, once a streak. A failed read hands back no T3 statuses.
watch_at_limit() {
  if [ "$(jq '.timer.alerted != true' <<<"$S")" = true ] && [ "$(wake '{}')" = true ]; then
    S="$(jq -c '.timer.alerted = true' <<<"$S")"
  fi
}

# ---------- check ----------
cmd_check() {
  in_t3
  newest_run
  [ "$(jq -r .status <<<"$S")" != stopped ] || die "the run in $slug is stopped; say /orchestrate resume"
  local obs seen
  read_run check_at_limit

  # seen: the rows and status of this check, so the next one can tell the
  # timer whether anything moved. A run from before it has none: all changed.
  seen="$(jq -c '.seen // {}' <<<"$S")"
  S="$(jq -cn --argjson o "$obs" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$good_check_jq$turn_jq"'$o.state | .threads += $o.claims | take_turn($o.task_turn) | good_check($at)
     | if $o.done then .status = "done" else . end
     | .seen = {status: .status, issues: ($o.rows | map({key: .ref, value: .}) | from_entries)}')"
  save "$S" "$obs"
  # A start counts as a change even on a row that did not move, as after a
  # resume: the post must link the new thread. The conflicts are the
  # watcher's to send, so the line lists none.
  jq -cn --arg run "$run" --arg am "$analysis_model" --arg ae "$analysis_effort" --argjson S "$S" --argjson o "$obs" --argjson seen "$seen" '
    $o.starts as $starts | $o.rows as $rows | $o.joined as $joined | $o.done as $done
    | $o.propose as $propose | $o.settles as $settles
    | ($rows | map(. as $r | . + {changed: (($starts | any(.ref == $r.ref))
      or (($seen.issues // {})[$r.ref] != $r))})) as $marked
    | {run: $run, status: $S.status, starts: $starts, settles: $settles, issues: $marked, joined: $joined, done: $done,
       propose: $propose}
    | . + {changed: (any($marked[]; .changed) or $joined != [] or .propose != [] or $settles != [] or $done or $seen.status != $S.status)}
    + if $done then {summary: [$rows[] | .ref as $r | {ref, label, number, title,
        stages: (reduce ($S.threads[] | select(.ref == $r) | .stage) as $x ([]; if index([$x]) then . else . + [$x] end)),
        prs, threads: [$S.threads[] | select(.ref == $r and .link != null) | .link]}],
        removed: $S.removed}
      # The retro reads everything the run did; analysis gets the row decide.sh gives grill and triage.
      # A run with issues taken out is not the whole work, so it gets no retro yet.
      + (if ($S.removed | length) == 0 then {retro: {model: ($S.use.all.model // $am),
          effort: ($S.use.all.effort // $ae), path: $S.path,
          thread_title: "retro: \($S.name)", message: "/retro run \($run)"}} else {} end)
      else {} end'
}

# ---------- started ----------
# started <issue> <stage> <thread-id> <link>, or <issue> <stage> --failed <why>: the
# claim of that stage becomes the thread the agent launched, or a failed
# launch. A failed one is never started again; `restart` clears it. A failed
# task launch frees the task turn now, so other runs need not wait a check.
cmd_started() {
  [ $# -eq 4 ] || die "usage: orchestrate.sh started <owner/repo> <issue> <stage> <thread-id> <link> | --failed <why>"
  newest_run
  local r st="$2" upd
  r="$(to_ref "$1")" || exit 1
  [ "$(jq --arg r "$r" --arg s "$st" '[.threads[] | select(.ref == $r and .stage == $s and .status == "pending")] | length' <<<"$S")" -gt 0 ] \
    || die "$(label_of "$r") has no pending thread at stage $st"
  if [ "$3" = --failed ]; then
    upd="$(jq -cn --arg why "$4" '{status: "failed", why: $why}')"
  else
    upd="$(jq -cn --arg id "$3" --arg link "$4" '{thread: $id, link: $link, status: "started"}')"
  fi
  S="$(jq -c --arg r "$r" --arg s "$st" --argjson u "$upd" "$turn_jq"'
    (.threads | map(.ref == $r and .stage == $s and .status == "pending") | rindex(true)) as $i
    | .threads[$i] += $u
    | if $u.status == "failed" then free_turn($r) else . end' <<<"$S")"
  save
}

# ---------- settled ----------
# settled <thread-id> <run-id> [--kept <why>]: what the agent did with a
# /grill or /triage thread a check listed in settles: settled it at that
# turn, or kept it open for the user, with why.
cmd_settled() {
  local susage="usage: orchestrate.sh settled <owner/repo> <thread-id> <run-id> [--kept <why>]"
  [ $# -eq 2 ] || { [ $# -eq 4 ] && [ "$3" = --kept ] && [ -n "$4" ]; } || die "$susage"
  newest_run
  local id="$1" upd
  [ "$(jq --arg t "$id" '[.threads[] | select(.thread == $t and .status == "started" and (.command == "grill" or .command == "triage"))] | length' <<<"$S")" -gt 0 ] \
    || die "$id is no grill or triage thread of this run"
  upd="$(jq -cn --arg run "$2" --arg why "${4:-}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{verdict: (if $why == "" then "settled" else "kept" end), run: $run, why: (if $why == "" then null else $why end), at: $at}')"
  S="$(jq -c --arg t "$id" --argjson u "$upd" '
    (.threads | map(.thread == $t) | rindex(true)) as $i
    | .threads[$i].settle = $u' <<<"$S")"
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
  local pusage="usage: orchestrate.sh proposed <owner/repo> <issue> $routes|unsure [--size $size_list]"
  [ $# -ge 2 ] && [[ "$2" =~ ^($routes|unsure)$ ]] || die "$pusage"
  local word="$1" r route="$2" size="" sk line why=""
  shift 2
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --size ] || die "$pusage"
    size="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
    one_of "$size_list" "$size" || die "$pusage"
  fi
  case "$route" in
    ship) [ -n "$size" ] || die "a ship proposal needs --size $size_list" ;;
    task|close) [ -z "$size" ] || die "a $route proposal takes no --size" ;;
  esac
  newest_run
  r="$(to_ref "$word")" || exit 1
  [ "$(jq --arg r "$r" '.set | index([$r]) != null' <<<"$S")" = true ] || die "$(label_of "$r") is not in the set"
  S="$(jq -c --arg i "$r" --arg r "$route" --arg z "$size" \
    '.proposals[$i] = {route: $r, answer: ((.proposals // {})[$i].answer)} + (if $z == "" then {} else {size: $z} end)' <<<"$S")"
  save
  sk="$(answer_skill "$route")"
  line="null"
  if [ -n "$sk" ] && ! line="$(decide_for "$r" "$sk")"; then
    line="null"; why="$(tail -1 "$errf" | sed 's/^stop: //')"
  fi
  jq -cn --arg i "$r" --arg label "$(label_of "$r")" --arg r "$route" --arg z "$size" --argjson l "$line" --arg why "$why" \
    '{ref: $i, label: $label, route: $r, size: (if $z == "" then null else $z end), model: $l.model, effort: $l.effort}
     + (if $why == "" then {} else {why: $why} end)'
}

# ---------- change ----------
# change add <issue>... and remove <issue>...: the set. A removed issue keeps its
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
  local what="${1:-}" refs a r
  case "$what" in
    add|remove)
      shift; [ $# -gt 0 ] || die "usage: orchestrate.sh change <owner/repo> $what <issue>..."
      refs=""
      for a in "$@"; do r="$(to_ref "$a")" || exit 1; refs="$refs$r"$'\n'; done
      refs="$(printf '%s' "$refs" | jq -Rcs 'split("\n") | map(select(. != ""))')"
      if [ "$what" = add ]; then
        S="$(jq -c --argjson a "$refs" '.set += [$a[] as $x | select(.set | index([$x]) | not) | $x] | .removed -= $a' <<<"$S")"
      else
        S="$(jq -c --argjson a "$refs" '.set -= $a | .removed += [$a[] as $x | select(.removed | index([$x]) | not) | $x]' <<<"$S")"
      fi
      ;;
    restart)
      [ -n "${2:-}" ] || die "usage: orchestrate.sh change <owner/repo> restart <issue>"
      r="$(to_ref "$2")" || exit 1
      [ "$(jq --arg r "$r" '[.threads[] | select(.ref == $r)] | length' <<<"$S")" -gt 0 ] \
        || die "$(label_of "$r") has no thread to restart"
      S="$(jq -c --arg r "$r" '(.threads | map(.ref == $r) | rindex(true)) as $i | .threads |= del(.[$i])' <<<"$S")"
      ;;
    ship)
      one_of "$ship_mode_list" "${2:-}" && [ -n "${3:-}" ] \
        || die "usage: orchestrate.sh change <owner/repo> ship $ship_mode_list <issue>|all"
      local mode="$2"
      # shellcheck disable=SC2016 # the $ names are jq variables
      local shipped='(.stage == "ticket" or (.stage == "unlabeled" and ($S.proposals // {})[.ref].answer == "ship"))'
      if [ "$3" = all ]; then
        S="$(jq -c --arg m "$mode" '
          . as $S | (.ship.default // "") as $d
          | reduce (.threads[] | select('"$shipped"') | .ref) as $r (.; .ship[$r] //= $d)
          | .ship.default = $m' <<<"$S")"
      else
        r="$(to_ref "$3")" || exit 1
        [ "$(jq --arg r "$r" '. as $S | [.threads[] | select(.ref == $r and '"$shipped"')] | length' <<<"$S")" -eq 0 ] \
          || die "$(label_of "$r") has started; it ships with /ship$(m="$(ship_mode "$r")"; [ -z "$m" ] || printf ' --%s' "$m")"
        S="$(jq -c --arg r "$r" --arg m "$mode" '.ship[$r] = $m' <<<"$S")"
      fi
      ;;
    use)
      [ -n "${2:-}" ] || die "usage: orchestrate.sh change <owner/repo> use <issue>|all [--model M] [--effort E]"
      local key="all" pick="{}"
      [ "$2" = all ] || { key="$(to_ref "$2")" || exit 1; }
      shift 2
      while [ $# -gt 0 ]; do
        case "$1" in
          --model) [ -n "${2:-}" ] || die "--model needs a name"; pick="$(jq -c --arg v "$2" '.model = $v' <<<"$pick")"; shift 2 ;;
          --effort)
            one_of "$effort_list" "${2:-}" || die "--effort must be $(spelled "$effort_list"), got: ${2:-nothing}"
            pick="$(jq -c --arg v "$2" '.effort = $v' <<<"$pick")"; shift 2 ;;
          *) die "unexpected argument: $1" ;;
        esac
      done
      S="$(jq -c --arg k "$key" --argjson p "$pick" '.use[$k] = ((.use[$k] // {}) + $p)' <<<"$S")"
      ;;
    answer)
      local ausage="usage: orchestrate.sh change <owner/repo> answer <issue>|all yes|skip|$routes"
      [ $# -eq 3 ] && [[ "$3" =~ ^(yes|skip|$routes)$ ]] || die "$ausage"
      local word="$3"
      if [ "$2" = all ]; then
        case "$word" in yes|skip) ;; *) die "$ausage" ;; esac
        S="$(jq -c --arg w "$word" '.proposals = ((.proposals // {}) | map_values(
          if .answer != null then .
          elif $w == "skip" then .answer = "skip"
          elif .route != null and .route != "unsure" then .answer = .route
          else . end))' <<<"$S")"
      else
        r="$(to_ref "$2")" || exit 1
        [ "$(jq --arg r "$r" '.set | index([$r]) != null' <<<"$S")" = true ] || die "$(label_of "$r") is not in the set"
        if [ "$word" = yes ]; then
          word="$(jq -r --arg r "$r" '(.proposals // {})[$r].route // "unsure"' <<<"$S")"
          [ "$word" != unsure ] || die "$(label_of "$r") has no proposal to say yes to; name a skill"
        fi
        S="$(jq -c --arg r "$r" --arg w "$word" '.proposals[$r] = ((.proposals // {})[$r] // {}) + {route: ((.proposals // {})[$r].route), answer: $w}' <<<"$S")"
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
# title, and the check interval.
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
  S="$(jq -c "$to_refs_jq"'to_refs(.repo)' "$run/state.json")"
  S="$(jq -c --arg l "$(thread_link "$(jq -r .name <<<"$S")" "$2")" --arg thread "$2" --arg env "$4" \
    '.thread = $thread | .link = $l | .env = $env | .status = "running" | .timer.fails = 0 | .timer.alerted = false' <<<"$S")"
  save
  copy_page
  jq -cn --arg run "$run" --argjson S "$S" '{run: $run, name: $S.name, every: $S.timer.every}'
}

# ---------- sync ----------
# sync: the default branch of the newest run's main checkout, fast-forwarded
# to origin's, so prune-worktrees judges, and the retro reads, the merged
# work. It only fast-forwards: the checkout is the user's, so their branch,
# commits, and edits stay. A branch that cannot move exits 0 with a
# `not updated` line, since the done run goes on to prune and retro anyway.
cmd_sync() {
  [ $# -eq 0 ] || die "usage: orchestrate.sh sync <owner/repo>"
  newest_run
  local path def new old where
  path="$(jq -r .path <<<"$S")"
  def="$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name 2>"$errf")" \
    || { printf '%s not updated: gh could not name the default branch: %s\n' "$slug" "$(tail -1 "$errf")"; return 0; }
  # The refspec is named, since the clone's own fetch refspec may leave the default branch out.
  git -C "$path" fetch --quiet origin "+refs/heads/$def:refs/remotes/origin/$def" 2>"$errf" \
    || { printf '%s not updated: fetch failed: %s\n' "$def" "$(tail -1 "$errf")"; return 0; }
  new="$(git -C "$path" rev-parse --verify --quiet "refs/remotes/origin/$def")"
  old="$(git -C "$path" rev-parse --verify --quiet "refs/heads/$def")" \
    || { printf '%s not updated: no local %s branch\n' "$def" "$def"; return 0; }
  [ "$old" != "$new" ] \
    || { printf '%s up to date at %s\n' "$def" "$(git -C "$path" rev-parse --short=7 "$new")"; return 0; }
  git -C "$path" merge-base --is-ancestor "$old" "$new" \
    || { printf '%s not updated: it has commits origin/%s lacks\n' "$def" "$def"; return 0; }
  where="$(bash "$core/checkout.sh" holder "$path" "$def")"
  if [ -n "$where" ]; then
    # Git's defaults overwrite an ignored file in the way, and a user's
    # merge.autoStash carries edits across the move into a conflict.
    git -C "$where" merge --ff-only --no-autostash --no-overwrite-ignore --quiet "$new" 2>"$errf" \
      || { printf '%s not updated: %s\n' "$def" "$(head -1 "$errf")"; return 0; }
  else
    # The old value makes git refuse a ref that moved since it was read.
    git -C "$path" update-ref "refs/heads/$def" "$new" "$old" 2>"$errf" \
      || { printf '%s not updated: %s\n' "$def" "$(head -1 "$errf")"; return 0; }
  fi
  printf '%s fast-forwarded %s..%s\n' "$def" "$(git -C "$path" rev-parse --short=7 "$old")" "$(git -C "$path" rev-parse --short=7 "$new")"
}

# ---------- watch ----------
# wake <statuses>: send the orchestrator thread `/orchestrate check`, unless T3's statuses show it
# busy: mid-turn, or waiting on the user, where a message would land as the
# answer to its question. Prints true when it sent. A failed send is left on
# stderr and not recorded, so the next watcher check tries again.
wake() {
  local thread st
  thread="$(jq -r '.thread // ""' <<<"$S")"
  st="$(jq -r --arg t "$thread" '.[$t].status // ""' <<<"$1")"
  case "$st" in
    preparing|queued|starting|running|waiting) echo false; return ;;
  esac
  if "$t3" thread send "$thread" "/orchestrate check" >/dev/null 2>"$errf"; then echo true
  else printf 'wake failed: %s\n' "$(tail -1 "$errf")" >&2; echo false; fi
}

# watcher_alive <pid>: true when <pid> runs a watcher. A pid whose command is
# not a watcher is a reused pid, as after a restart.
watcher_alive() {
  [ -n "$1" ] && [[ "$(ps -p "$1" -o command= 2>/dev/null || true)" == *"orchestrate.sh watch"* ]]
}

# stop_watcher: end the run's watcher and forget it. A pid whose command is
# not a watcher is a reused pid and is left alone.
stop_watcher() {
  local pid i
  pid="$(jq -r '.timer.watcher.pid // empty' <<<"$S")"
  if watcher_alive "$pid"; then
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
  local obs at view reasons woke=false
  read_run watch_at_limit
  at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  view="$(jq -c --arg at "$at" "$good_check_jq"'.state | good_check($at)' <<<"$obs")"
  # A conflict is claimed before it is sent, so a failed send is never tried
  # again. The task turn keeps only its holders: a watcher claims no start,
  # but a task that closed frees the turn for the other runs now.
  S="$(jq -c --arg at "$at" --argjson o "$obs" \
    "$good_check_jq$turn_jq"'.conflicts = ((.conflicts // []) + $o.sent) | take_turn($o.holders) | good_check($at)' <<<"$S")"
  save "$view" "$obs"
  local c
  while IFS= read -r c; do
    "$t3" thread send "$(jq -r .thread <<<"$c")" "$(jq -r .message <<<"$c")" >/dev/null 2>"$errf" \
      || printf 'ready-pr send failed: %s PR #%s: %s\n' "$(jq -r .label <<<"$c")" "$(jq -r .pr <<<"$c")" "$(tail -1 "$errf")" >&2
  done < <(jq -c '.sends[]' <<<"$obs")
  reasons="$(jq -c --arg h "$slug" "$label_jq"'
    [.starts[] | "start \(.label)"] + [.propose[] | "propose \(ref_label($h))"] + [.settles[] | "settle \(.label)"] + (if .done then ["done"] else [] end)' <<<"$obs")"
  [ "$reasons" = "[]" ] || woke="$(wake "$(jq -c .statuses <<<"$obs")")"
  jq -cn --argjson w "$reasons" --argjson woke "$woke" --argjson o "$obs" \
    '{wake: $w, woke: $woke, sent: [$o.sends[] | {ref, pr, thread}]}'
}

case "$cmd" in
  start) cmd_start "$@" ;;
  check) cmd_check ;;
  started) cmd_started "$@" ;;
  settled) cmd_settled "$@" ;;
  proposed) cmd_proposed "$@" ;;
  change) cmd_change "$@" ;;
  timer) cmd_timer "$@" ;;
  resume) cmd_resume "$@" ;;
  sync) cmd_sync "$@" ;;
  watch) cmd_watch "$@" ;;
  *) die "$usage" ;;
esac
