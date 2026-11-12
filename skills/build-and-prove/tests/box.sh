# box.sh: the cases for this skill's Sandbox script, driven through a fake
# proofbox. The repo's test.sh sources this file after test-lib.sh and runs
# its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_proofbox: a fake proofbox first on PATH, a repo at R, HOME in the temp
# folder, and the setup script for acme/shop on linux in place. The fake logs
# each call as one line in $FAKE_PB/log and answers by verb from fixture files
# in $FAKE_PB: call n of a verb prints <verb>.<n>.fail or <verb>.fail to stderr
# and exits 125 when one exists, else prints <verb>.err to stderr when it
# exists, then <verb>.<n>.out or <verb>.out. `exec` then exits with the number
# in exec.<n>.code or exec.code, or 0. An exec.<n>.run file makes call n of
# `exec` run its command on this machine instead, each argument that starts
# with /tmp/ moved to $FAKE_PB/tmp/, as a Sandbox has its own /tmp, and exit
# with the command's code. A fake `sleep` on PATH logs its argument to
# $FAKE_PB/sleep.log and returns at once, so a wait runs to its limit fast.
fake_proofbox() {
  repo
  mkdir -p "$T/bin" "$T/pb" "$T/home/.agents/proofbox/acme-shop"
  cat > "$T/bin/proofbox" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
verb="$1"
n=$(( $(cat "$FAKE_PB/$verb.calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_PB/$verb.calls"
printf '%s\n' "$*" >> "$FAKE_PB/log"
for f in "$FAKE_PB/$verb.$n.fail" "$FAKE_PB/$verb.fail"; do
  if [ -f "$f" ]; then cat "$f" >&2; exit 125; fi
done
if [ "$verb" = exec ] && [ -f "$FAKE_PB/exec.$n.run" ]; then
  shift 3
  mkdir -p "$FAKE_PB/tmp"
  args=("${@/#\/tmp\//$FAKE_PB/tmp/}")
  c=0; "${args[@]}" || c=$?
  exit "$c"
fi
if [ -f "$FAKE_PB/$verb.err" ]; then cat "$FAKE_PB/$verb.err" >&2; fi
for f in "$FAKE_PB/$verb.$n.out" "$FAKE_PB/$verb.out"; do
  if [ -f "$f" ]; then cat "$f"; break; fi
done
if [ "$verb" = exec ]; then
  for f in "$FAKE_PB/exec.$n.code" "$FAKE_PB/exec.code"; do
    if [ -f "$f" ]; then exit "$(cat "$f")"; fi
  done
fi
exit 0
EOF
  chmod +x "$T/bin/proofbox"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$FAKE_PB/sleep.log"\n' > "$T/bin/sleep"
  chmod +x "$T/bin/sleep"
  export PATH="$T/bin:$PATH" FAKE_PB="$T/pb" HOME="$T/home"
  SETUP="$HOME/.agents/proofbox/acme-shop/setup-linux.sh"
  printf '#!/bin/sh\n' > "$SETUP"
  P="$T/proof"
}

box() { run bash "$here/../scripts/box.sh" "$@"; }

# state <id> [<remade>] [<size>] [<secrets>] [<os>]: an up Sandbox, without
# running up. The OS is linux unless named.
state() {
  mkdir -p "$P"
  printf 'BOX_ID=%s\nBOX_OS=%s\nBOX_WORK=%s\nBOX_SETUP=%s\nBOX_ENV=%s\nBOX_REMADE=%s\nBOX_SIZE=%s\n' "$1" "${5:-linux}" "$R" "$SETUP" "${4:-}" "${2:-0}" "${3:-}" > "$P/box.env"
}

# group <pid file> [term]: a process group on this machine, as the app or the
# browser is in the Sandbox, with its id in <pid file>; sets gpid. With
# `term`, the group ignores TERM, so only a KILL ends it. A case that fails
# before its stop still kills the group when it ends.
group() {
  mkdir -p "$(dirname "$1")"
  if [ "${2:-}" = term ]; then
    bash -c 'set -m; (trap "" TERM; exec /bin/sleep 300) >/dev/null 2>&1 & echo $! > "$1"' _ "$1"
  else
    bash -c 'set -m; /bin/sleep 300 >/dev/null 2>&1 & echo $! > "$1"' _ "$1"
  fi
  gpid="$(cat "$1")"
  trap 'kill -KILL "$gpid" 2>/dev/null || true' EXIT
}

# ended <pid>: the process ends within 2 s.
ended() {
  local i
  for i in $(seq 20); do kill -0 "$1" 2>/dev/null || return 0; /bin/sleep 0.1; done
  kill -KILL "$1" 2>/dev/null || true
  eq "process $1" ended "still running"
}

# line <n> <text>: line n of the text.
line() { printf '%s\n' "$2" | sed -n "$1p"; }

t_box_up_flags() {
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --idle 30m" "$(cat "$FAKE_PB/log")"
  has state "BOX_ID=ns:us:abc" "$(cat "$P/box.env")"
}

t_box_up_secrets() {
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  printf 'KEY=v\n' > "$HOME/.agents/proofbox/acme-shop/app.env"
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --secrets $HOME/.agents/proofbox/acme-shop/app.env --idle 30m" "$(cat "$FAKE_PB/log")"
}

t_box_up_reuses() {
  fake_proofbox
  state ns:us:abc
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  eq stdout "SANDBOX=ns:us:abc" "$out"
  [ ! -e "$FAKE_PB/log" ] || eq "proofbox calls" "none" "$(cat "$FAKE_PB/log")"
}

t_box_up_macos_idle() {
  fake_proofbox
  printf '#!/bin/sh\n' > "$HOME/.agents/proofbox/acme-shop/setup-macos.sh"
  echo ns:us:mac > "$FAKE_PB/create.out"
  box up "$P" "$R" macos acme/shop
  eq exit 0 "$code"
  has "create args" "--os macos" "$(cat "$FAKE_PB/log")"
  has "create args" "--idle 10m" "$(cat "$FAKE_PB/log")"
}

t_box_run_counts_remakes() {
  fake_proofbox
  state ns:us:abc 1
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 0 "$code"
  has state "BOX_REMADE=2" "$(cat "$P/box.env")"
  has stderr "Sandbox ns:us:abc is gone; made ns:us:def from its Snapshot" "$err"
}

t_box_down_prints_remakes() {
  fake_proofbox
  state ns:us:abc 2
  box down "$P"
  eq exit 0 "$code"
  eq stdout "REMADE=2" "$out"
}

t_box_run_passes_code() {
  fake_proofbox
  state ns:us:abc
  echo 3 > "$FAKE_PB/exec.code"
  box run "$P" -- pnpm test
  eq exit 3 "$code"
  eq log "upload ns:us:abc $R
exec ns:us:abc -- pnpm test" "$(cat "$FAKE_PB/log")"
}

t_box_run_recreates() {
  fake_proofbox
  state ns:us:abc
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 0 "$code"
  has state "BOX_ID=ns:us:def" "$(cat "$P/box.env")"
  eq creates 1 "$(grep -c '^create ' "$FAKE_PB/log")"
}

t_box_run_gone_twice() {
  fake_proofbox
  state ns:us:abc
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo "Sandbox ns:us:def is gone" > "$FAKE_PB/upload.2.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 1 "$code"
  has stderr "stop: Sandbox ns:us:abc is gone" "$err"
  eq creates 1 "$(grep -c '^create ' "$FAKE_PB/log")"
}

t_box_down() {
  fake_proofbox
  state ns:us:abc
  box down "$P"
  eq exit 0 "$code"
  eq log "delete ns:us:abc" "$(cat "$FAKE_PB/log")"
  [ ! -e "$P/box.env" ] || { echo "box.env still there" >&2; exit 1; }
}

t_box_no_proofbox() {
  repo
  mkdir -p "$T/home"
  export HOME="$T/home" PATH="/usr/bin:/bin"
  box up "$T/proof" "$R" linux acme/shop
  eq exit 1 "$code"
  has stderr "stop: proofbox is not installed" "$err"
}

t_box_create_fails() {
  fake_proofbox
  echo "Namespace refused the Sandbox: 4 of 4 in use; nothing was created. Delete a Sandbox or use a smaller --size" > "$FAKE_PB/create.fail"
  box up "$P" "$R" linux acme/shop
  eq exit 1 "$code"
  has stderr "stop: Namespace refused the Sandbox: 4 of 4 in use" "$err"
  [ ! -e "$P/box.env" ] || { echo "box.env written" >&2; exit 1; }
}

t_box_login() {
  fake_proofbox
  echo "Not logged in to namespace. Run: proofbox auth login namespace" > "$FAKE_PB/create.fail"
  box up "$P" "$R" linux acme/shop
  eq exit 1 "$code"
  has stderr "stop: log in first: proofbox auth login namespace" "$err"
}

t_box_up_setup_fails() {
  fake_proofbox
  printf '%s\n' "npm: command not found" "setup-linux.sh: line 4: pnpm: command not found" \
    "Setup script failed with exit code 127; its last 50 lines are above. Fix the script and create again. This Sandbox was deleted." > "$FAKE_PB/create.fail"
  box up "$P" "$R" linux acme/shop
  eq exit 1 "$code"
  eq stderr "npm: command not found
setup-linux.sh: line 4: pnpm: command not found
Setup script failed with exit code 127; its last 50 lines are above. Fix the script and create again. This Sandbox was deleted.
stop: Setup script failed with exit code 127; its last 50 lines are above. Fix the script and create again. This Sandbox was deleted." "$err"
}

t_box_up_snapshot_reused() {
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  printf '%s\n' "proofbox: uploading the work folder" "proofbox: Snapshot reused, Fingerprint 3f9a2c71" > "$FAKE_PB/create.err"
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  has stderr "proofbox: Snapshot reused, Fingerprint 3f9a2c71" "$err"
  eq stdout "SANDBOX=ns:us:abc" "$out"
}

t_box_up_login_last() {
  fake_proofbox
  echo "Not logged in to namespace. Run: proofbox auth login namespace" > "$FAKE_PB/create.fail"
  box up "$P" "$R" linux acme/shop
  eq exit 1 "$code"
  eq stderr "Not logged in to namespace. Run: proofbox auth login namespace
stop: log in first: proofbox auth login namespace" "$err"
}

t_box_up_size() {
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  echo 8x16 > "$HOME/.agents/proofbox/acme-shop/size"
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --size 8x16 --idle 30m" "$(cat "$FAKE_PB/log")"
  has state "BOX_SIZE=8x16" "$(cat "$P/box.env")"
}

t_box_run_remake_size() {
  fake_proofbox
  state ns:us:abc 0 8x16
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --size 8x16 --idle 30m" "$(grep '^create ' "$FAKE_PB/log")"
  has state "BOX_SIZE=8x16" "$(cat "$P/box.env")"
}

t_box_run_remake_no_size() {
  fake_proofbox
  state ns:us:abc
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --idle 30m" "$(grep '^create ' "$FAKE_PB/log")"
}

t_box_run_remake_secrets() {
  fake_proofbox
  state ns:us:abc 0 "" "$HOME/.agents/proofbox/acme-shop/app.env"
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --secrets $HOME/.agents/proofbox/acme-shop/app.env --idle 30m" "$(grep '^create ' "$FAKE_PB/log")"
}

t_box_up_size_not_offered() {
  fake_proofbox
  echo 3x3 > "$HOME/.agents/proofbox/acme-shop/size"
  echo "Provider namespace does not offer the size 3x3; use one of: 4x8, 8x16" > "$FAKE_PB/create.fail"
  box up "$P" "$R" linux acme/shop
  eq exit 1 "$code"
  eq "last stderr line" "stop: Provider namespace does not offer the size 3x3; use one of: 4x8, 8x16" "$(printf '%s\n' "$err" | tail -n 1)"
  [ ! -e "$P/box.env" ] || { echo "box.env written" >&2; exit 1; }
  eq log "create --os linux --work $R --setup $SETUP --size 3x3 --idle 30m" "$(cat "$FAKE_PB/log")"
}

t_box_run_exec_gone() {
  fake_proofbox
  state ns:us:abc
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/exec.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  box run "$P" -- pnpm test
  eq exit 0 "$code"
  has state "BOX_ID=ns:us:def" "$(cat "$P/box.env")"
  eq creates 1 "$(grep -c '^create ' "$FAKE_PB/log")"
}

t_box_run_from() {
  fake_proofbox
  state ns:us:abc
  mkdir -p "$T/base"
  box run "$P" --from "$T/base" -- sh -c 'npm start &'
  eq exit 0 "$code"
  eq log "upload ns:us:abc $T/base
exec ns:us:abc -- sh -c npm start &" "$(cat "$FAKE_PB/log")"
}

t_box_state_not_run() {
  fake_proofbox
  mkdir -p "$P"
  printf 'BOX_ID=$(touch %s/pwned)\nBOX_OS=linux\n' "$T" > "$P/box.env"
  box down "$P"
  eq exit 0 "$code"
  eq log 'delete $(touch '"$T"'/pwned)' "$(cat "$FAKE_PB/log")"
  [ ! -e "$T/pwned" ] || { echo "box.env ran as shell" >&2; exit 1; }
}

t_box_auth_not_logged_in() {
  fake_proofbox
  printf 'docker  no login needed\nnamespace  not logged in\n' > "$FAKE_PB/auth.out"
  box auth linux
  eq exit 1 "$code"
  has stderr "stop: log in first: proofbox auth login namespace" "$err"
}

t_box_auth_expired() {
  fake_proofbox
  echo "namespace  expired 2026-10-01T00:00:00Z. Run: proofbox auth login namespace" > "$FAKE_PB/auth.out"
  box auth macos
  eq exit 1 "$code"
  has stderr "stop: log in first: proofbox auth login namespace" "$err"
}

t_box_auth_rejected() {
  fake_proofbox
  echo "namespace  PROOFBOX_NAMESPACE_TOKEN is set, but namespace did not accept it" > "$FAKE_PB/auth.out"
  box auth linux
  eq exit 1 "$code"
  has stderr "stop: PROOFBOX_NAMESPACE_TOKEN is set, but namespace did not accept it" "$err"
}

t_box_auth_ok() {
  fake_proofbox
  echo "namespace  logged in as Personal, region us, expires 2026-10-31T02:02:57Z, saved login" > "$FAKE_PB/auth.out"
  box auth linux
  eq exit 0 "$code"
  eq stdout "PROVIDER=namespace" "$out"
}

t_box_auth_config() {
  fake_proofbox
  mkdir -p "$HOME/.config/proofbox"
  echo '{ "linux": "docker", "macos": "namespace" }' > "$HOME/.config/proofbox/config"
  printf 'docker  no login needed\nnamespace  not logged in\n' > "$FAKE_PB/auth.out"
  box auth linux
  eq exit 0 "$code"
  eq stdout "PROVIDER=docker" "$out"
}

# gate_fixture: an up Sandbox, an old checks.txt, and two Gate outputs; sets
# sha to the fixture repo's short HEAD.
gate_fixture() {
  fake_proofbox
  state ns:us:abc
  echo 'old · 0000000 · 1 pass (sandbox)' > "$P/checks.txt"
  printf 'ok a\n116 passed, 0 failed\n' > "$FAKE_PB/exec.1.out"
  printf 'lint ok\n\n\n' > "$FAKE_PB/exec.2.out"
  sha="$(git -C "$R" rev-parse --short HEAD)"
}

t_box_gates_green() {
  # Given
  gate_fixture
  # When
  box gates "$P" -- 'pnpm test' 'pnpm lint'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)
pnpm lint · $sha · lint ok (sandbox)" "$(cat "$P/checks.txt")"
  eq log "upload ns:us:abc $R
exec ns:us:abc -- sh -c pnpm test
upload ns:us:abc $R
exec ns:us:abc -- sh -c pnpm lint" "$(cat "$FAKE_PB/log")"
}

t_box_gates_remakes() {
  # Given
  gate_fixture
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  # When
  box gates "$P" -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  has state "BOX_ID=ns:us:def" "$(cat "$P/box.env")"
  eq creates 1 "$(grep -c '^create ' "$FAKE_PB/log")"
  has stderr "Sandbox ns:us:abc is gone; made ns:us:def from its Snapshot" "$err"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)" "$(cat "$P/checks.txt")"
}

t_box_gates_gone_twice() {
  # Given
  gate_fixture
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/upload.1.fail"
  echo "Sandbox ns:us:def is gone" > "$FAKE_PB/upload.2.fail"
  echo ns:us:def > "$FAKE_PB/create.out"
  # When
  box gates "$P" -- 'pnpm test'
  # Then
  eq exit 1 "$code"
  has stderr "stop: Sandbox ns:us:abc is gone" "$err"
  eq checks "old · 0000000 · 1 pass (sandbox)" "$(cat "$P/checks.txt")"
  [ ! -e "$P/checks.txt.tmp" ] || { echo "checks.txt.tmp left" >&2; exit 1; }
}

t_box_gates_usage() {
  # Given
  gate_fixture
  # When
  box gates "$P" --
  # Then
  eq exit 1 "$code"
  has stderr "gates <proof-dir> [--local <worktree>] [--on-local <command>]... [--not-run <command> <why>]... -- <command>..." "$err"
  eq checks "old · 0000000 · 1 pass (sandbox)" "$(cat "$P/checks.txt")"
  [ ! -e "$FAKE_PB/log" ] || eq "proofbox calls" "none" "$(cat "$FAKE_PB/log")"
}

t_box_gates_red() {
  # Given
  fake_proofbox
  state ns:us:abc
  echo 1 > "$FAKE_PB/exec.1.code"
  printf 'FAIL a\n1 passed, 1 failed\n' > "$FAKE_PB/exec.1.out"
  echo 'lint ok' > "$FAKE_PB/exec.2.out"
  echo built > "$FAKE_PB/exec.3.out"
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" -- 'pnpm test' 'pnpm lint' 'make build'
  # Then
  eq exit 3 "$code"
  eq execs 3 "$(grep -c '^exec ' "$FAKE_PB/log")"
  eq checks "pnpm test · $sha · red, exit 1: 1 passed, 1 failed (sandbox)
pnpm lint · $sha · lint ok (sandbox)
make build · $sha · built (sandbox)" "$(cat "$P/checks.txt")"
  has stderr "red: pnpm test · exit 1 · output " "$err"
  f="$(printf '%s\n' "$err" | sed -n 's/^red: pnpm test · exit 1 · output //p')"
  [ -f "$f" ] || eq "output file" "a file" "$f"
  case "$f" in "$P"*) eq "output file" "outside $P" "$f" ;; esac
  has output "FAIL a" "$(cat "$f")"
  case "$err" in *"red: pnpm lint"*) eq stderr "no red line for pnpm lint" "$err" ;; esac
}

