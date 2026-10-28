#!/usr/bin/env bash
# factory.sh: the factory's check, and the one writer of a run's state file.
#
# Usage: factory.sh start <owner/repo> --name <words> --link <thread link> <n>...
#        factory.sh check <owner/repo>
#        factory.sh started <owner/repo> <n> <stage> <thread-id> <link>
#        factory.sh started <owner/repo> <n> <stage> --failed <why>
#        factory.sh change <owner/repo> add <n>... | remove <n>... | restart <n>
#                          | ship full|ready <n>|all | use <n>|all [--model M] [--effort E]
#
# A run lives in ${FACTORY_HOME:-~/.agents/factory}/<owner>-<repo>/<run-id>/,
# outside every checkout, and holds one state.json: only what GitHub and T3
# do not hold. Every command works on the repo's newest run.
#
# check reads every issue of the set from GitHub and the threads from T3,
# puts each issue in its stage, and prints the threads to start. Each start
# is claimed in the state file before it is printed, so a second check never
# starts it again. It launches nothing: the agent starts each thread with
# T3's tools and records it with `started`.
#
# Exit 0: one JSON line on stdout for start and check, nothing for started
# and change.
# Exit 1: something stopped us; the reason is the last line on stderr.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$here/../../../shared"
. "$core/kickoff/labels.sh"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

usage="usage: factory.sh start|check|started|change <owner/repo> ..."
[ $# -ge 2 ] || die "$usage"
cmd="$1"; slug="$2"; shift 2
[[ "$slug" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]] || die "the repo must be owner/repo, got: $slug"
owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
runs="${FACTORY_HOME:-$HOME/.agents/factory}/$owner-$repo"

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
  [ -n "$d" ] || die "no run in $slug; say /factory <set>"
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

# ---------- start ----------
cmd_start() {
  local name="" link="" nums=() a
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --link) link="${2:-}"; shift 2 ;;
      *) [[ "$1" =~ ^#?([0-9]+)$ ]] || die "unexpected argument: $1"; nums+=("${BASH_REMATCH[1]}"); shift ;;
    esac
  done
  [ -n "$name" ] && [ -n "$link" ] && [ "${#nums[@]}" -gt 0 ] || die "usage: factory.sh start <owner/repo> --name <words> --link <thread link> <n>..."
  in_t3
  local found path
  found="$(bash "$core/checkout.sh" main "$slug")" || exit 1
  path="${found#* MAIN=}"
  run="$runs/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$runs"; mkdir "$run" || die "a run of $slug started this second; try again"
  S="$(jq -n --arg repo "$slug" --arg name "$name" --arg link "$link" --arg path "$path" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson set "$(printf '%s\n' "${nums[@]}" | jq -s 'map(tonumber) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)')" \
    '{repo: $repo, name: $name, link: $link, path: $path, started_at: $at, status: "running",
      set: $set, removed: [], ship: {default: "ready"}, use: {},
      threads: [], timer: {task: null, every: 5, fails: 0}}')"
  save
  jq -cn --arg run "$run" --argjson set "$(jq -c .set <<<"$S")" '{run: $run, set: $set}'
}

# ---------- check ----------
cmd_check() {
  in_t3
  newest_run
  # The set first, then each round of issues it brings: the open sub-issues
  # of an issue in it, and the follow-ups a PR that closes one lists.
  local issues="{}" got todo joined="[]" new t3list statuses
  todo="$(jq -c .set <<<"$S")"
  while [ "$todo" != "[]" ]; do
    # shellcheck disable=SC2046 # one word per number
    got="$(read_issues $(jq -r '.[]' <<<"$todo"))" || die "check failed: $(tail -1 "$errf")"
    issues="$(jq -c --argjson g "$got" '. + $g' <<<"$issues")"
    new="$(jq -c --argjson S "$S" "$joins" <<<"$got")"
    S="$(jq -c --argjson new "$new" '.set += $new' <<<"$S")"
    joined="$(jq -c --argjson new "$new" '. + $new' <<<"$joined")"
    todo="$new"
  done
  t3list="$("$t3" thread list --project "$(jq -r .path <<<"$S")" --json 2>"$errf")" || die "check failed: $(tail -1 "$errf")"
  statuses="$(jq -c 'map({key: .threadId, value: .status}) | from_entries' <<<"$t3list")"

  local n j st sk free blocked rec line flags model effort starts="[]" rows="[]" claims="[]"
  for n in $(jq -r '.set[]' <<<"$S"); do
    j="$(jq -c --arg n "$n" '.[$n]' <<<"$issues")"
    st="$(stage "$j" "$(jq -r .started_at <<<"$S")")"
    sk="$(skill "$st" "$(jq -r --arg n "$n" '.ship[$n] // .ship.default' <<<"$S")")"
    blocked="$(jq -c '[.blockedBy.nodes[] | select(.state == "OPEN") | .number]' <<<"$j")"
    if [ "$blocked" = "[]" ]; then free=true; else free=false; fi
    rec="$(jq -c --argjson n "$n" '[.threads[] | select(.number == $n)] | last' <<<"$S")"
    if [ -n "$sk" ] && [ "$free" = true ] \
       && [ "$(jq --argjson n "$n" --arg s "$st" '[.threads[] | select(.number == $n and .stage == $s)] | length' <<<"$S")" -eq 0 ]; then
      flags=()
      model="$(jq -r --arg n "$n" '.use[$n].model // .use.all.model // empty' <<<"$S")"
      effort="$(jq -r --arg n "$n" '.use[$n].effort // .use.all.effort // empty' <<<"$S")"
      [ -z "$model" ] || flags+=(--model "$model")
      [ -z "$effort" ] || flags+=(--effort "$effort")
      line="$(bash "$core/kickoff/decide.sh" --command "$sk" ${flags[@]+"${flags[@]}"} "https://github.com/$slug/issues/$n" 2>"$errf")" \
        || die "check failed: $(tail -1 "$errf")"
      starts="$(jq -c --argjson l "$line" --arg st "$st" \
        '. + [$l + {stage: $st, message: "/\($l.command) \($l.args)", thread_title: "\($l.label) \($l.title)", runtime_mode: "auto"}]' <<<"$starts")"
      claims="$(jq -c --argjson n "$n" --arg st "$st" '. + [{number: $n, stage: $st, thread: null, link: null, status: "pending", why: null}]' <<<"$claims")"
    fi
    rows="$(jq -c --argjson j "$j" --arg st "$st" --arg sk "$sk" --argjson free "$free" --argjson b "$blocked" \
      --argjson rec "$rec" --argjson ts "$statuses" \
      '. + [{number: $j.number, title: $j.title, stage: $st, free: $free, blocked_by: $b,
             skill: (if $sk == "" then null else $sk end),
             thread: $rec.thread, thread_status: (if $rec.thread then $ts[$rec.thread] else null end),
             prs: [$j.closedByPullRequestsReferences.nodes[] | {number, url, state}]}]' <<<"$rows")"
  done

  S="$(jq -c --argjson c "$claims" '.threads += $c | .timer.fails = 0' <<<"$S")"
  save
  jq -cn --arg run "$run" --argjson S "$S" --argjson starts "$starts" --argjson rows "$rows" \
    --argjson joined "$joined" \
    '{run: $run, status: $S.status, starts: $starts, issues: $rows, joined: $joined, done: false}'
}

