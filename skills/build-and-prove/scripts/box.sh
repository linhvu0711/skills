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
#   box.sh close <proof-dir> [--out <file>]
#   box.sh fit <proof-dir>
#   box.sh gates <proof-dir> [--local <worktree> | --ci <worktree>]
#                [--on-local <command>]...
#                [--not-run <command> <why>]... -- <command>...
#   box.sh down <proof-dir>
#
# auth first checks that `proofbox click --help` lists --mark, which the walker
# sets on each step's action; an older proofbox stops it with `stop: proofbox
# is too old: run proofbox update`. Then it checks the login of the Provider
# that ~/.config/proofbox/config picks for the OS (namespace when it names
# none), from `proofbox auth status --json`, so a run can stop before any
# work. Logged in, or no login needed: it prints PROVIDER=<name>.
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
# the app's group stopped as stop does, then a stop.
#
# stop sends TERM to the app's process group, waits up to 30 s for it to end,
# then sends KILL. With --url it then waits up to 30 s, one try a second, until
# nothing answers there (curl exits 7), so the port is free for the next start;
# still answering is a stop. It stops by the group's id, never by name: pkill
# and killall can match the shell that runs them. A Sandbox gone under it has
# no app to stop: it says so and exits 0.
#
# open and close are the walker's: open writes the browser starter,
# walk-browser.cjs, to /tmp/pb-walk/walk-browser, then runs its command, a
# browser or a terminal window, with /tmp/pb-walk first on PATH and
# WALK_BROWSER_LOG set to the browser log, walk_log below, in its own process
# group, whose id goes in
# /tmp/walk-open.pid; close ends that group as stop does, with a 10 s wait, and
# exits 0 when the window already closed. With --out, close then copies the
# browser log to <file> next to the video: `none` when the log is empty,
# `missing: <the log's path>` when there is no log. Either way it removes that log, so the next video's log holds only its
# own lines. Neither uploads or makes a gone Sandbox again: proofbox's `Sandbox <id> is gone` line reaches stderr and the
# exit code is proofbox's, so the walker sees the Sandbox died.
#
# fit is the walker's check before a recording: does the active window, the
# browser, end above the taskbar? On linux it reads the window's bottom with
# xdotool and the bottom of the screen's work area, the screen less fluxbox's
# taskbar, with xprop, and prints `FIT window bottom <b> · screen bottom <s>`,
# or `TALL ...` and exits 3 when the window runs past it. A page cannot tell:
# Playwright makes its screen size the viewport's. On macos it checks nothing
# and prints `FIT not checked on macos`. Like open, it neither uploads nor
# makes a gone Sandbox again.
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
# gates --ci <worktree> leaves to the PR's CI each Gate after -- that
# ci-covers.sh finds in <worktree>'s workflows, with the same `not run: CI runs
# it` line, and runs the rest as above; --on-local Gates still run on the local
# machine. It needs proofbox and loads the Sandbox only when a
# Gate after -- is left for it; with no Sandbox up, that is a stop that names
# `box.sh up`. The short SHA comes from <worktree>.
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
walk_log=/tmp/walk-browser.log
cover="$here/../../../shared/ci-covers.sh"