t_box_gates_own_code() {
  # Given
  fake_proofbox
  state ns:us:abc
  echo 3 > "$FAKE_PB/exec.code"
  printf '2 failed\n\n\n\n' > "$FAKE_PB/exec.out"
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" -- 'pnpm test | tail -n 5'
  # Then
  eq exit 3 "$code"
  eq checks "pnpm test | tail -n 5 · $sha · red, exit 3: 2 failed (sandbox)" "$(cat "$P/checks.txt")"
  has log "exec ns:us:abc -- sh -c pnpm test | tail -n 5" "$(cat "$FAKE_PB/log")"
}

t_box_gates_missing_tool() {
  # Given
  fake_proofbox
  state ns:us:abc
  echo 127 > "$FAKE_PB/exec.code"
  echo 'sh: 1: pnpm: not found' > "$FAKE_PB/exec.out"
  # When
  box gates "$P" -- 'pnpm test'
  # Then
  eq exit 3 "$code"
  has stderr "missing tool: pnpm test · sh: 1: pnpm: not found" "$err"
}

t_box_gates_not_found_line() {
  # Given
  fake_proofbox
  state ns:us:abc
  echo 1 > "$FAKE_PB/exec.code"
  echo 'docker: command not found' > "$FAKE_PB/exec.out"
  # When
  box gates "$P" -- 'pnpm test:docker'
  # Then
  eq exit 3 "$code"
  has stderr "missing tool: pnpm test:docker · docker: command not found" "$err"
}