# ---------- started ----------
# started <n> <stage> <thread-id> <link>, or <n> <stage> --failed <why>: the
# claim of that stage becomes the thread the agent launched, or a failed
# launch. A failed one is never started again; `restart` clears it.
cmd_started() {
  [ $# -eq 4 ] || die "usage: factory.sh started <owner/repo> <n> <stage> <thread-id> <link> | --failed <why>"
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

# ---------- change ----------
# change add <n>... and remove <n>...: the set. A removed issue keeps its
# thread records and never joins again by itself.
# change restart <n>: drop #n's newest thread record, so the next check
# starts a fresh thread at #n's stage.
# change ship full|ready <n>|all: how a ticket ships. It reaches only issues
# whose ticket thread has not started: for `all`, each started one keeps the
# old default as its own.
# change use <n>|all: the model and effort a thread gets, for one issue or
# for all; one issue's value wins, field by field.
cmd_change() {
  newest_run
  local what="${1:-}" nums a
  case "$what" in
    add|remove)
      shift; [ $# -gt 0 ] || die "usage: factory.sh change <owner/repo> $what <n>..."
      for a in "$@"; do [[ "$a" =~ ^#?[0-9]+$ ]] || die "unexpected argument: $a"; done
      nums="$(printf '%s\n' "$@" | tr -d '#' | jq -cs .)"
      if [ "$what" = add ]; then
        S="$(jq -c --argjson a "$nums" '.set += [$a[] as $x | select(.set | index([$x]) | not) | $x] | .removed -= $a' <<<"$S")"
      else
        S="$(jq -c --argjson a "$nums" '.set -= $a | .removed += [$a[] as $x | select(.removed | index([$x]) | not) | $x]' <<<"$S")"
      fi
      ;;
    restart)
      [[ "${2:-}" =~ ^#?([0-9]+)$ ]] || die "usage: factory.sh change <owner/repo> restart <n>"
      local n="${BASH_REMATCH[1]}"
      [ "$(jq --argjson n "$n" '[.threads[] | select(.number == $n)] | length' <<<"$S")" -gt 0 ] \
        || die "#$n has no thread to restart"
      S="$(jq -c --argjson n "$n" '(.threads | map(.number == $n) | rindex(true)) as $i | .threads |= del(.[$i])' <<<"$S")"
      ;;
    ship)
      [[ "${2:-}" =~ ^(full|ready)$ ]] && [[ "${3:-}" =~ ^(all|#?[0-9]+)$ ]] \
        || die "usage: factory.sh change <owner/repo> ship full|ready <n>|all"
      local mode="$2" who="${3#\#}"
      if [ "$who" = all ]; then
        S="$(jq -c --arg m "$mode" '
          .ship.default as $d
          | reduce (.threads[] | select(.stage == "ticket") | .number | tostring) as $n (.; .ship[$n] //= $d)
          | .ship.default = $m' <<<"$S")"
      else
        [ "$(jq --argjson n "$who" '[.threads[] | select(.number == $n and .stage == "ticket")] | length' <<<"$S")" -eq 0 ] \
          || die "#$who has started; its mode stays ship-$(jq -r --arg n "$who" '.ship[$n] // .ship.default' <<<"$S")"
        S="$(jq -c --arg n "$who" --arg m "$mode" '.ship[$n] = $m' <<<"$S")"
      fi
      ;;
    use)
      [[ "${2:-}" =~ ^(all|#?[0-9]+)$ ]] || die "usage: factory.sh change <owner/repo> use <n>|all [--model M] [--effort E]"
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
    *) die "usage: factory.sh change <owner/repo> add|remove|restart|ship|use ..." ;;
  esac
  save
}

case "$cmd" in
  start) cmd_start "$@" ;;
  check) cmd_check ;;
  started) cmd_started "$@" ;;
  change) cmd_change "$@" ;;
  *) die "$usage" ;;
esac
