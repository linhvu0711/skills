#!/usr/bin/env bash
# run.sh: runs every test case of the repo. It sources lib.sh, the helpers,
# the one fake gh, and the fake curl that every case shares, starts its own
# cases, then sources each test file in turn and starts that file's cases.
#
#   tests/run.sh
#
# Each case runs as a background job, one per CPU core at a time. It starts in
# an empty temp folder with set -e on and its own fake home, builds its own git
# repo in a temp folder, copies the repo's scripts/ folder in, and runs the command
# there. Each case's temp folders go when the case ends.
#
# Prints `ok <case>` or `FAIL <case>: <why>` per case, in case order, then
# `<p> passed, <f> failed`. Exit 1 when any case failed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$here/lib.sh"

# t_runner_keeps_cases_out_of_caller: from a caller repo with an origin, a
# run of its own (run_init, run_cases, run_wait) runs two broken cases. One
# fails, then would write a marker. One loses its cd behind `|| true`, then
# commits and pushes. Both report FAIL; the caller and its origin are
# unchanged and no marker exists.
t_runner_keeps_cases_out_of_caller() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q --bare "$T/origin.git"; git init -q "$T/caller"; cd "$T/caller"
  git config user.email t@example.invalid; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  git remote add origin "$T/origin.git"
  git commit -q --allow-empty -m init; git push -q origin HEAD:refs/heads/main
  local head; head="$(git rev-parse HEAD)"
  t_stops_at_error() { false; touch "$T/marker"; }
  t_lost_cd() { cd "$T/missing" 2>/dev/null || true; git commit -q --allow-empty -m lost; git push -q origin HEAD:refs/heads/lost; }
  cases=("stops|t_stops_at_error" "lost|t_lost_cd")
  # Called directly: `run` uses `||`, which turns set -e off for all it calls.
  { run_init; run_cases; run_wait; } >"$T/out" 2>&1
  eq failed 2 "$fail"
  eq marker no "$([ -e "$T/marker" ] && echo yes || echo no)"
  eq "caller HEAD" "$head" "$(git -C "$T/caller" rev-parse HEAD)"
  eq "origin branches" refs/heads/main "$(git -C "$T/origin.git" for-each-ref --format='%(refname)' refs/heads)"
}

# t_runner_removes_case_temp_folders: a run of its own runs one passing and
# one failing case, each making a temp folder and a temp file with a bare mktemp. None of
# the four is left after either case.
t_runner_removes_case_temp_folders() {
  # Given: a passing and a failing case that each note the temp paths they make
  T="$(cd "$(mktemp -d)" && pwd -P)"
  t_temp_pass() { mktemp -d >>"$T/made.pass"; mktemp >>"$T/made.pass"; }
  t_temp_fail() { mktemp -d >>"$T/made.fail"; mktemp >>"$T/made.fail"; false; }
  local -a cases=("pass|t_temp_pass" "fail|t_temp_fail")
  local p left=""
  # When
  { run_init; run_cases; run_wait; } >"$T/out" 2>&1
  # Then
  eq failed 1 "$fail"
  cat "$T/made.pass" "$T/made.fail" >"$T/made"
  while IFS= read -r p; do [ ! -e "$p" ] || left="$left $p"; done <"$T/made"
  eq "temp left" "" "$left"
}

cases=(
  "runner keeps a broken case out of the caller repo|t_runner_keeps_cases_out_of_caller"
  "runner removes each case's temp folders|t_runner_removes_case_temp_folders"
)

# run_init: a new run: an empty run folder, a pipe that holds one token per
# CPU core, and the counters. A case starts only when it takes a token, and
# its job gives the token back when the case ends, so at most one case per
# core runs at once. A pipe, not `wait -n`: macOS ships Bash 3.2, which has
# no `wait -n`.
run_init() {
  local n
  run_dir="$(mktemp -d)"; mkfifo "$run_dir/slots"; exec 9<>"$run_dir/slots"
  n="$(getconf _NPROCESSORS_ONLN)"
  while [ "$n" -gt 0 ]; do printf '\n' >&9; n=$((n - 1)); done
  names=(); started=0; printed=0; pass=0; fail=0
}

# run_cases: start each case of `cases` as a background job, in a subshell
# with set -e on, from a new empty temp folder that git finds no repo above,
# with its own fake home. The folder sits in a root that is the case's
# TMPDIR, with the mktemp wrapper first on PATH, and the root is removed when
# the case ends, pass or fail. The job keeps the case's output and exit code
# in the run folder; the exit code is written under a temp name and renamed,
# so run_print never reads half of it. Then print the cases that have ended.
run_cases() {
  local c fn
  for c in "${cases[@]}"; do
    fn="${c##*|}"; started=$((started + 1)); names[started]="${c%%|*}"
    read -r -u 9 _
    (
      root="$(mktemp -d)"
      set +e; ( set -e; export TMPDIR="$root" PATH="$case_bin:$PATH"; cd "$(mktemp -d)"; export GIT_CEILING_DIRECTORIES="$(dirname "$PWD")"; fake_home; "$fn" ) >"$run_dir/$started.log" 2>&1; rc=$?
      rm -rf "$root"
      printf '%s' "$rc" > "$run_dir/$started.rc.tmp"; mv "$run_dir/$started.rc.tmp" "$run_dir/$started.rc"
      printf '\n' >&9
    ) &
    run_print
  done
}

# run_print: print each ended case in case order, up to the first that still
# runs, as `ok <name>` or `FAIL <name>: <why>`, and add to pass and fail.
run_print() {
  local n
  while [ -e "$run_dir/$((printed + 1)).rc" ]; do
    n=$((printed + 1)); printed="$n"
    if [ "$(cat "$run_dir/$n.rc")" -eq 0 ]; then
      printf 'ok %s\n' "${names[n]}"; pass=$((pass + 1))
    else
      printf 'FAIL %s: %s\n' "${names[n]}" "$(tail -1 "$run_dir/$n.log")"; fail=$((fail + 1))
    fi
  done
}

# run_wait: wait for every case of the run, then print the rest. A case whose
# job ended with no exit code, as when its temp root could not be made, is a
# FAIL, so a run never passes with a case that did not run.
run_wait() {
  wait; run_print
  while [ "$printed" -lt "$started" ]; do
    printed=$((printed + 1))
    printf 'FAIL %s: no result\n' "${names[printed]}"; fail=$((fail + 1))
    run_print
  done
}

run_tmp="$(mktemp -d)"; case_bin="$run_tmp/case-bin"; mkdir -p "$case_bin"
# A case that links mktemp into a PATH of its own links this wrapper, so the
# wrapper names the real mktemp by its full path.
{ printf '#!/bin/sh\nreal='\''%s'\''\n' "$(command -v mktemp)"; cat <<'EOF'
# macOS mktemp ignores TMPDIR when it gets no template (man mktemp), so a
# case's temp files would land outside its root; -p puts them there.
for a in "$@"; do case "$a" in *XXX*) exec "$real" "$@" ;; esac; done
[ -n "${TMPDIR:-}" ] || exec "$real" "$@"
exec "$real" -p "$TMPDIR" "$@"
EOF
} > "$case_bin/mktemp"
chmod +x "$case_bin/mktemp"
# Each test file is sourced only after the jobs of the file before have
# started, and a job keeps the functions it started with, so a helper name in
# one file never replaces another file's.
run_init
trap 'rm -rf "$run_tmp" "$run_dir"' EXIT
run_cases
for f in "$here"/*/*.sh; do
  cases=(); . "$f"; run_cases
done
run_wait
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