t_box_gates_local() {
  # Given
  fake_proofbox
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" --local "$R" -- 'echo one' 'pwd'
  # Then
  eq exit 0 "$code"
  eq checks "echo one · $sha · one (local machine)
pwd · $sha · $R (local machine)" "$(cat "$P/checks.txt")"
  eq log "" "$(cat "$FAKE_PB/log" 2>/dev/null)"
}

t_box_gates_local_no_proofbox() {
  # Given
  repo
  export PATH="/usr/bin:/bin"
  P="$T/proof"
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" --local "$R" -- 'echo one'
  # Then
  eq exit 0 "$code"
  eq checks "echo one · $sha · one (local machine)" "$(cat "$P/checks.txt")"
}

t_box_gates_local_red() {
  # Given
  fake_proofbox
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" --local "$R" -- 'echo bad; exit 3' 'no-such-tool-xyz' 'echo ok'
  # Then
  eq exit 3 "$code"
  eq first "echo bad; exit 3 · $sha · red, exit 3: bad (local machine)" "$(sed -n 1p "$P/checks.txt")"
  has second "no-such-tool-xyz · $sha · red, exit 127: " "$(sed -n 2p "$P/checks.txt")"
  eq third "echo ok · $sha · ok (local machine)" "$(sed -n 3p "$P/checks.txt")"
  has stderr "red: echo bad; exit 3 · exit 3 · output " "$err"
  has stderr "missing tool: no-such-tool-xyz · " "$err"
}

