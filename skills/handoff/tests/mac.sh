# mac.sh: the cases for this skill's Namespace Mac script, driven through the
# fake nsc and the fake gh of test-lib.sh. The repo's test.sh sources this
# file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mac() { run env HOME="$T/home" CURSOR_API_KEY=crsr_k bash "$here/../scripts/mac.sh" "$@"; }

# macs: the row file mac.sh keeps. row_with <mac>: writes the one row of bc-1
# on ho-1, its Mac <mac>.
macs() { cat "$T/home/.config/dispatch/cursor-macs.tsv"; }
row_with() {
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\t%s\thttps://github.com/o/r\tmain\t%s\n' "$wid" "$1" > "$T/home/.config/dispatch/cursor-macs.tsv"
}

# The line mac.sh prints when it cannot destroy mac-1.
not_given_back="mac.sh: could not destroy mac-1 (Failed: timeout). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force"

wid=0f0e0d0c-0b0a-4908-8706-050403020100

t_mac_rent_starts_worker() {
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  mac rent ho-1 https://github.com/o/r main -- printf 'bc-1\tu\n'
  eq exit 0 "$code"
  eq stdout "bc-1	u" "$out"
  has "create" "--duration 4h" "$(sed -n 1p "$FAKE_NSC/calls")"
  has "keys go by stdin" "export GH_TOKEN=gho_secret" "$(cat "$FAKE_NSC/stdin.2")"
  has "keys go by stdin" "export CURSOR_API_KEY=crsr_k" "$(cat "$FAKE_NSC/stdin.2")"
  has "worker" "agent worker start --name ho-1" "$(sed -n 3,99p "$FAKE_NSC/calls")"
  has "clone at base" "--branch main https://github.com/o/r.git r" "$(sed -n 3,99p "$FAKE_NSC/calls")"
  lacks "nsc commands" gho_secret "$(cat "$FAKE_NSC/calls")"
  lacks "nsc commands" crsr_k "$(cat "$FAKE_NSC/calls")"
  lacks "nsc commands" '> ~/.cursor/agent-cli-state' "$(cat "$FAKE_NSC/calls")"
}

t_mac_renew_keeps_worker_id() {
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  row_with -
  mac renew bc-1 -- true
  eq exit 0 "$code"
  has "state written before start" '{"version":1,"workerIdsByDisplayName":{"%s":"%s"}}' "$(sed -n 3,99p "$FAKE_NSC/calls")"
  has "the ID" "ho-1 $wid > ~/.cursor/agent-cli-state.json" "$(sed -n 3,99p "$FAKE_NSC/calls")"
}

t_mac_rent_no_worker_id() {
  fake_nsc
  mac rent ho-1 https://github.com/o/r main -- true
  eq exit 1 "$code"
  eq stderr "mac.sh: the worker on mac-1 has no ID in agent-cli-state.json" "$err"
  has "destroyed" "destroy mac-1 --force" "$(cat "$FAKE_NSC/calls")"
}

t_mac_rent_worker_fails() {
  fake_nsc
  echo 1 > "$FAKE_NSC/3.exit"
  mac rent ho-1 https://github.com/o/r main -- true
  eq exit 1 "$code"
  eq stderr "mac.sh: the worker did not start on mac-1" "$err"
  has "destroyed" "destroy mac-1 --force" "$(cat "$FAKE_NSC/calls")"
}

t_mac_rent_bad_worker() {
  fake_nsc
  mac rent 'ho 1;x' https://github.com/o/r main -- true
  eq exit 1 "$code"
  eq stderr "mac.sh: worker name: letters, digits, and - only" "$err"
  [ ! -f "$FAKE_NSC/calls" ] || eq "nsc calls" "" "$(cat "$FAKE_NSC/calls")"
}

