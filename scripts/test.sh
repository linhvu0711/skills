#!/usr/bin/env bash
# test.sh: the tests for check.sh, the pre-commit hook, and adopt.sh.
#
#   test.sh
#
# Each case builds its own git repo in a temp folder, copies this scripts/
# folder in, and runs the command there. Every leak string below is joined
# from two halves at runtime, so this file holds nothing check.sh flags.
#
# Prints `ok <case>` or `FAIL <case>: <why>` per case, then
# `<p> passed, <f> failed`. Exit 1 when any case failed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
mac_home="/Us""ers/alice"
linux_home="/ho""me/bob"
email="alice""@""example.com"

# repo: a fresh repo in a temp folder with scripts/ committed; cd into it.
# Sets T (the temp folder) and R (the repo, a physical path).
repo() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; R="$T/repo"
  mkdir -p "$R"; cd "$R"
  git init -q
  git config user.email "t""@""example.invalid"; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  cp -R "$here" "$R/scripts"
  git add scripts; git commit -qm init
}

# run <cmd...>: run it, keep its exit code in `code`, stdout in `out`, stderr in `err`.
run() {
  code=0
  "$@" >"$T/out" 2>"$T/err" || code=$?
  out="$(cat "$T/out")"; err="$(cat "$T/err")"
}

eq() { [ "$2" = "$3" ] || { printf '%s: expected [%s], got [%s]\n' "$1" "$2" "$3" >&2; exit 1; }; }
has() { case "$3" in *"$2"*) ;; *) printf '%s: [%s] not in [%s]\n' "$1" "$2" "$3" >&2; exit 1 ;; esac; }

t_flags_home_path() {
  repo; printf 'hello\nsee %s/x\n' "$mac_home" > notes.md
  run bash scripts/check.sh notes.md
  eq exit 1 "$code"
  eq "stderr line 1" "notes.md:2: home path: $mac_home" "$(printf '%s\n' "$err" | sed -n 1p)"
  eq "last stderr line" "check: 1 problem(s) found" "$(printf '%s\n' "$err" | tail -1)"
}

t_flags_linux_home_path() {
  repo; printf 'cd %s\n' "$linux_home" > notes.md
  run bash scripts/check.sh notes.md
  eq exit 1 "$code"
  eq "stderr line 1" "notes.md:1: home path: $linux_home" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_passes_clean_file() {
  repo; printf 'see ~/development/x\n' > notes.md
  run bash scripts/check.sh notes.md
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

cases=(
  "flags a home path|t_flags_home_path"
  "flags a linux home path|t_flags_linux_home_path"
  "passes a clean file|t_passes_clean_file"
)

pass=0; fail=0
log="$(mktemp)"
for c in "${cases[@]}"; do
  name="${c%%|*}"; fn="${c##*|}"
  if ( "$fn" ) >"$log" 2>&1; then
    printf 'ok %s\n' "$name"; pass=$((pass + 1))
  else
    printf 'FAIL %s: %s\n' "$name" "$(tail -1 "$log")"; fail=$((fail + 1))
  fi
done
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