t_box_gates_local_ci() {
  # Given
  fake_proofbox
  mkdir -p "$R/.github/workflows"
  printf '%s\n' 'on: pull_request' 'jobs:' '  t:' '    steps:' '      - run: echo one' > "$R/.github/workflows/ci.yml"
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" --local "$R" -- 'echo one' 'echo two'
  # Then
  eq exit 0 "$code"
  eq checks "echo one · $sha · not run: CI runs it (ci.yml)
echo two · $sha · two (local machine)" "$(cat "$P/checks.txt")"
}

# special_fixture: an up Sandbox whose every exec prints a green test line.
special_fixture() {
  fake_proofbox
  state ns:us:abc
  echo '116 passed, 0 failed' > "$FAKE_PB/exec.out"
  sha="$(git -C "$R" rev-parse --short HEAD)"
}

t_box_gates_on_local() {
  # Given
  special_fixture
  # When
  box gates "$P" --on-local 'pwd' -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)
pwd · $sha · $R (local machine)" "$(cat "$P/checks.txt")"
  eq execs 1 "$(grep -c '^exec ' "$FAKE_PB/log")"
}

t_box_gates_not_run() {
  # Given
  special_fixture
  # When
  box gates "$P" --not-run 'pnpm test:docker' 'no Docker on either machine' -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)
