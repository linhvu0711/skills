#!/usr/bin/env bash
# box.sh: hold the one proofbox Sandbox of a build-and-prove run, and write its
# checks.txt. Coding runs on the local machine; for a plan with UI walks, the
# Gates, the app, and the walks run in this Sandbox. A plan with no UI starts
# none, and runs its Gates on the local machine with `gates --local`.
#
#   box.sh auth <linux|macos>
#   box.sh up <proof-dir> <worktree> <linux|macos> <owner/repo>
#   box.sh run <proof-dir> [--from <folder>] -- <command>...
#   box.sh start <proof-dir> [--from <folder>] [--url <url>] -- <Run line>
#   box.sh stop <proof-dir> [--url <url>]
#   box.sh open <proof-dir> -- <command>...
#   box.sh close <proof-dir>
#   box.sh gates <proof-dir> [--local <worktree>] [--on-local <command>]...
#                [--not-run <command> <why>]... -- <command>...
#   box.sh down <proof-dir>
#
# auth checks the login of the Provider that ~/.config/proofbox/config picks
# for the OS (namespace when it names none), from `proofbox auth status`, so a
# run can stop before any work. Logged in, or no login needed: it prints
# PROVIDER=<name>.
#
# up creates the Sandbox with the repo's setup script, and its Secrets file and
# size when there are, from ~/.agents/proofbox/<owner>-<repo>/: setup-<os>.sh,
# app.env, passed as --secrets, and size, one line such as 8x16, passed as
# --size; with no size file it passes no --size, so proofbox's default applies. It passes no
# --provider, so ~/.config/proofbox/config picks it. It shows on stderr every
# line proofbox prints while it makes the Sandbox: the Setup script's last
# lines when it fails, the Snapshot line when it reuses one.
# The idle time is 30m on linux and 10m on macos, where a minute costs ten
# times more and a new Sandbox costs 1 to 3. It passes no --max-life, so
# proofbox's 3h applies, which every Namespace plan allows. The state goes in
# <proof-dir>/box.env as KEY=value lines: BOX_ID, BOX_OS, BOX_WORK,
# BOX_SETUP, BOX_ENV, BOX_REMADE, BOX_SIZE, and BOX_TREE, the tree the Sandbox
# holds: `base` after an upload with --from, `branch` after any other upload or
# a create.
#
# run uploads the worktree's changed files, runs the command in the Sandbox,
# and exits with its code. --from uploads that folder instead, such as a copy
# of the base for before shots; the next run without it puts the worktree
# back. A Sandbox that is gone (idle, or past its max life) at the upload or
# the exec is made again once, from the same setup, and the command runs
# again; BOX_REMADE counts these. Each upload notes its tree in BOX_TREE.
#
# start starts the app in the Sandbox from the plan's Run line, after the same
# upload and one remake as run: the Run line runs as `sh -c`, with its output in
# /tmp/app.log, in its own process group, whose id goes in /tmp/app.pid, so
# stop reaches every process it starts. It prints TREE=base or TREE=branch,
# the tree it runs. With --url it then waits up to 120 s for the URL to
# answer, one try every 2 s; it does not: the log's last 50 lines on stderr,
# then a stop.
#
# stop sends TERM to the app's process group, waits up to 30 s for it to end,
# then sends KILL. With --url it then waits up to 30 s, one try a second, until
# nothing answers there (curl exits 7), so the port is free for the next start;
# still answering is a stop. It stops by the group's id, never by name: pkill
# and killall can match the shell that runs them. A Sandbox gone under it has
# no app to stop: it says so and exits 0.
#
# open and close are the walker's: open runs its command, a browser or a
# terminal window, in its own process group, whose id goes in
# /tmp/walk-open.pid; close ends that group as stop does, with a 10 s wait, and
# exits 0 when the window already closed. Neither uploads or makes a gone
# Sandbox again: proofbox's `Sandbox <id> is gone` line reaches stderr and the
# exit code is proofbox's, so the walker sees the Sandbox died.
#
# gates runs each command, in order, as `sh -c '<command>'`, through the same
# upload and one remake as run. Each command's output goes to its own file in a
# box-gates.* temp folder, outside the proof folder, named on stderr as
# `logs: <folder>`. It writes <proof-dir>/checks.txt fresh, one line per
# command: `<command> · <short SHA> · <last non-empty output line> (sandbox)`.
# A command that exits non-zero gets `<command> · <short SHA> · red, exit
# <code>: <last non-empty output line> (sandbox)` and a stderr line
# `red: <command> · exit <code> · output <file>`; the other commands still run.
# A red command that exits 127 or prints `not found` also gets `missing tool:
# <command> · <that line>` on stderr. gates exits 3 when any command is red,
# 0 when all are green. A stop leaves the old checks.txt as it was.
#
# The caller names its special Gates as options, and gates writes their lines
# after the others, each kind in the order given:
#   --on-local <command>      a Gate the Sandbox cannot run, such as one that
#                             needs Docker: it runs on the local machine in the
#                             worktree, its line ending `(local machine)`.
#                             Not with --local, where every Gate runs there.
#   --not-run <command> <why> a Gate that runs nowhere: `<command> · <short
#                             SHA> · not run: <why>`.
# Each call writes every line of checks.txt again, so a caller passes its
# special Gates on every call. At least one Gate, of any kind.
#
# gates --local <worktree> needs no Sandbox and no proofbox. It asks the shared
# core's ci-covers.sh which commands the PR's GitHub CI runs; each of those is
# not run, and its line is `<command> · <short SHA> · not run: CI runs it
# (<workflow file>)`. It runs each other command on the local machine, one at
# a time, as `sh -c '<command>'` in <worktree>, and takes the short SHA from
# there. Its lines end `(local machine)` in place of `(sandbox)`; the rest is
# the same, so checks.txt keeps one writer and one line shape.
#
# up with a box.env already in <proof-dir> reuses that Sandbox and prints its
# id; it creates nothing.
#
# down deletes the Sandbox and the state, and prints REMADE=<n>.
#
# Exit 1, in every verb: `stop: <why>` as the last stderr line. An upload that
# fails for another reason than a gone Sandbox is a stop too.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

