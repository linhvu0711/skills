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

# new_proofbox: the fake proofbox's `click --help` lists --mark, as a proofbox
# new enough for the walker's one-call steps does.
new_proofbox() { printf '  --mark text\n' > "$FAKE_PB/click.out"; }

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

t_box_down() {
  fake_proofbox
  state ns:us:abc
  box down "$P"
  eq exit 0 "$code"
  eq log "delete ns:us:abc" "$(cat "$FAKE_PB/log")"
  [ ! -e "$P/box.env" ] || eq box.env gone "still there"
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
  [ ! -e "$T/pwned" ] || eq "box.env as shell" "not run" ran
}

t_box_auth_config() {
  fake_proofbox
  new_proofbox
  mkdir -p "$HOME/.config/proofbox"
  echo '{ "linux": "docker", "macos": "namespace" }' > "$HOME/.config/proofbox/config"
  echo '[{"provider":"docker","login":"not-needed"},{"provider":"namespace","login":"none"}]' > "$FAKE_PB/auth.out"
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

t_box_gates_ci() {
  # Given
  special_fixture
  mkdir -p "$R/.github/workflows"
  printf '%s\n' 'on: pull_request' 'jobs:' '  t:' '    steps:' '      - run: pnpm lint' > "$R/.github/workflows/ci.yml"
  # When
  box gates "$P" --ci "$R" -- 'pnpm test' 'pnpm lint'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)
pnpm lint · $sha · not run: CI runs it (ci.yml)" "$(cat "$P/checks.txt")"
  eq execs 1 "$(grep -c '^exec ' "$FAKE_PB/log")"
}

# ci_only_fixture: no Sandbox up, and a workflow that runs pnpm test and pwd
# on pull requests.
ci_only_fixture() {
  fake_proofbox
  mkdir -p "$R/.github/workflows"
  printf '%s\n' 'on: pull_request' 'jobs:' '  t:' '    steps:' '      - run: pnpm test' '      - run: pwd' > "$R/.github/workflows/ci.yml"
  sha="$(git -C "$R" rev-parse --short HEAD)"
}

t_box_gates_ci_no_sandbox() {
  # Given
  ci_only_fixture
  # When
  box gates "$P" --ci "$R" -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · not run: CI runs it (ci.yml)" "$(cat "$P/checks.txt")"
  [ ! -e "$FAKE_PB/log" ] || eq "proofbox calls" "none" "$(cat "$FAKE_PB/log")"
}

t_box_gates_ci_no_proofbox() {
  # Given
  ci_only_fixture
  export PATH="/usr/bin:/bin"
  # When
  box gates "$P" --ci "$R" -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · not run: CI runs it (ci.yml)" "$(cat "$P/checks.txt")"
}

t_box_gates_ci_on_local() {
  # Given
  ci_only_fixture
  # When
  box gates "$P" --ci "$R" --on-local 'pwd' -- 'pnpm test'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · not run: CI runs it (ci.yml)
pwd · $sha · not run: CI runs it (ci.yml)" "$(cat "$P/checks.txt")"
}

t_box_gates_ci_up_all_ci() {
  # Given
  ci_only_fixture
  state ns:us:abc
  # When
  box gates "$P" --ci "$R" -- 'pnpm test' 'pwd'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · not run: CI runs it (ci.yml)
pwd · $sha · not run: CI runs it (ci.yml)" "$(cat "$P/checks.txt")"
  [ ! -e "$FAKE_PB/log" ] || eq "proofbox calls" "none" "$(cat "$FAKE_PB/log")"
}

t_box_gates_ci_no_ci() {
  # Given
  special_fixture
  # When
  box gates "$P" --ci "$R" -- 'pnpm test' 'pnpm lint'
  # Then
  eq exit 0 "$code"
  eq checks "pnpm test · $sha · 116 passed, 0 failed (sandbox)
pnpm lint · $sha · 116 passed, 0 failed (sandbox)" "$(cat "$P/checks.txt")"
  eq execs 2 "$(grep -c '^exec ' "$FAKE_PB/log")"
}

