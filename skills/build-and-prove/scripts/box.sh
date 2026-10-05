#!/usr/bin/env bash
# box.sh: hold the one proofbox Sandbox of a build-and-prove run. The Mac
# edits; every command that runs the project's code runs in this Sandbox.
#
#   box.sh up <proof-dir> <worktree> <linux|macos> <owner/repo>
#   box.sh run <proof-dir> [--from <folder>] -- <command>...
#   box.sh down <proof-dir>
#
# up creates the Sandbox with the repo's setup script, and its env file when
# there is one, from ~/.agents/proofbox/<owner>-<repo>/: setup-<os>.sh and
# app.env. It passes no --provider, so ~/.config/proofbox/config picks it.
# The state goes in <proof-dir>/box.env as KEY=value lines: BOX_ID, BOX_OS,
# BOX_WORK, BOX_SETUP, BOX_ENV.
#
# run uploads the worktree's changed files, runs the command in the Sandbox,
# and exits with its code. --from uploads that folder instead, such as a copy
# of the base for before shots; the next run without it puts the worktree
# back. A Sandbox that is gone (idle, or past its max life) at the upload or
# the exec is made again once, from the same setup, and the command runs again.
#
# down deletes the Sandbox and the state.
#
# Exit 1: `stop: <why>` as the last stderr line.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

IDLE=30m
MAX_LIFE=6h

usage="usage: box.sh up <proof-dir> <worktree> <linux|macos> <owner/repo> | run <proof-dir> [--from <folder>] -- <command>... | down <proof-dir>"
verb="${1:-}"; [ $# -gt 0 ] && shift
command -v proofbox >/dev/null || die "proofbox is not installed"

# create: make a Sandbox from the BOX_* values and write the state.
create() {
  local args=(create --os "$BOX_OS" --work "$BOX_WORK" --setup "$BOX_SETUP") id errf
  [ -z "$BOX_ENV" ] || args+=(--env-file "$BOX_ENV")
  args+=(--idle "$IDLE" --max-life "$MAX_LIFE")
  errf="$(mktemp)"
  if ! id="$(proofbox "${args[@]}" 2>"$errf")"; then
    local why login
    why="$(tail -n 1 "$errf")"; rm -f "$errf"
    login="$(grep -o 'proofbox auth login [a-z]*' <<<"$why" || true)"
    [ -z "$login" ] || die "log in first: $login"
    die "${why:-proofbox create failed}"
  fi
  rm -f "$errf"
  BOX_ID="$(tail -n 1 <<<"$id")"
  printf 'BOX_ID=%s\nBOX_OS=%s\nBOX_WORK=%s\nBOX_SETUP=%s\nBOX_ENV=%s\n' \
    "$BOX_ID" "$BOX_OS" "$BOX_WORK" "$BOX_SETUP" "$BOX_ENV" > "$dir/box.env"
}

# load: read the state as text, the five keys only; the file never runs.
load() {
  [ -f "$dir/box.env" ] || die "no Sandbox for $dir; run box.sh up first"
  BOX_ID=""; BOX_OS=""; BOX_WORK=""; BOX_SETUP=""; BOX_ENV=""
  local k v
  while IFS='=' read -r k v; do
    case "$k" in
      BOX_ID) BOX_ID="$v" ;; BOX_OS) BOX_OS="$v" ;; BOX_WORK) BOX_WORK="$v" ;;
      BOX_SETUP) BOX_SETUP="$v" ;; BOX_ENV) BOX_ENV="$v" ;;
    esac
  done < "$dir/box.env"
}

# attempt <command>...: upload, then exec. Sets `gone` when proofbox says the
# Sandbox is gone, at either step; otherwise exits with the command's code.
# exec's stderr still reaches the caller live; a copy is kept to tell a gone
# Sandbox (125 and its line) from the command's own exit code.
attempt() {
  local errf c=0
  errf="$(mktemp)"
  gone=""
  proofbox upload "$BOX_ID" "${from:-$BOX_WORK}" >/dev/null 2>"$errf" || c=$?
  if [ "$c" -ne 0 ]; then
    if grep -q "Sandbox $BOX_ID is gone" "$errf"; then gone="$(tail -n 1 "$errf")"; rm -f "$errf"; return; fi
    cat "$errf" >&2; rm -f "$errf"; exit "$c"
  fi
  set +e
  { proofbox exec "$BOX_ID" -- "$@" 2>&1 1>&3 3>&- | tee "$errf" 1>&2; c=${PIPESTATUS[0]}; } 3>&1
  set -e
  if [ "$c" -eq 125 ] && grep -q "Sandbox $BOX_ID is gone" "$errf"; then gone="$(tail -n 1 "$errf")"; rm -f "$errf"; return; fi
  rm -f "$errf"
  exit "$c"
}

case "$verb" in
  up)
    [ $# -eq 4 ] || die "$usage"
    dir="$1"; BOX_WORK="$2"; BOX_OS="$3"; slug="${4/\//-}"
    case "$BOX_OS" in linux|macos) ;; *) die "os must be linux or macos, not $BOX_OS" ;; esac
    home="$HOME/.agents/proofbox/$slug"
    BOX_SETUP="$home/setup-$BOX_OS.sh"
    [ -f "$BOX_SETUP" ] || die "no setup script at $BOX_SETUP"
    BOX_ENV=""; [ ! -f "$home/app.env" ] || BOX_ENV="$home/app.env"
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
    attempt "$@"
    old="$gone"
    create
    attempt "$@"
    die "$old"
    ;;
  down)
    [ $# -eq 1 ] || die "$usage"
    dir="$1"
    load
    proofbox delete "$BOX_ID" >/dev/null
    rm -f "$dir/box.env"
    ;;
  *) die "$usage" ;;
esac