idle() { [ "$1" = macos ] && echo 10m || echo 30m; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cover="$here/../../../shared/ci-covers.sh"

usage="usage: box.sh auth <linux|macos> | up <proof-dir> <worktree> <linux|macos> <owner/repo> | run <proof-dir> [--from <folder>] -- <command>... | start <proof-dir> [--from <folder>] [--url <url>] -- <Run line> | stop <proof-dir> [--url <url>] | open <proof-dir> -- <command>... | close <proof-dir> | gates <proof-dir> [--local <worktree>] [--on-local <command>]... [--not-run <command> <why>]... -- <command>... | down <proof-dir>"
verb="${1:-}"; [ $# -gt 0 ] && shift
# Only `gates --local` runs without proofbox.
[ "$verb" = gates ] && [ "${2:-}" = --local ] || command -v proofbox >/dev/null || die "proofbox is not installed"

# create: make a Sandbox from the BOX_* values and write the state. proofbox's
# stderr reaches the caller live; a copy is kept for its last line.
create() {
  local args=(create --os "$BOX_OS" --work "$BOX_WORK" --setup "$BOX_SETUP") id errf c=0
  [ -z "$BOX_ENV" ] || args+=(--secrets "$BOX_ENV")
  [ -z "$BOX_SIZE" ] || args+=(--size "$BOX_SIZE")
  args+=(--idle "$(idle "$BOX_OS")")
  errf="$(mktemp)"
  set +e
  id="$( { proofbox "${args[@]}" 2>&1 1>&3 3>&- | tee "$errf" 1>&2; exit "${PIPESTATUS[0]}"; } 3>&1 )"; c=$?
  set -e
  if [ "$c" -ne 0 ]; then
    local why login
    why="$(tail -n 1 "$errf")"; rm -f "$errf"
    login="$(grep -o 'proofbox auth login [a-z]*' <<<"$why" || true)"
    [ -z "$login" ] || die "log in first: $login"
    die "${why:-proofbox create failed}"
  fi
  rm -f "$errf"
  BOX_ID="$(tail -n 1 <<<"$id")"
  # create uploads --work, the worktree.
  BOX_TREE=branch
  save
}

# save: write the state under a temp name, then move it into place, so a stop
# mid-write leaves the old file whole.
save() {
  printf 'BOX_ID=%s\nBOX_OS=%s\nBOX_WORK=%s\nBOX_SETUP=%s\nBOX_ENV=%s\nBOX_REMADE=%s\nBOX_SIZE=%s\nBOX_TREE=%s\n' \
    "$BOX_ID" "$BOX_OS" "$BOX_WORK" "$BOX_SETUP" "$BOX_ENV" "$BOX_REMADE" "$BOX_SIZE" "$BOX_TREE" > "$dir/box.env.tmp"
  mv "$dir/box.env.tmp" "$dir/box.env"
}

# load: read the state as text, its eight keys only; the file never runs.
load() {
  [ -f "$dir/box.env" ] || die "no Sandbox for $dir; run box.sh up first"
  BOX_ID=""; BOX_OS=""; BOX_WORK=""; BOX_SETUP=""; BOX_ENV=""; BOX_REMADE=0; BOX_SIZE=""; BOX_TREE=""
  local k v
  while IFS='=' read -r k v; do
    case "$k" in
      BOX_ID) BOX_ID="$v" ;; BOX_OS) BOX_OS="$v" ;; BOX_WORK) BOX_WORK="$v" ;;
      BOX_SETUP) BOX_SETUP="$v" ;; BOX_ENV) BOX_ENV="$v" ;; BOX_REMADE) BOX_REMADE="$v" ;;
      BOX_SIZE) BOX_SIZE="$v" ;; BOX_TREE) BOX_TREE="$v" ;;
    esac
  done < "$dir/box.env"
}