t_box_gates_ci_red() {
  # Given
  special_fixture
  echo 1 > "$FAKE_PB/exec.1.code"
  mkdir -p "$R/.github/workflows"
  printf '%s\n' 'on: pull_request' 'jobs:' '  t:' '    steps:' '      - run: pwd' > "$R/.github/workflows/ci.yml"
  # When
  box gates "$P" --ci "$R" -- 'pnpm test' 'pnpm lint' 'pwd'
  # Then
  eq exit 3 "$code"
  eq checks "pnpm test · $sha · red, exit 1: 116 passed, 0 failed (sandbox)
pnpm lint · $sha · 116 passed, 0 failed (sandbox)
pwd · $sha · not run: CI runs it (ci.yml)" "$(cat "$P/checks.txt")"
  has stderr "red: pnpm test · exit 1 · output " "$err"
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

t_box_start_no_answer_stops() {
  # Given: the app runs but never answers
  fake_proofbox
  fake_curl
  echo 7 > "$FAKE_CURL/GET_.exit"
  state ns:us:abc
  : > "$FAKE_PB/exec.2.run"; : > "$FAKE_PB/exec.3.run"; : > "$FAKE_PB/exec.4.run"
  group "$FAKE_PB/tmp/app.pid"
  # When
  box start "$P" --url http://localhost:3000/ -- pnpm dev
  # Then
  eq exit 1 "$code"
  ended "$gpid"
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
  # A group can take a moment to end after TERM, as on linux, so a wait of a
  # second or two is fine; the 30 s limit is not.
  [ "$(cat "$FAKE_PB/sleep.log" 2>/dev/null | wc -l)" -lt 30 ] || eq sleeps "under 30" "$(cat "$FAKE_PB/sleep.log" | wc -l)"
  case "$(cat "$FAKE_PB/log")" in *upload*) eq log "no upload" "$(cat "$FAKE_PB/log")" ;; esac
}

t_box_stop_gone_port_wait() {
  # Given: the app already ended, and the Sandbox dies during the port wait
  fake_proofbox
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"
  echo "Sandbox ns:us:abc is gone" > "$FAKE_PB/exec.2.fail"
  # When
  box stop "$P" --url http://localhost:3000/
  # Then
  eq exit 0 "$code"
  has stderr "Sandbox ns:us:abc is gone; nothing to stop" "$err"
}

t_box_open_starter() {
  # Given
  fake_proofbox
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"
  # When
  box open "$P" -- walk-browser http://localhost:3000/
  # Then
  eq exit 0 "$code"
  cmp -s "$here/../scripts/walk-browser.cjs" "$FAKE_PB/tmp/pb-walk/walk-browser" || eq starter "the lines of walk-browser.cjs" "$(head -n 3 "$FAKE_PB/tmp/pb-walk/walk-browser" 2>&1)"
  [ -x "$FAKE_PB/tmp/pb-walk/walk-browser" ] || eq "run bit" set none
  eq log 'exec ns:us:abc -- setsid -w sh -c sh -c "$1" >/dev/null 2>&1 & echo $$ >/tmp/walk-open.pid sh export PATH=/tmp/pb-walk:$PATH WALK_BROWSER_LOG=/tmp/walk-browser.log; walk-browser http://localhost:3000/' "$(tail -n 1 "$FAKE_PB/log")"
}

t_box_close_empty() {
  # Given
  fake_proofbox
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"; : > "$FAKE_PB/exec.2.run"; : > "$FAKE_PB/exec.3.run"
  mkdir -p "$FAKE_PB/tmp"
  : > "$FAKE_PB/tmp/walk-browser.log"
  # When
  box close "$P" --out "$P/video-1-browser.txt"
  # Then
  eq exit 0 "$code"
  eq file none "$(cat "$P/video-1-browser.txt")"
}

t_box_close_missing() {
  # Given
  fake_proofbox
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"; : > "$FAKE_PB/exec.2.run"; : > "$FAKE_PB/exec.3.run"
  mkdir -p "$FAKE_PB/tmp"
  # When
  box close "$P" --out "$P/video-1-browser.txt"
  # Then
  eq exit 0 "$code"
  eq file "missing: /tmp/walk-browser.log" "$(cat "$P/video-1-browser.txt")"
}