pnpm test:docker · $sha · not run: no Docker on either machine" "$(cat "$P/checks.txt")"
}

t_box_gates_rewrites_all() {
  # Given
  special_fixture
  # When
  box gates "$P" --on-local 'pwd' --not-run 'pnpm test:docker' 'no Docker' -- 'pnpm test'
  box gates "$P" --on-local 'pwd' --not-run 'pnpm test:docker' 'no Docker' -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)
pwd · $sha · $R (local machine)
pnpm test:docker · $sha · not run: no Docker" "$(cat "$P/checks.txt")"
}

t_box_gates_on_local_with_local() {
  # Given
  gate_fixture
  # When
  box gates "$P" --local "$R" --on-local 'pwd' -- 'echo one'
  # Then
  eq exit 1 "$code"
  has stderr "stop: --on-local runs a Gate the Sandbox cannot; with --local every Gate runs on the local machine" "$err"
  eq checks "old · 0000000 · 1 pass (sandbox)" "$(cat "$P/checks.txt")"
}

t_box_gates_local_only_not_run() {
  # Given
  fake_proofbox
  sha="$(git -C "$R" rev-parse --short HEAD)"
  # When
  box gates "$P" --local "$R" --not-run 'pnpm test:docker' 'no Docker here' --
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test:docker · $sha · not run: no Docker here" "$(cat "$P/checks.txt")"
}