# attempt <command>...: upload, then exec. Sets `gone` when proofbox says the
# Sandbox is gone, at either step; otherwise sets `rc` to the command's code.
# With `log` empty, exec's stderr still reaches the caller live, and a copy is
# kept to tell a gone Sandbox (125 and its line) from the command's own exit
# code. With `log` set, exec's stdout and stderr go to that file with no pipe,
# so nothing can stand in for the command's own code.
attempt() {
  local errf src c=0
  errf="$(mktemp)"
  gone=""; rc=0
  proofbox upload "$BOX_ID" "${from:-$BOX_WORK}" >/dev/null 2>"$errf" || c=$?
  if [ "$c" -ne 0 ]; then
    if grep -q "Sandbox $BOX_ID is gone" "$errf"; then gone="$(tail -n 1 "$errf")"; rm -f "$errf"; return; fi
    local why; why="$(tail -n 1 "$errf")"
    cat "$errf" >&2; rm -f "$errf"; die "${why:-proofbox upload failed}"
  fi
  if [ -n "${from:-}" ]; then BOX_TREE=base; else BOX_TREE=branch; fi
  save
  set +e
  if [ -n "${log:-}" ]; then
    proofbox exec "$BOX_ID" -- "$@" >"$log" 2>&1; c=$?
    src="$log"
  else
    { proofbox exec "$BOX_ID" -- "$@" 2>&1 1>&3 3>&- | tee "$errf" 1>&2; c=${PIPESTATUS[0]}; } 3>&1
    src="$errf"
  fi
  set -e
  if [ "$c" -eq 125 ] && grep -q "Sandbox $BOX_ID is gone" "$src"; then gone="$(tail -n 1 "$src")"; rm -f "$errf"; return; fi
  rm -f "$errf"
  rc="$c"
}

# in_box <command>...: attempt, and when the Sandbox is gone make it again once
# and attempt again. Sets `rc`; a Sandbox gone twice is a stop.
in_box() {
  local old was
  attempt "$@"
  [ -n "$gone" ] || return 0
  old="$gone"; was="$BOX_ID"
  BOX_REMADE=$((BOX_REMADE + 1))
  create
  printf 'Sandbox %s is gone; made %s from its Snapshot\n' "$was" "$BOX_ID" >&2
  attempt "$@"
  [ -n "$gone" ] || return 0
  die "$old"
}

