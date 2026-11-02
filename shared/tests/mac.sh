# mac.sh: the cases for the shared Namespace Mac script, shared/cursor/mac.sh, driven through a
# fake nsc and the fake gh of test-lib.sh. The repo's test.sh sources this
# file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_nsc: a fake nsc first on PATH, beside the fake gh. Call n logs its
# args to $FAKE_NSC/calls and its stdin to $FAKE_NSC/stdin.<n>; `create`
# writes mac-1 to its --cidfile; a call prints $FAKE_NSC/<n>.out and exits
# with $FAKE_NSC/<n>.exit when those files exist.
fake_nsc() {
  fake_gh
  mkdir -p "$T/nsc"
  cat > "$T/bin/nsc" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_NSC/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_NSC/n"
printf '%s\n' "$*" >> "$FAKE_NSC/calls"
cat > "$FAKE_NSC/stdin.$n"
if [ "$1" = create ]; then
  while [ $# -gt 0 ]; do [ "$1" = --cidfile ] && echo mac-1 > "$2"; shift; done
fi
[ ! -f "$FAKE_NSC/$n.out" ] || cat "$FAKE_NSC/$n.out"
[ ! -f "$FAKE_NSC/$n.exit" ] || exit "$(cat "$FAKE_NSC/$n.exit")"
exit 0
EOF
  chmod +x "$T/bin/nsc"
  export FAKE_NSC="$T/nsc"
  printf 'gho_secret\n' > "$FAKE_GH/auth-token.json"
}

mac() { run env CURSOR_API_KEY=crsr_k bash "$here/../cursor/mac.sh" "$@"; }

wid=0f0e0d0c-0b0a-4908-8706-050403020100

t_mac_up() {
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  mac up ho-1 https://github.com/o/r main
  eq exit 0 "$code"
  eq stdout "mac-1	$wid" "$out"
  has "create" "--duration 4h" "$(sed -n 1p "$FAKE_NSC/calls")"
  has "keys go by stdin" "export GH_TOKEN=gho_secret" "$(cat "$FAKE_NSC/stdin.2")"
  has "keys go by stdin" "export CURSOR_API_KEY=crsr_k" "$(cat "$FAKE_NSC/stdin.2")"
  has "worker" "agent worker start --name ho-1" "$(sed -n 3,99p "$FAKE_NSC/calls")"
  has "clone at base" "--branch main https://github.com/o/r.git r" "$(sed -n 3,99p "$FAKE_NSC/calls")"
  case "$(cat "$FAKE_NSC/calls")" in
    *gho_secret*|*crsr_k*) echo "a key is on an nsc command line" >&2; exit 1 ;;
    *'> ~/.cursor/agent-cli-state'*) echo "a new worker got an ID" >&2; exit 1 ;;
  esac
}

t_mac_up_keeps_worker_id() {
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  mac up ho-1 https://github.com/o/r main "$wid"
  eq exit 0 "$code"
  eq stdout "mac-1	$wid" "$out"
  has "state written before start" '{"version":1,"workerIdsByDisplayName":{"%s":"%s"}}' "$(sed -n 3,99p "$FAKE_NSC/calls")"
  has "the ID" "ho-1 $wid > ~/.cursor/agent-cli-state.json" "$(sed -n 3,99p "$FAKE_NSC/calls")"
}

t_mac_up_no_worker_id() {
  fake_nsc
  mac up ho-1 https://github.com/o/r main
  eq exit 1 "$code"
  eq stderr "mac.sh: the worker on mac-1 has no ID in agent-cli-state.json" "$err"
  has "destroyed" "destroy mac-1 --force" "$(cat "$FAKE_NSC/calls")"
}

t_mac_up_worker_fails() {
  fake_nsc
  echo 1 > "$FAKE_NSC/3.exit"
  mac up ho-1 https://github.com/o/r main
  eq exit 1 "$code"
  eq stderr "mac.sh: the worker did not start on mac-1" "$err"
  has "destroyed" "destroy mac-1 --force" "$(cat "$FAKE_NSC/calls")"
}

t_mac_up_bad_worker() {
  fake_nsc
  mac up 'ho 1;x' https://github.com/o/r main
  eq exit 1 "$code"
  eq stderr "mac.sh: worker name: letters, digits, and - only" "$err"
  [ ! -f "$FAKE_NSC/calls" ] || { echo "nsc ran" >&2; exit 1; }
}

t_mac_alive() {
  fake_nsc
  mac alive -
  eq "no Mac" 1 "$code"
  mac alive mac-1
  eq "worker runs" 0 "$code"
  echo 255 > "$FAKE_NSC/2.exit"
  mac alive mac-1
  eq "Mac gone" 1 "$code"
}

t_mac_down() {
  fake_nsc
  mac down mac-1
  eq exit 0 "$code"
  eq stdout "destroyed mac-1" "$out"
  has "keys removed" "rm -f ~/.ho-env" "$(sed -n 1p "$FAKE_NSC/calls")"
  eq destroy "destroy mac-1 --force" "$(sed -n 2p "$FAKE_NSC/calls")"
}

cases=(
  "mac up rents a Mac, sends the keys by stdin, starts the worker|t_mac_up"
  "mac up starts a new Mac's worker under a known worker ID|t_mac_up_keeps_worker_id"
  "mac up destroys the Mac when the worker has no ID|t_mac_up_no_worker_id"
  "mac up destroys the Mac when the worker does not start|t_mac_up_worker_fails"
  "mac up refuses a worker name the shell would split|t_mac_up_bad_worker"
  "mac alive asks the Mac for its worker|t_mac_alive"
  "mac down deletes the keys and destroys the Mac|t_mac_down"
)