t_box_close_out() {
  # Given
  fake_proofbox
  state ns:us:abc
  : > "$FAKE_PB/exec.1.run"; : > "$FAKE_PB/exec.2.run"; : > "$FAKE_PB/exec.3.run"
  mkdir -p "$FAKE_PB/tmp"
  printf '%s\n' 'error: Uncaught TypeError: x is undefined · http://localhost:3000/' \
    'request: 500 http://localhost:3000/api/wishes' > "$FAKE_PB/tmp/walk-browser.log"
  # When
  box close "$P" --out "$P/video-1-browser.txt"
  # Then
  eq exit 0 "$code"
  eq file "error: Uncaught TypeError: x is undefined · http://localhost:3000/
request: 500 http://localhost:3000/api/wishes" "$(cat "$P/video-1-browser.txt")"
  [ ! -e "$FAKE_PB/tmp/walk-browser.log" ] || eq log gone "still there"
}

cases=(
  "gates runs an --on-local Gate on the local machine|t_box_gates_on_local"
  "gates writes a --not-run line|t_box_gates_not_run"
  "gates --local leaves a Gate CI runs to CI|t_box_gates_local_ci"
  "gates --ci leaves a Gate CI runs to CI and runs the rest in the Sandbox|t_box_gates_ci"
  "gates --ci needs no Sandbox when CI runs every Gate|t_box_gates_ci_no_sandbox"
  "gates --ci needs no proofbox when CI runs every Gate|t_box_gates_ci_no_proofbox"
  "box gates leaves an --on-local Gate CI runs to CI|t_box_gates_ci_on_local"
  "gates --ci runs no Gate in an up Sandbox when CI runs every Gate|t_box_gates_ci_up_all_ci"
  "gates --ci runs every Gate in the Sandbox when the repo has no CI|t_box_gates_ci_no_ci"
  "gates --ci keeps going after a red Gate in the Sandbox and exits 3|t_box_gates_ci_red"
  "gates --local runs each Gate in the worktree and writes checks.txt|t_box_gates_local"
  "gates --local needs no proofbox|t_box_gates_local_no_proofbox"
  "gates --local keeps going after a red Gate and names a missing tool|t_box_gates_local_red"
  "gates keeps going after a red Gate and exits 3|t_box_gates_red"
  "gates runs each Gate in order and writes checks.txt|t_box_gates_green"
  "up creates linux with idle 30m and no max life or provider|t_box_up_flags"
  "up creates macos with idle 10m|t_box_up_macos_idle"
  "run counts each Sandbox it makes again|t_box_run_counts_remakes"
  "down prints how many times the Sandbox was made again|t_box_down_prints_remakes"
  "up passes the setup script and the Secrets file from the repo's folder|t_box_up_secrets"
  "run uploads then execs and passes the exit code|t_box_run_passes_code"
  "run recreates a gone Sandbox once|t_box_run_recreates"
  "run recreates a Sandbox that exec finds gone|t_box_run_exec_gone"
  "run --from uploads that folder instead|t_box_run_from"
  "box.env is read as text, never run|t_box_state_not_run"
  "down deletes the Sandbox and clears the state|t_box_down"
  "up passes the repo's size|t_box_up_size"
  "up reuses the Sandbox already in the proof folder|t_box_up_reuses"
  "auth reads the Provider for the OS from proofbox's config|t_box_auth_config"
  "run notes the base after --from and the branch after a plain run|t_box_run_notes_tree"
  "up notes the branch|t_box_up_notes_branch"
  "start runs the Run line in its own group on linux and waits for the URL|t_box_start_linux"
  "start runs the Run line in its own group on macos|t_box_start_macos"
  "start --from starts the base and prints it|t_box_start_from_base"
  "start stops the app's group when the app does not answer|t_box_start_no_answer_stops"
  "stop ends the app's group and waits for a free port|t_box_stop"
  "stop on a Sandbox gone during the port wait has nothing to stop|t_box_stop_gone_port_wait"
  "open puts the browser starter on the command's PATH|t_box_open_starter"
  "close saves the browser log next to the video|t_box_close_out"
  "close writes none for an empty browser log|t_box_close_empty"
  "close names a missing browser log|t_box_close_missing"
)