t_box_gates_upload_fails() {
  # Given
  gate_fixture
  echo 'upload: connection refused' > "$FAKE_PB/upload.fail"
  # When
  box gates "$P" -- 'pnpm test'
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: upload: connection refused" "$(printf '%s\n' "$err" | tail -n 1)"
  eq checks "old · 0000000 · 1 pass (sandbox)" "$(cat "$P/checks.txt")"
}

t_box_run_notes_tree() {
  # Given
  fake_proofbox
  state ns:us:abc
  mkdir -p "$T/base"
  # When
  box run "$P" --from "$T/base" -- true
  # Then
  eq "exit after --from" 0 "$code"
  has "state after --from" "BOX_TREE=base" "$(cat "$P/box.env")"
  # When
  box run "$P" -- true
  # Then
  eq exit 0 "$code"
  has state "BOX_TREE=branch" "$(cat "$P/box.env")"
  case "$(cat "$P/box.env")" in *BOX_TREE=base*) eq state "no BOX_TREE=base" "$(cat "$P/box.env")" ;; esac
}

t_box_up_notes_branch() {
  # Given
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  # When
  box up "$P" "$R" linux acme/shop
  # Then
  eq exit 0 "$code"
  has state "BOX_TREE=branch" "$(cat "$P/box.env")"
}

t_box_start_linux() {
  # Given
  fake_proofbox
  fake_curl
  echo '{}' > "$FAKE_CURL/GET_.json"
  state ns:us:abc
  : > "$FAKE_PB/exec.2.run"
  # When
  box start "$P" --url http://localhost:3000/ -- pnpm dev
  # Then
  eq exit 0 "$code"
  eq stdout "TREE=branch" "$out"
  eq "log line 1" "upload ns:us:abc $R" "$(line 1 "$(cat "$FAKE_PB/log")")"
  eq "log line 2" 'exec ns:us:abc -- setsid -w sh -c sh -c "$1" >/tmp/app.log 2>&1 & echo $$ >/tmp/app.pid sh pnpm dev' "$(line 2 "$(cat "$FAKE_PB/log")")"
  has "log line 3" 'exec ns:us:abc -- sh -c for i in $(seq 60)' "$(line 3 "$(cat "$FAKE_PB/log")")"
  eq "curl calls" "GET /" "$(cat "$FAKE_CURL/calls")"
  [ ! -e "$FAKE_PB/sleep.log" ] || eq sleeps none "$(cat "$FAKE_PB/sleep.log")"
}