usage="usage: box.sh auth <linux|macos> | up <proof-dir> <worktree> <linux|macos> <owner/repo> | run <proof-dir> [--from <folder>] -- <command>... | start <proof-dir> [--from <folder>] [--url <url>] -- <Run line> | stop <proof-dir> [--url <url>] | open <proof-dir> -- <command>... | close <proof-dir> [--out <file>] | fit <proof-dir> | gates <proof-dir> [--local <worktree> | --ci <worktree>] [--on-local <command>]... [--not-run <command> <why>]... -- <command>... | down <proof-dir>"
verb="${1:-}"; [ $# -gt 0 ] && shift
# gates checks for proofbox itself, when it loads the Sandbox.
[ "$verb" = gates ] || command -v proofbox >/dev/null || die "proofbox is not installed"

# create: make a Sandbox from the BOX_* values and write the state. proofbox's
# stderr reaches the caller live; a copy is kept for its last line.
create() {
  local args=(create --os "$BOX_OS" --work "$BOX_WORK" --setup "$BOX_SETUP") login
  [ -z "$BOX_ENV" ] || args+=(--secrets "$BOX_ENV")
  [ -z "$BOX_SIZE" ] || args+=(--size "$BOX_SIZE")
  args+=(--idle "$(idle "$BOX_OS")")
  pb keep show "${args[@]}"
  if [ "$rc" -ne 0 ]; then
    login="$(grep -o 'proofbox auth login [a-z]*' <<<"$why" || true)"
    [ -z "$login" ] || die "log in first: $login"
    die "${why:-proofbox create failed}"
  fi
  BOX_ID="$(tail -n 1 <<<"$got")"
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

# pb <out> <err> <proofbox args>...: the one place box.sh runs proofbox, so a
# gone Sandbox is told from a failed command by one rule: exit 125 and the line
# `Sandbox <id> is gone`. <out> takes proofbox's stdout: stdout, stderr, null,
# keep (read into `got`), or a file the caller keeps. <err> takes its stderr:
# show (live on box.sh's stderr, a copy kept), keep (the copy only, read into
# `said`), or out (into the <out> file with no pipe, so nothing can stand in
# for proofbox's own code). Sets `rc`, `why` (the last stderr line), `gone`
# (that line when the Sandbox is gone, else empty), `said`, and `got`.
pb() {
  local out="$1" err="$2" copy keepf="" src
  shift 2
  copy="$(mktemp)"; src="$copy"
  case "$out" in
    stdout) exec 3>&1 ;;
    stderr) exec 3>&2 ;;
    null) exec 3>/dev/null ;;
    keep) keepf="$(mktemp)"; exec 3>"$keepf" ;;
    *) exec 3>"$out" ;;
  esac
  set +e
  case "$err" in
    show) { proofbox "$@" 2>&1 1>&3 3>&- | tee "$copy" 1>&2; rc=${PIPESTATUS[0]}; } ;;
    keep) proofbox "$@" 2>"$copy" 1>&3 3>&-; rc=$? ;;
    out) proofbox "$@" 1>&3 2>&1 3>&-; rc=$?; src="$out" ;;
  esac
  set -e
  exec 3>&-
  why="$(tail -n 1 "$src")"; said=""; got=""; gone=""
  [ "$err" != keep ] || said="$(cat "$copy")"
  [ -z "$keepf" ] || { got="$(cat "$keepf")"; rm -f "$keepf"; }
  if [ -n "${BOX_ID:-}" ] && [ "$rc" -eq 125 ] && grep -q "Sandbox $BOX_ID is gone" "$src"; then gone="$why"; fi
  rm -f "$copy"
}

# attempt <from> <log> <command>...: upload <from>, or the worktree when it is
# empty, then exec. Sets `gone` when the Sandbox is gone at either step;
# otherwise sets `rc` to the command's code. With <log> empty, the command's
# output reaches the caller live; with <log>, both its streams go to that file.
attempt() {
  local from="$1" log="$2"
  shift 2
  pb null keep upload "$BOX_ID" "${from:-$BOX_WORK}"
  [ -z "$gone" ] || return 0
  if [ "$rc" -ne 0 ]; then
    [ -z "$said" ] || printf '%s\n' "$said" >&2
    die "${why:-proofbox upload failed}"
  fi
  if [ -n "$from" ]; then BOX_TREE=base; else BOX_TREE=branch; fi
  save
  if [ -n "$log" ]; then pb "$log" out exec "$BOX_ID" -- "$@"
  else pb stdout show exec "$BOX_ID" -- "$@"; fi
}

