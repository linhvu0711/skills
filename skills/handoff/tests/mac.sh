# mac.sh: the cases for this skill's Namespace Mac script, driven through the
# fake nsc and the fake gh of test-lib.sh. The repo's test.sh sources this
# file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mac() { run env CURSOR_API_KEY=crsr_k bash "$here/../scripts/mac.sh" "$@"; }

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

t_mac_down_fails() {
  # Given: call 1 is the ssh step, call 2 the destroy, which fails
  fake_nsc
  echo 1 > "$FAKE_NSC/2.exit"
  printf 'Failed: not signed in\n' > "$FAKE_NSC/2.out"
  # When
  mac down mac-1
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "mac.sh: could not destroy mac-1 (Failed: not signed in). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force" "$err"
}

t_mac_down_gone() {
  # Given: the destroy fails because Namespace holds no such Mac
  fake_nsc
  echo 1 > "$FAKE_NSC/2.exit"
  printf 'Failed: mac-1: does not exist.\n' > "$FAKE_NSC/2.out"
  # When
  mac down mac-1
  # Then
  eq exit 0 "$code"
  eq stdout "already gone mac-1" "$out"
  eq stderr "" "$err"
}

t_mac_up_destroy_fails() {
  # Given: the worker does not start (call 3), and the cleanup's destroy
  # (call 5, after its ssh step) fails
  fake_nsc
  echo 1 > "$FAKE_NSC/3.exit"
  echo 1 > "$FAKE_NSC/5.exit"
  printf 'Failed: timeout\n' > "$FAKE_NSC/5.out"
  # When
  mac up ho-1 https://github.com/o/r main
  # Then
  eq exit 1 "$code"
  eq stderr "mac.sh: could not destroy mac-1 (Failed: timeout). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force
mac.sh: the worker did not start on mac-1" "$err"
}

cases=(
  "mac up rents a Mac, sends the keys by stdin, starts the worker|t_mac_up"
  "mac up starts a new Mac's worker under a known worker ID|t_mac_up_keeps_worker_id"
  "mac up destroys the Mac when the worker has no ID|t_mac_up_no_worker_id"
  "mac up destroys the Mac when the worker does not start|t_mac_up_worker_fails"
  "mac up refuses a worker name the shell would split|t_mac_up_bad_worker"
  "mac alive asks the Mac for its worker|t_mac_alive"
  "mac down deletes the keys and destroys the Mac|t_mac_down"
  "mac down fails and names the Mac when nsc destroy fails|t_mac_down_fails"
  "mac down counts a Mac that no longer exists as given back|t_mac_down_gone"
  "mac up names a Mac it could not destroy after a failed start|t_mac_up_destroy_fails"
)