t_mac_return_deletes_keys() {
  fake_nsc
  row_with mac-1
  mac return bc-1 -- true
  eq exit 0 "$code"
  eq stdout "bc-1: destroyed mac-1" "$out"
  has "keys removed" "rm -f ~/.ho-env" "$(sed -n 1p "$FAKE_NSC/calls")"
  eq destroy "destroy mac-1 --force" "$(sed -n 2p "$FAKE_NSC/calls")"
}

t_mac_return_destroy_fails() {
  # Given: call 1 is the ssh step, call 2 the destroy, which fails
  fake_nsc
  row_with mac-1
  echo 1 > "$FAKE_NSC/2.exit"
  printf 'Failed: not signed in\n' > "$FAKE_NSC/2.out"
  # When
  mac return bc-1 -- true
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "mac.sh: could not destroy mac-1 (Failed: not signed in). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force" "$err"
}

t_mac_return_gone() {
  # Given: the destroy fails because Namespace holds no such Mac
  fake_nsc
  row_with mac-1
  echo 1 > "$FAKE_NSC/2.exit"
  printf 'Failed: mac-1: does not exist.\n' > "$FAKE_NSC/2.out"
  # When
  mac return bc-1 -- true
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1: already gone mac-1" "$out"
  eq stderr "" "$err"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	-" "$(macs)"
}

t_mac_rent_destroy_fails() {
  # Given: the worker does not start (call 3), and the cleanup's destroy
  # (call 5, after its ssh step) fails
  fake_nsc
  echo 1 > "$FAKE_NSC/3.exit"
  echo 1 > "$FAKE_NSC/5.exit"
  printf 'Failed: timeout\n' > "$FAKE_NSC/5.out"
  # When
  mac rent ho-1 https://github.com/o/r main -- true
  # Then
  eq exit 1 "$code"
  eq stderr "$not_given_back
mac.sh: the worker did not start on mac-1" "$err"
}

t_mac_rent() {
  # Given
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  # When
  mac rent ho-1 https://github.com/o/r main -- printf 'bc-1\thttps://cursor.com/agents/bc-1\n'
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1	https://cursor.com/agents/bc-1" "$out"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_rent_create_fails() {
  # Given
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  # When
  mac rent ho-1 https://github.com/o/r main -- sh -c 'echo "cursor.sh: HTTP 500 on POST /agents" >&2; exit 1'
  # Then
  eq exit 1 "$code"
  eq stderr "cursor.sh: HTTP 500 on POST /agents" "$err"
  eq "last nsc call" "destroy mac-1 --force" "$(tail -1 "$FAKE_NSC/calls")"
  [ ! -s "$T/home/.config/dispatch/cursor-macs.tsv" ] || eq "mac rows" "" "$(cat "$T/home/.config/dispatch/cursor-macs.tsv")"
}

t_mac_rent_names_kept_mac() {
  # Given: the start command fails, and the give-back's destroy (call 5) fails
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  echo 1 > "$FAKE_NSC/5.exit"
  printf 'Failed: timeout\n' > "$FAKE_NSC/5.out"
  # When
  mac rent ho-1 https://github.com/o/r main -- sh -c 'echo "cursor.sh: HTTP 500 on POST /agents" >&2; exit 1'
  # Then
  eq exit 1 "$code"
  has stderr "$not_given_back" "$err"
  eq "last line" "mac.sh: no agent started, so no row names mac-1" "$(printf '%s\n' "$err" | tail -1)"
}

t_mac_rent_grok_key() {
  # Given
  fake_nsc
  # When
  run env HOME="$T/home" CURSOR_API_KEY=grok_k bash "$here/../scripts/mac.sh" rent ho-1 https://github.com/o/r main -- true
  # Then
  eq exit 1 "$code"
  eq stderr "mac.sh: a Mac worker refuses grok_ keys: put a personal crsr_ key in CURSOR_API_KEY" "$err"
  [ ! -f "$FAKE_NSC/calls" ] || eq "nsc calls" "" "$(cat "$FAKE_NSC/calls")"
}