# bare <command>...: one exec with no upload and no remake. An upload would put
# the branch over the base the before shots run, and a new Sandbox has no app
# to wait for or stop. The output goes to stderr, so stdout keeps only
# box.sh's own KEY=value lines. Sets `rc`, and `gone` when proofbox says the
# Sandbox is gone.
bare() {
  local errf
  errf="$(mktemp)"; gone=""
  set +e
  { proofbox exec "$BOX_ID" -- "$@" 2>&1 1>&3 3>&- | tee "$errf" 1>&2; rc=${PIPESTATUS[0]}; } 3>&2
  set -e
  if [ "$rc" -eq 125 ] && grep -q "Sandbox $BOX_ID is gone" "$errf"; then gone="$(tail -n 1 "$errf")"; fi
  rm -f "$errf"
}

# group_argv <pid file> <log file> <command>: set `gcmd` to a launch of the
# command in its own process group, with the group's id in <pid file>. A Run
# line such as `pnpm build && pnpm preview` runs its server under an outer sh,
# and a kill of that sh alone leaves the server on its port. Linux's sh turns
# `set -m` off with no terminal, and macOS has no setsid. The command goes in
# as $1, never pasted into the script, so its quotes need no escape.
group_argv() {
  if [ "$BOX_OS" = macos ]; then
    gcmd=(sh -c "set -m; sh -c \"\$1\" >$2 2>&1 & echo \$! >$1" sh "$3")
  else
    gcmd=(setsid -w sh -c "sh -c \"\$1\" >$2 2>&1 & echo \$\$ >$1" sh "$3")
  fi
}

# group_stop <pid file> <limit>: TERM the group whose id is in <pid file>, wait
# up to <limit> s for it to end, then KILL it. No pid file: nothing to stop. It
# ends `true`, so a group that already ended is no failure.
group_stop() {
  bare sh -c 'g=$(cat "$1" 2>/dev/null) || exit 0; kill -TERM -"$g" 2>/dev/null; i=0; while kill -0 -"$g" 2>/dev/null && [ $i -lt "$2" ]; do i=$((i+1)); sleep 1; done; kill -KILL -"$g" 2>/dev/null; true' sh "$1" "$2"
}

