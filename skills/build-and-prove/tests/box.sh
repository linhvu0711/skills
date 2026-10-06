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
# in exec.code, or 0.
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
if [ -f "$FAKE_PB/$verb.err" ]; then cat "$FAKE_PB/$verb.err" >&2; fi
for f in "$FAKE_PB/$verb.$n.out" "$FAKE_PB/$verb.out"; do
  if [ -f "$f" ]; then cat "$f"; break; fi
done
[ "$verb" = exec ] && exit "$(cat "$FAKE_PB/exec.code" 2>/dev/null || echo 0)"
exit 0
EOF
  chmod +x "$T/bin/proofbox"
  export PATH="$T/bin:$PATH" FAKE_PB="$T/pb" HOME="$T/home"
  SETUP="$HOME/.agents/proofbox/acme-shop/setup-linux.sh"
  printf '#!/bin/sh\n' > "$SETUP"
  P="$T/proof"
}

box() { run bash "$here/../scripts/box.sh" "$@"; }

# state: an up Sandbox, without running up.
state() {
  mkdir -p "$P"
  printf 'BOX_ID=%s\nBOX_OS=linux\nBOX_WORK=%s\nBOX_SETUP=%s\nBOX_ENV=\nBOX_REMADE=%s\n' "$1" "$R" "$SETUP" "${2:-0}" > "$P/box.env"
}

t_box_up_flags() {
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  eq "create args" "create --os linux --work $R --setup $SETUP --idle 30m" "$(cat "$FAKE_PB/log")"
  has state "BOX_ID=ns:us:abc" "$(cat "$P/box.env")"
}

t_box_up_env_file() {
  fake_proofbox
  echo ns:us:abc > "$FAKE_PB/create.out"
  printf 'KEY=v\n' > "$HOME/.agents/proofbox/acme-shop/app.env"
  box up "$P" "$R" linux acme/shop
  eq exit 0 "$code"
  has "create args" "--setup $SETUP --env-file $HOME/.agents/proofbox/acme-shop/app.env" "$(cat "$FAKE_PB/log")"
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

cases=(
  "up creates linux with idle 30m and no max life or provider|t_box_up_flags"
  "up creates macos with idle 10m|t_box_up_macos_idle"
  "run counts each Sandbox it makes again|t_box_run_counts_remakes"
  "down prints how many times the Sandbox was made again|t_box_down_prints_remakes"
  "up passes the setup and env files from the repo's folder|t_box_up_env_file"
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
)