# in_box <from> <log> <command>...: attempt, and when the Sandbox is gone make
# it again once and attempt again. Sets `rc`; a Sandbox gone twice is a stop.
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
bare() { pb stderr show exec "$BOX_ID" -- "$@"; }

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
    in_box "$from" "" "$@"
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
    in_box "$from" "" "${gcmd[@]}"
    [ "$rc" -eq 0 ] || die "the app did not start: exit $rc"
    printf 'TREE=%s\n' "$BOX_TREE"
    [ -n "$url" ] || exit 0
    bare sh -c 'for i in $(seq 60); do curl -fsS -o /dev/null "$1" && exit 0; sleep 2; done; exit 1' sh "$url"
    [ "$rc" -ne 0 ] || exit 0
    [ -z "$gone" ] || die "$gone"
    bare tail -n 50 /tmp/app.log
    # A slow app may still hold the port; the next start needs it free.
    group_stop /tmp/app.pid 30
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
    if [ -n "$gone" ]; then printf '%s; nothing to stop\n' "$gone" >&2; exit 0; fi
    [ "$rc" -eq 0 ] || die "$url still answers after the app stopped"
    ;;
  open)
    [ $# -ge 3 ] && [ "$2" = "--" ] || die "$usage"
    dir="$1"; shift 2
    load
    # proofbox runs an argument list with no shell, and the Work folder holds
    # only the repo, so the starter goes in as text, its path a separate word.
    bare sh -c 'mkdir -p "${2%/*}" && printf "%s\n" "$1" > "$2" && chmod +x "$2"' sh "$(cat "$here/walk-browser.cjs")" /tmp/pb-walk/walk-browser
    [ "$rc" -eq 0 ] || exit "$rc"
    group_argv /tmp/walk-open.pid /dev/null "export PATH=/tmp/pb-walk:\$PATH WALK_BROWSER_LOG=$walk_log; $*"
    bare "${gcmd[@]}"
    exit "$rc"
    ;;
  close)
    [ $# -eq 1 ] || { [ $# -eq 3 ] && [ "$2" = --out ]; } || die "$usage"
    dir="$1"; out="${3:-}"
    load
    group_stop /tmp/walk-open.pid 10
    [ -z "$gone" ] || exit "$rc"
    stopped="$rc"
    if [ -n "$out" ]; then
      pb "$out.tmp" keep exec "$BOX_ID" -- cat "$walk_log"
      if [ -n "$gone" ]; then
        [ -z "$said" ] || printf '%s\n' "$said" >&2
        rm -f "$out.tmp"; exit 125
      fi
      # The walker fails the walk's console and request checks on this line,
      # so close still exits 0 and the walk goes on.
      if [ "$rc" -ne 0 ]; then
        printf 'missing: %s\n' "$walk_log" >"$out.tmp"
      elif [ ! -s "$out.tmp" ]; then
        printf 'none\n' >"$out.tmp"
      fi
      mv "$out.tmp" "$out"
    fi
    # The next video's browser starts a new log, so its file holds only its own lines.
    bare rm -f "$walk_log"
    [ -z "$gone" ] || exit "$rc"
    exit "$stopped"
    ;;
  fit)
    [ $# -eq 1 ] || die "$usage"
    dir="$1"
    load
    if [ "$BOX_OS" = macos ]; then echo "FIT not checked on macos"; exit 0; fi
    # The geometry goes in a variable first: eval of a failed command's empty
    # output succeeds, and an unset Y reads as 0, a window that seems to fit.
    measure='g=$(xdotool getactivewindow getwindowgeometry --shell) && eval "$g" && set -- $(xprop -root _NET_WORKAREA | sed "s/.*= //; s/,//g") && echo "$((Y + HEIGHT)) $(($2 + $4))"'
    pb keep show exec "$BOX_ID" -- sh -c "$measure"
    [ -z "$gone" ] || exit 125
    read -r bottom area <<<"$got" || true
    if [ "$rc" -ne 0 ] || ! [[ "${bottom:-}" =~ ^[0-9]+$ && "${area:-}" =~ ^[0-9]+$ ]]; then
      die "cannot measure the window: ${why:-no output}"
    fi
    if [ "$bottom" -le "$area" ]; then
      echo "FIT window bottom $bottom · screen bottom $area"
    else
      echo "TALL window bottom $bottom · screen bottom $area"; exit 3
    fi
    ;;
  gates)
    [ $# -ge 1 ] || die "$usage"
    dir="$1"; shift; local_wt=""; ci_wt=""; on_local=(); not_run=()
    # Both options leave to CI each Gate after -- that the PR's CI runs, read
    # from ci_wt.
    case "${1:-}" in
      --local) [ -d "${2:-}" ] || die "--local needs a worktree"; local_wt="$2"; ci_wt="$2"; shift 2 ;;
      --ci) [ -d "${2:-}" ] || die "--ci needs a worktree"; ci_wt="$2"; shift 2 ;;
    esac
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
    # covered[i] is the workflow file that runs that Gate on the PR, or
    # empty. An --on-local Gate always runs here: ci-covers does not follow
    # `needs:`, so a CI job it finds may still skip this PR, and nothing else
    # would run the Gate.
    covered=()
    if [ -n "$ci_wt" ] && [ $# -ge 1 ]; then
      cerr="$(mktemp)"
      cover_out="$(bash "$cover" "$ci_wt" -- "$@" 2>"$cerr")" || die "$(tail -n 1 "$cerr")"
      rm -f "$cerr"
      while IFS= read -r v; do
        v="${v%% · *}"
        case "$v" in "ci "*) covered+=("${v#ci }") ;; *) covered+=("") ;; esac
      done <<<"$cover_out"
    fi
    # With --ci, a call where CI runs every Gate needs no Sandbox.
    sandbox_gates=0; i=0
    for cmd in "$@"; do [ -n "${covered[$i]:-}" ] || sandbox_gates=1; i=$((i + 1)); done
    if [ -n "$local_wt" ]; then mode=local; work="$local_wt"
    else
      mode=sandbox; work="$ci_wt"
      if [ -z "$ci_wt" ] || [ "$sandbox_gates" -eq 1 ]; then
        command -v proofbox >/dev/null || die "proofbox is not installed"
        load; work="${ci_wt:-$BOX_WORK}"
      fi
    fi
    mkdir -p "$dir"
    tmpd="${TMPDIR:-/tmp}"; logs="$(mktemp -d "${tmpd%/}/box-gates.XXXXXX")"
    sha="$(git -C "$work" rev-parse --short HEAD)"
    # checks.txt is moved into place whole, so a stop leaves the old one.
    tmp="$dir/checks.txt.tmp"
    trap 'rm -f "$tmp"' EXIT
    : > "$tmp"
    n=0; red=0

    # gate <command> <local|sandbox>: run it there, write its line, and name
    # it on stderr when it is red.
    gate() {
      local cmd="$1" where last miss log
      n=$((n + 1)); log="$logs/$n.log"
      if [ "$2" = sandbox ]; then
        where="sandbox"; in_box "" "$log" sh -c "$cmd"
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
    pb null show delete "$BOX_ID"
    [ "$rc" -eq 0 ] || exit "$rc"
    rm -f "$dir/box.env"
    printf 'REMADE=%s\n' "$BOX_REMADE"
    ;;
  auth)
    [ $# -eq 1 ] || die "$usage"
    case "$1" in linux|macos) ;; *) die "os must be linux or macos, not $1" ;; esac
    conf="$HOME/.config/proofbox/config"; provider=""
    [ ! -f "$conf" ] || provider="$(sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([a-z]*\)\".*/\1/p" "$conf" | head -n 1)"
    provider="${provider:-namespace}"
    pb keep keep click --help
    grep -q -- '--mark' <<<"$got" || die "proofbox is too old: run proofbox update"
    command -v jq >/dev/null || die "jq is not installed: box.sh auth reads proofbox's login JSON with it"
    pb keep keep auth status --json
    [ "$rc" -eq 0 ] || die "proofbox auth status failed"
    item="$(jq -r --arg p "$provider" 'map(select(.provider == $p))[0] // empty | [.login, (.env // "")] | @tsv' <<<"$got")" \
      || die "proofbox auth status --json printed no JSON"
    [ -n "$item" ] || die "proofbox auth status has no line for $provider"
    IFS=$'\t' read -r login env <<<"$item"
    case "$login" in
      ok|not-needed) printf 'PROVIDER=%s\n' "$provider" ;;
      none|expired) die "log in first: proofbox auth login $provider" ;;
      rejected) die "$env is set, but $provider did not accept it" ;;
      *) die "proofbox auth status: $provider login is $login" ;;
    esac
    ;;
  *) die "$usage" ;;
esac