case "$verb" in
  up)
    [ $# -eq 4 ] || die "$usage"
    dir="$1"; BOX_WORK="$2"; BOX_OS="$3"; slug="${4/\//-}"; BOX_REMADE=0
    case "$BOX_OS" in linux|macos) ;; *) die "os must be linux or macos, not $BOX_OS" ;; esac
    home="$HOME/.agents/proofbox/$slug"
    BOX_SETUP="$home/setup-$BOX_OS.sh"
    [ -f "$BOX_SETUP" ] || die "no setup script at $BOX_SETUP"
    BOX_ENV=""; [ ! -f "$home/app.env" ] || BOX_ENV="$home/app.env"
    BOX_SIZE=""; [ ! -f "$home/size" ] || BOX_SIZE="$(tr -d '[:space:]' < "$home/size")"
    # A Sandbox already in <proof-dir>, such as one Coding started for a
    # missing tool, is the run's Sandbox: keep it.
    if [ -f "$dir/box.env" ]; then load; printf 'SANDBOX=%s\n' "$BOX_ID"; exit 0; fi
    mkdir -p "$dir"
    create
    printf 'SANDBOX=%s\n' "$BOX_ID"
    ;;
  run)
    [ $# -ge 1 ] || die "$usage"
    dir="$1"; shift; from=""
    if [ "${1:-}" = "--from" ]; then
      [ -d "${2:-}" ] || die "--from needs a folder"
      from="$2"; shift 2
    fi
    [ "${1:-}" = "--" ] && [ $# -ge 2 ] || die "$usage"
    shift
    load
    in_box "$@"
    exit "$rc"
    ;;
  start)
    [ $# -ge 1 ] || die "$usage"
    dir="$1"; shift; from=""; url=""
    while :; do
      case "${1:-}" in
        --from) [ -d "${2:-}" ] || die "--from needs a folder"; from="$2"; shift 2 ;;
        --url) [ -n "${2:-}" ] || die "--url needs a URL"; url="$2"; shift 2 ;;
        *) break ;;
      esac
    done
    [ "${1:-}" = "--" ] && [ $# -ge 2 ] || die "$usage"
    shift
    load
    group_argv /tmp/app.pid /tmp/app.log "$*"
    in_box "${gcmd[@]}"
    [ "$rc" -eq 0 ] || die "the app did not start: exit $rc"
    printf 'TREE=%s\n' "$BOX_TREE"
    [ -n "$url" ] || exit 0
    bare sh -c 'for i in $(seq 60); do curl -fsS -o /dev/null "$1" && exit 0; sleep 2; done; exit 1' sh "$url"
    [ "$rc" -ne 0 ] || exit 0
    [ -z "$gone" ] || die "$gone"
    bare tail -n 50 /tmp/app.log
    die "$url did not answer in 120 s; the app log's last lines are above"
    ;;
  stop)
    [ $# -ge 1 ] || die "$usage"
    dir="$1"; shift; url=""
    if [ "${1:-}" = "--url" ]; then
      [ -n "${2:-}" ] || die "--url needs a URL"
      url="$2"; shift 2
    fi
    [ $# -eq 0 ] || die "$usage"
    load
    group_stop /tmp/app.pid 30
    if [ -n "$gone" ]; then printf '%s; nothing to stop\n' "$gone" >&2; exit 0; fi
    [ "$rc" -eq 0 ] || exit "$rc"
    [ -n "$url" ] || exit 0
    bare sh -c 'for i in $(seq 30); do curl -s -o /dev/null "$1"; [ $? -eq 7 ] && exit 0; sleep 1; done; exit 1' sh "$url"
    [ "$rc" -eq 0 ] || die "$url still answers after the app stopped"
    ;;
  open)
    [ $# -ge 3 ] && [ "$2" = "--" ] || die "$usage"
    dir="$1"; shift 2
    load
    group_argv /tmp/walk-open.pid /dev/null "$*"
    bare "${gcmd[@]}"
    exit "$rc"
    ;;
  close)
    [ $# -eq 1 ] || die "$usage"
    dir="$1"
    load
    group_stop /tmp/walk-open.pid 10
    exit "$rc"
    ;;
  gates)
    [ $# -ge 1 ] || die "$usage"
    dir="$1"; shift; local_wt=""; on_local=(); not_run=()
    # --local stays first, so the proofbox check above sees it.
    if [ "${1:-}" = "--local" ]; then
      [ -d "${2:-}" ] || die "--local needs a worktree"
      local_wt="$2"; shift 2
    fi
    while [ $# -gt 0 ] && [ "$1" != -- ]; do
      case "$1" in
        --on-local) [ $# -ge 2 ] || die "$usage"; on_local+=("$2"); shift 2 ;;
        --not-run) [ $# -ge 3 ] || die "$usage"; not_run+=("$2" "$3"); shift 3 ;;
        *) die "$usage" ;;
      esac
    done
    [ "${1:-}" = "--" ] || die "$usage"
    shift
    [ $# -ge 1 ] || [ ${#on_local[@]} -ge 1 ] || [ ${#not_run[@]} -ge 1 ] || die "$usage"
    [ -z "$local_wt" ] || [ ${#on_local[@]} -eq 0 ] \
      || die "--on-local runs a Gate the Sandbox cannot; with --local every Gate runs on the local machine"
    if [ -n "$local_wt" ]; then mode=local; work="$local_wt"
    else load; mode=sandbox; work="$BOX_WORK"; fi
    mkdir -p "$dir"
    tmpd="${TMPDIR:-/tmp}"; logs="$(mktemp -d "${tmpd%/}/box-gates.XXXXXX")"
    sha="$(git -C "$work" rev-parse --short HEAD)"
    # checks.txt is moved into place whole, so a stop leaves the old one.
    tmp="$dir/checks.txt.tmp"
    trap 'rm -f "$tmp"' EXIT
    # With --local, a Gate the PR's CI runs is left to CI: covered[i] is its
    # workflow file, or empty.
    covered=()
    if [ -n "$local_wt" ] && [ $# -ge 1 ]; then
      cerr="$(mktemp)"
      cover_out="$(bash "$cover" "$local_wt" -- "$@" 2>"$cerr")" || die "$(tail -n 1 "$cerr")"
      rm -f "$cerr"
      while IFS= read -r v; do
        v="${v%% · *}"
        case "$v" in "ci "*) covered+=("${v#ci }") ;; *) covered+=("") ;; esac
      done <<<"$cover_out"
    fi
    : > "$tmp"
    n=0; red=0

    # gate <command> <local|sandbox>: run it there, write its line, and name
    # it on stderr when it is red.
    gate() {
      local cmd="$1" where last miss
      n=$((n + 1)); log="$logs/$n.log"
      if [ "$2" = sandbox ]; then
        where="sandbox"; in_box sh -c "$cmd"
      else
        where="local machine"; rc=0; (cd "$work" && sh -c "$cmd") >"$log" 2>&1 || rc=$?
      fi
      last="$(tr -d '\r' < "$log" | awk 'NF { l = $0 } END { print l }')"
      last="${last:-no output}"
      if [ "$rc" -eq 0 ]; then
        printf '%s · %s · %s (%s)\n' "$cmd" "$sha" "$last" "$where" >> "$tmp"
      else
        red=1
        printf '%s · %s · red, exit %s: %s (%s)\n' "$cmd" "$sha" "$rc" "$last" "$where" >> "$tmp"
        printf 'red: %s · exit %s · output %s\n' "$cmd" "$rc" "$log" >&2
        miss="$(grep -m 1 'not found' "$log" || true)"
        [ "$rc" -ne 127 ] || miss="${miss:-exit 127}"
        [ -z "$miss" ] || printf 'missing tool: %s · %s\n' "$cmd" "$miss" >&2
      fi
    }

    i=0
    for cmd in "$@"; do
      i=$((i + 1))
      if [ -n "${covered[$((i - 1))]:-}" ]; then
        printf '%s · %s · not run: CI runs it (%s)\n' "$cmd" "$sha" "${covered[$((i - 1))]}" >> "$tmp"
      else
        gate "$cmd" "$mode"
      fi
    done
    for cmd in ${on_local[@]+"${on_local[@]}"}; do gate "$cmd" local; done
    set -- ${not_run[@]+"${not_run[@]}"}
    while [ $# -ge 2 ]; do
      printf '%s · %s · not run: %s\n' "$1" "$sha" "$2" >> "$tmp"; shift 2
    done
    mv "$tmp" "$dir/checks.txt"
    printf 'logs: %s\n' "$logs" >&2
    [ "$red" -eq 0 ] || exit 3
    ;;
  down)
    [ $# -eq 1 ] || die "$usage"
    dir="$1"
    load
    proofbox delete "$BOX_ID" >/dev/null
    rm -f "$dir/box.env"
    printf 'REMADE=%s\n' "$BOX_REMADE"
    ;;
  auth)
    [ $# -eq 1 ] || die "$usage"
    case "$1" in linux|macos) ;; *) die "os must be linux or macos, not $1" ;; esac
    conf="$HOME/.config/proofbox/config"; provider=""
    [ ! -f "$conf" ] || provider="$(sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([a-z]*\)\".*/\1/p" "$conf" | head -n 1)"
    provider="${provider:-namespace}"
    status="$(proofbox auth status 2>/dev/null)" || die "proofbox auth status failed"
    line="$(grep -m 1 "^$provider " <<<"$status" || true)"
    [ -n "$line" ] || die "proofbox auth status has no line for $provider"
    state="$(sed 's/^[^ ]*  *//' <<<"$line")"
    case "$state" in
      "logged in"*|"no login needed"*) printf 'PROVIDER=%s\n' "$provider" ;;
      "not logged in"*|expired*) die "log in first: proofbox auth login $provider" ;;
      *) die "$state" ;;
    esac
    ;;
  *) die "$usage" ;;
esac