t_mac_renew_no_row() {
  # Given: no row file
  fake_nsc
  # When
  mac renew bc-9 -- sh -c 'echo "sent ${MAC_NEW_BASE:-same}"'
  # Then
  eq exit 0 "$code"
  eq stdout "sent same" "$out"
  [ ! -f "$FAKE_NSC/calls" ] || eq "nsc calls" "" "$(cat "$FAKE_NSC/calls")"
}

t_mac_renew_alive() {
  # Given: the Mac's worker runs
  fake_nsc
  row_with mac-1
  # When
  mac renew bc-1 -- sh -c 'echo "sent ${MAC_NEW_BASE:-same}"'
  # Then
  eq exit 0 "$code"
  eq stdout "sent same" "$out"
  eq "nsc calls" 1 "$(wc -l < "$FAKE_NSC/calls" | tr -d ' ')"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_renew_new_mac() {
  # Given: no Mac up
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  row_with -
  # When
  mac renew bc-1 -- sh -c 'echo "sent ${MAC_NEW_BASE:-same}"'
  # Then
  eq exit 0 "$code"
  eq stdout "sent main" "$out"
  has "same worker ID" "ho-1 $wid > ~/.cursor/agent-cli-state.json" "$(sed -n 3,99p "$FAKE_NSC/calls")"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_renew_send_fails() {
  # Given: no Mac up, and the send fails
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  row_with -
  # When
  mac renew bc-1 -- sh -c 'echo "cursor.sh: HTTP 409 on POST /agents/bc-1/runs: agent_busy" >&2; exit 1'
  # Then
  eq exit 1 "$code"
  eq "last nsc call" "destroy mac-1 --force" "$(tail -1 "$FAKE_NSC/calls")"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	-" "$(macs)"
}

t_mac_renew_send_fails_mac_kept() {
  # Given: as t_mac_renew_send_fails, and the new Mac's destroy (call 5) fails
  fake_nsc
  echo "$wid" > "$FAKE_NSC/3.out"
  echo 1 > "$FAKE_NSC/5.exit"
  printf 'Failed: timeout\n' > "$FAKE_NSC/5.out"
  row_with -
  # When
  mac renew bc-1 -- sh -c 'echo "cursor.sh: HTTP 409 on POST /agents/bc-1/runs: agent_busy" >&2; exit 1'
  # Then
  eq exit 1 "$code"
  has stderr "$not_given_back" "$err"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_renew_old_mac_kept() {
  # Given: the old Mac is not alive (call 1) and cannot be destroyed (call 3)
  fake_nsc
  row_with mac-1
  echo 255 > "$FAKE_NSC/1.exit"
  echo 1 > "$FAKE_NSC/3.exit"
  printf 'Failed: timeout\n' > "$FAKE_NSC/3.out"
  # When
  mac renew bc-1 -- touch "$T/sent"
  # Then
  eq exit 1 "$code"
  eq stderr "$not_given_back
mac.sh: no note sent: mac-1 was not given back" "$err"
  [ ! -f "$T/sent" ] || eq "sent note" "" "$(cat "$T/sent")"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_return() {
  # Given
  fake_nsc
  row_with mac-1
  # When
  mac return bc-1 -- true
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1: destroyed mac-1" "$out"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	-" "$(macs)"
  # When: again
  mac return bc-1 -- true
  # Then
  eq "second exit" 0 "$code"
  eq "second stdout" "bc-1: no Mac" "$out"
  eq "nsc calls" 2 "$(wc -l < "$FAKE_NSC/calls" | tr -d ' ')"
}

t_mac_return_run_goes() {
  # Given
  fake_nsc
  row_with mac-1
  # When
  mac return bc-1 -- false
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1: mac-1 kept, its run has not ended" "$out"
  [ ! -f "$FAKE_NSC/calls" ] || eq "nsc calls" "" "$(cat "$FAKE_NSC/calls")"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_return_check_fails() {
  # Given: the run check cannot read the run (exit 2)
  fake_nsc
  row_with mac-1
  # When
  mac return bc-1 -- sh -c 'echo "cursor.sh: HTTP 502 on GET /agents/bc-1/runs/run-2" >&2; exit 2'
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "cursor.sh: HTTP 502 on GET /agents/bc-1/runs/run-2
mac.sh: could not check the run of bc-1, so mac-1 is kept" "$err"
  [ ! -f "$FAKE_NSC/calls" ] || eq "nsc calls" "" "$(cat "$FAKE_NSC/calls")"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_mac_return_keeps_newer_mac() {
  # Given: the run check is where a renew names mac-2 in the row
  fake_nsc
  row_with mac-1
  printf "printf 'bc-1\\\\tho-1\\\\t%s\\\\thttps://github.com/o/r\\\\tmain\\\\tmac-2\\\\n' > \"%s\"\n" \
    "$wid" "$T/home/.config/dispatch/cursor-macs.tsv" > "$T/renewed"
  # When
  mac return bc-1 -- bash "$T/renewed"
  # Then
  eq exit 0 "$code"
  eq destroy "destroy mac-1 --force" "$(sed -n 2p "$FAKE_NSC/calls")"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-2" "$(macs)"
}

t_mac_return_keeps_row() {
  # Given: the destroy (call 2) fails
  fake_nsc
  row_with mac-1
  echo 1 > "$FAKE_NSC/2.exit"
  printf 'Failed: timeout\n' > "$FAKE_NSC/2.out"
  # When
  mac return bc-1 -- true
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "$not_given_back" "$err"
  eq row "bc-1	ho-1	$wid	https://github.com/o/r	main	mac-1" "$(macs)"
}

cases=(
  "mac rent writes the agent's row after the start command|t_mac_rent"
  "mac rent gives the Mac back when the start command fails|t_mac_rent_create_fails"
  "mac rent names a Mac it could not give back|t_mac_rent_names_kept_mac"
  "mac rent stops on a grok_ key before it rents|t_mac_rent_grok_key"
  "mac renew runs the command as is for an agent with no Mac|t_mac_renew_no_row"
  "mac renew sends as is while the Mac runs|t_mac_renew_alive"
  "mac renew names the new Mac after the send|t_mac_renew_new_mac"
  "mac renew gives the new Mac back when the send fails|t_mac_renew_send_fails"
  "mac renew keeps the new Mac's row when the send fails and the Mac is not given back|t_mac_renew_send_fails_mac_kept"
  "mac renew sends no note when the old Mac is not given back|t_mac_renew_old_mac_kept"
  "mac return gives the Mac back once the run ended|t_mac_return"
  "mac return keeps the Mac while a run goes|t_mac_return_run_goes"
  "mac return fails and keeps the Mac when the run check cannot run|t_mac_return_check_fails"
  "mac return keeps a Mac a renew named meanwhile|t_mac_return_keeps_newer_mac"
  "mac return keeps the row when the Mac is not given back|t_mac_return_keeps_row"
  "mac rent starts the worker, the keys sent by stdin|t_mac_rent_starts_worker"
  "mac renew starts the new Mac's worker under the row's worker ID|t_mac_renew_keeps_worker_id"
  "mac rent gives the Mac back when the worker has no ID|t_mac_rent_no_worker_id"
  "mac rent gives the Mac back when the worker does not start|t_mac_rent_worker_fails"
  "mac rent refuses a worker name the shell would split|t_mac_rent_bad_worker"
  "mac return deletes the keys and destroys the Mac|t_mac_return_deletes_keys"
  "mac return fails and names the Mac when nsc destroy fails|t_mac_return_destroy_fails"
  "mac return counts a Mac that no longer exists as given back|t_mac_return_gone"
  "mac rent names a Mac it could not destroy after a failed start|t_mac_rent_destroy_fails"
)