t_box_start_macos() {
  # Given
  fake_proofbox
  state ns:us:abc 0 "" "" macos
  # When
  box start "$P" -- pnpm dev
  # Then
  eq exit 0 "$code"
  eq log "upload ns:us:abc $R"'
exec ns:us:abc -- sh -c set -m; sh -c "$1" >/tmp/app.log 2>&1 & echo $! >/tmp/app.pid sh pnpm dev' "$(cat "$FAKE_PB/log")"
}

t_box_start_from_base() {
  # Given
  fake_proofbox
  state ns:us:abc
  mkdir -p "$T/base"
  # When
  box start "$P" --from "$T/base" -- pnpm dev
  # Then
  eq exit 0 "$code"
  eq stdout "TREE=base" "$out"
  eq "log line 1" "upload ns:us:abc $T/base" "$(line 1 "$(cat "$FAKE_PB/log")")"
  has state "BOX_TREE=base" "$(cat "$P/box.env")"
}

t_box_start_no_answer() {
  # Given
  fake_proofbox
  fake_curl
  echo 7 > "$FAKE_CURL/GET_.exit"
  state ns:us:abc
  : > "$FAKE_PB/exec.2.run"; : > "$FAKE_PB/exec.3.run"
  mkdir -p "$FAKE_PB/tmp"
  echo "Error: Cannot find module 'vite'" > "$FAKE_PB/tmp/app.log"
  # When
  box start "$P" --url http://localhost:3000/ -- pnpm dev
  # Then
  eq exit 1 "$code"
  eq sleeps "$(printf '2\n%.0s' $(seq 60))" "$(cat "$FAKE_PB/sleep.log")"
  has stderr "Error: Cannot find module 'vite'" "$err"
  eq "last stderr line" "stop: http://localhost:3000/ did not answer in 120 s; the app log's last lines are above" "$(printf '%s\n' "$err" | tail -n 1)"
}

t_box_stop() {
  # Given
  fake_proofbox
  fake_curl
  echo 7 > "$FAKE_CURL/GET_.exit"
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"; : > "$FAKE_PB/exec.2.run"
  group "$FAKE_PB/tmp/app.pid"
  # When
  box stop "$P" --url http://localhost:3000/
  # Then
  eq exit 0 "$code"
  ended "$gpid"
  [ ! -e "$FAKE_PB/sleep.log" ] || eq sleeps none "$(cat "$FAKE_PB/sleep.log")"
  case "$(cat "$FAKE_PB/log")" in *upload*) eq log "no upload" "$(cat "$FAKE_PB/log")" ;; esac
}

t_box_stop_limit() {
  # Given
  fake_proofbox
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"
  group "$FAKE_PB/tmp/app.pid" term
  # When
  box stop "$P"
  # Then
  eq exit 0 "$code"
  eq sleeps "$(printf '1\n%.0s' $(seq 30))" "$(cat "$FAKE_PB/sleep.log")"
  ended "$gpid"
}

t_box_stop_port_busy() {
  # Given
  fake_proofbox
  fake_curl
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"; : > "$FAKE_PB/exec.2.run"
  group "$FAKE_PB/tmp/app.pid"
  # When
  box stop "$P" --url http://localhost:3000/
  # Then
  eq exit 1 "$code"
  eq sleeps "$(printf '1\n%.0s' $(seq 30))" "$(cat "$FAKE_PB/sleep.log")"
  # The fake curl prints its status code, as a real `curl -o /dev/null` does not.
  eq "last stderr line" "stop: http://localhost:3000/ still answers after the app stopped" "$(printf '%s\n' "$err" | tail -n 1 | sed 's/^\(404\)*//')"
}

t_box_stop_gone() {
  # Given
  fake_proofbox
  state ns:us:abc
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/exec.1.fail"
  # When
  box stop "$P" --url http://localhost:3000/
  # Then
  eq exit 0 "$code"
  has stderr "Sandbox ns:us:abc is gone; nothing to stop" "$err"
  eq log 'exec ns:us:abc -- sh -c g=$(cat "$1" 2>/dev/null) || exit 0; kill -TERM -"$g" 2>/dev/null; i=0; while kill -0 -"$g" 2>/dev/null && [ $i -lt "$2" ]; do i=$((i+1)); sleep 1; done; kill -KILL -"$g" 2>/dev/null; true sh /tmp/app.pid 30' "$(cat "$FAKE_PB/log")"
}

cases=(
  "gates stops with exit 1 when the upload fails|t_box_gates_upload_fails"
  "gates runs an --on-local Gate on the local machine|t_box_gates_on_local"
  "gates writes a --not-run line|t_box_gates_not_run"
  "gates writes every line again on a second call|t_box_gates_rewrites_all"
  "gates refuses --on-local with --local|t_box_gates_on_local_with_local"
  "gates --local writes a --not-run line with no Gate to run|t_box_gates_local_only_not_run"
  "gates --local leaves a Gate CI runs to CI|t_box_gates_local_ci"
  "gates --local runs each Gate in the worktree and writes checks.txt|t_box_gates_local"
  "gates --local needs no proofbox|t_box_gates_local_no_proofbox"
  "gates --local keeps going after a red Gate and names a missing tool|t_box_gates_local_red"
  "gates names a Gate whose tool is missing|t_box_gates_missing_tool"
  "gates names a not found line|t_box_gates_not_found_line"
  "gates keeps going after a red Gate and exits 3|t_box_gates_red"
  "gates keeps the Gate's own exit code|t_box_gates_own_code"
  "gates runs each Gate in order and writes checks.txt|t_box_gates_green"
  "gates makes a gone Sandbox again once|t_box_gates_remakes"
  "gates stops when the new Sandbox is gone too|t_box_gates_gone_twice"
  "gates with no command is a usage error|t_box_gates_usage"
  "up creates linux with idle 30m and no max life or provider|t_box_up_flags"
  "up creates macos with idle 10m|t_box_up_macos_idle"
  "run counts each Sandbox it makes again|t_box_run_counts_remakes"
  "down prints how many times the Sandbox was made again|t_box_down_prints_remakes"
  "up passes the setup script and the Secrets file from the repo's folder|t_box_up_secrets"
  "run uploads then execs and passes the exit code|t_box_run_passes_code"
  "run recreates a gone Sandbox once|t_box_run_recreates"
  "run stops when the new Sandbox is gone too|t_box_run_gone_twice"
  "run recreates a Sandbox that exec finds gone|t_box_run_exec_gone"
  "run --from uploads that folder instead|t_box_run_from"
  "box.env is read as text, never run|t_box_state_not_run"
  "down deletes the Sandbox and clears the state|t_box_down"
  "up stops when proofbox is missing|t_box_no_proofbox"
  "up stops with proofbox's line when create fails|t_box_create_fails"
  "up names the login command when the login is missing|t_box_login"
  "up shows the setup script's lines, then the stop line|t_box_up_setup_fails"
  "up shows the Snapshot line and prints only the id on stdout|t_box_up_snapshot_reused"
  "up ends with the login stop line after proofbox's line|t_box_up_login_last"
  "up passes the repo's size|t_box_up_size"
  "run makes the Sandbox again at the same size|t_box_run_remake_size"
  "run makes the Sandbox again with no size when the state has none|t_box_run_remake_no_size"
  "run makes the Sandbox again with the Secrets file|t_box_run_remake_secrets"
  "up stops with proofbox's line on a size it does not offer|t_box_up_size_not_offered"
  "up reuses the Sandbox already in the proof folder|t_box_up_reuses"
  "auth stops with the login command when not logged in|t_box_auth_not_logged_in"
  "auth stops with the login command when the login expired|t_box_auth_expired"
  "auth stops when an env token is not accepted|t_box_auth_rejected"
  "auth passes a logged-in Provider|t_box_auth_ok"
  "auth reads the Provider for the OS from proofbox's config|t_box_auth_config"
  "run notes the base after --from and the branch after a plain run|t_box_run_notes_tree"
  "up notes the branch|t_box_up_notes_branch"
  "start runs the Run line in its own group on linux and waits for the URL|t_box_start_linux"
  "start runs the Run line in its own group on macos|t_box_start_macos"
  "start --from starts the base and prints it|t_box_start_from_base"
  "start stops with the log's last lines when the app does not answer|t_box_start_no_answer"
  "stop ends the app's group and waits for a free port|t_box_stop"
  "stop waits 30 s for the group, then kills it|t_box_stop_limit"
  "stop fails when the port stays busy|t_box_stop_port_busy"
  "stop on a gone Sandbox has nothing to stop|t_box_stop_gone"
)
