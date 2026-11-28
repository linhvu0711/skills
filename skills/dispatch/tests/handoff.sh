# handoff.sh: the cases for this skill's handoff module, driven through a
# fake adapter. The repo's test.sh sources this file after test-lib.sh and
# runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_adapters: a fake devin and cursor adapter in $T/adapters (T made when
# not set yet), HANDOFF_ADAPTERS pointing there, and HOME in the temp folder,
# so the ledger is $T/home/.config/dispatch/handoff.tsv. cd into T. The fake
# takes its name from its file and its verb from $1, and answers from fixture
# files in $FAKE_AD, by route <name>.<verb>: each route counts its calls in
# <route>.calls and logs the args after the verb in <route>.args, one line per
# call. Call n prints <route>.<n>.fail or <route>.fail to stderr and fails when
# one exists, else prints <route>.<n>.err to stderr when it exists, then
# <route>.<n>.out or <route>.out, or nothing when neither exists.
fake_adapters() {
  [ -n "${T:-}" ] || T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/adapters" "$T/ad" "$T/home"
  cat > "$T/adapters/devin.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0" .sh)"; verb="$1"; shift
key="$name.$verb"
n=$(( $(cat "$FAKE_AD/$key.calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_AD/$key.calls"
printf '%s\n' "$*" >> "$FAKE_AD/$key.args"
for f in "$FAKE_AD/$key.$n.fail" "$FAKE_AD/$key.fail"; do
  if [ -f "$f" ]; then cat "$f" >&2; exit 1; fi
done
[ ! -f "$FAKE_AD/$key.$n.err" ] || cat "$FAKE_AD/$key.$n.err" >&2
f="$FAKE_AD/$key.$n.out"; [ -f "$f" ] || f="$FAKE_AD/$key.out"
[ ! -f "$f" ] || cat "$f"
EOF
  cp "$T/adapters/devin.sh" "$T/adapters/cursor.sh"
  export HANDOFF_ADAPTERS="$T/adapters" FAKE_AD="$T/ad" HOME="$T/home"
  cd "$T"
}

handoff() { run bash "$here/../scripts/handoff.sh" "$@"; }

# ledger: the ledger's path, its folder made.
ledger() { mkdir -p "$HOME/.config/dispatch"; printf '%s' "$HOME/.config/dispatch/handoff.tsv"; }

issue12="https://github.com/o/r/issues/12"
row_devin12="2026-10-01T10:00:00Z	devin	devin-a	https://app.devin.ai/sessions/a	$issue12	#12 Export"
row_cursor12="2026-10-02T10:00:00Z	cursor	bc-1	https://cursor.com/agents/bc-1	$issue12	#12 Export"

t_start_records_row() {
  fake_adapters
  printf 'devin-abc\thttps://app.devin.ai/sessions/abc\n' > "$FAKE_AD/devin.start.out"
  printf '# Brief\n' > p.md
  handoff start devin p.md --issue "$issue12" --title "#12 Export"
  eq exit 0 "$code"
  eq ledger "devin	devin-abc	https://app.devin.ai/sessions/abc	$issue12	#12 Export" "$(cut -f2- "$(ledger)")"
}

t_start_passes_options() {
  fake_adapters
  printf 'bc-1\thttps://cursor.com/agents/bc-1\n' > "$FAKE_AD/cursor.start.out"
  printf '# Brief\n' > p.md
  handoff start cursor p.md --issue "$issue12" --title "#12 Export" --repo o/r --base main
  eq exit 0 "$code"
  eq "adapter args" "p.md --title #12 Export --repo o/r --base main" "$(cat "$FAKE_AD/cursor.start.args")"
}

t_route_follows_ledger() {
  fake_adapters
  printf '%s\n%s\n' "$row_devin12" "$row_cursor12" > "$(ledger)"
  handoff route "$issue12"
  eq exit 0 "$code"
  eq stdout "follow cursor bc-1 https://cursor.com/agents/bc-1" "$out"
}

t_route_follows_named() {
  fake_adapters
  printf '%s\n%s\n' "$row_devin12" "$row_cursor12" > "$(ledger)"
  handoff route "$issue12" devin
  eq exit 0 "$code"
  eq stdout "follow devin devin-a https://app.devin.ai/sessions/a" "$out"
}

t_route_new_issue_devin() {
  fake_adapters
  printf '%s\n%s\n' "$row_devin12" "$row_cursor12" > "$(ledger)"
  handoff route https://github.com/o/r/issues/13
  eq exit 0 "$code"
  eq stdout "start devin" "$out"
}

t_status_through_adapter() {
  fake_adapters
  printf 'blocked\trun-1|FINISHED\thttps://github.com/o/r/pull/5\thttps://cursor.com/agents/bc-1\tWhich file?\n' > "$FAKE_AD/cursor.poll.out"
  handoff status cursor bc-1
  eq exit 0 "$code"
  eq stdout "state: blocked
pr: https://github.com/o/r/pull/5
link: https://cursor.com/agents/bc-1
message: Which file?" "$out"
}

t_say_through_adapter() {
  fake_adapters
  printf 'sent to devin-abc\n' > "$FAKE_AD/devin.say.out"
  printf '# Changed\n' > note.md
  handoff say devin devin-abc note.md
  eq exit 0 "$code"
  eq "adapter args" "devin-abc note.md" "$(cat "$FAKE_AD/devin.say.args")"
}

# unstamped: stdout with each line's leading `[HH:MM] ` dropped.
unstamped() { printf '%s\n' "$out" | sed 's/^\[[0-9:]*\] //'; }

t_watch_events() {
  fake_adapters
  printf 'working\tworking|-\t-\thttps://app.devin.ai/sessions/abc\t-\n' > "$FAKE_AD/devin.poll.1.out"
  printf 'blocked\tblocked|Which file?\t-\thttps://app.devin.ai/sessions/abc\tWhich file?\n' > "$FAKE_AD/devin.poll.2.out"
  printf 'finished\tfinished|Done\thttps://github.com/o/r/pull/5\thttps://app.devin.ai/sessions/abc\tDone\n' > "$FAKE_AD/devin.poll.3.out"
  handoff watch devin devin-abc --interval 0
  eq exit 0 "$code"
  eq stdout "blocked https://app.devin.ai/sessions/abc :: Which file?
pr https://github.com/o/r/pull/5
finished https://app.devin.ai/sessions/abc :: Done" "$(unstamped)"
}

t_watch_once_on_pr() {
  fake_adapters
  printf 'working\tworking|-\thttps://github.com/o/r/pull/5\thttps://app.devin.ai/sessions/abc\t-\n' > "$FAKE_AD/devin.poll.out"
  handoff watch devin devin-abc --interval 0 --once
  eq exit 0 "$code"
  eq stdout "pr https://github.com/o/r/pull/5" "$(unstamped)"
}

t_watch_survives_a_failed_poll() {
  fake_adapters
  printf 'stop: HTTP 502 on GET /sessions/devin-abc\n' > "$FAKE_AD/devin.poll.1.fail"
  printf 'finished\tfinished|Done\t-\thttps://app.devin.ai/sessions/abc\tDone\n' > "$FAKE_AD/devin.poll.2.out"
  handoff watch devin devin-abc --interval 0
  eq exit 0 "$code"
  eq stdout "finished https://app.devin.ai/sessions/abc :: Done" "$(unstamped)"
}

t_watch_stops_on_failing_polls() {
  fake_adapters
  printf 'stop: HTTP 401 on GET /sessions/devin-abc: bad key\n' > "$FAKE_AD/devin.poll.fail"
  handoff watch devin devin-abc --interval 0
  eq exit 1 "$code"
  lacks stdout "poll failed" "$out"
  eq "stderr last line" "stop: poll failed devin-abc :: HTTP 401 on GET /sessions/devin-abc: bad key" "$(printf '%s\n' "$err" | tail -n 1)"
}

t_watch_releases_before_it_stops() {
  # Given: the poll fails each time, as when gh is signed out
  fake_adapters
  printf 'stop: gh failed: gh auth login\n' > "$FAKE_AD/cursor.poll.fail"
  # When
  handoff watch cursor bc-1 --interval 0
  # Then
  eq exit 1 "$code"
  eq "release calls" 1 "$(cat "$FAKE_AD/cursor.release.calls" 2>/dev/null || echo 0)"
  eq "stderr last line" "stop: poll failed bc-1 :: gh failed: gh auth login" "$(printf '%s\n' "$err" | tail -n 1)"
}

t_new_adapter_file() {
  # Given: a third adapter file, zed
  fake_adapters
  cp "$T/adapters/devin.sh" "$T/adapters/zed.sh"
  printf 'zed-1\thttps://zed.test/1\n' > "$FAKE_AD/zed.start.out"
  printf '# Brief\n' > p.md
  # When
  handoff start zed p.md --issue "$issue12" --title "#12 Export"
  # Then
  eq exit 0 "$code"
  eq ledger "zed	zed-1	https://zed.test/1	$issue12	#12 Export" "$(cut -f2- "$(ledger)")"
}

t_release_through_adapter() {
  # Given
  fake_adapters
  printf '%s\n%s\n' "$row_devin12" "$row_cursor12" > "$(ledger)"
  printf 'bc-1: destroyed mac-1\n' > "$FAKE_AD/cursor.release.out"
  # When
  handoff release bc-1
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1: destroyed mac-1" "$out"
  eq "adapter args" "bc-1" "$(cat "$FAKE_AD/cursor.release.args")"
}

t_watch_releases_once() {
  # Given: the run ends on poll 2 and stays ended on poll 3; polls 4 to 6
  # fail, the one way a --follow watch ends
  fake_adapters
  printf 'working\trun-2|RUNNING\t-\thttps://cursor.com/agents/bc-1\t-\n' > "$FAKE_AD/cursor.poll.1.out"
  printf 'finished\trun-2|FINISHED\t-\thttps://cursor.com/agents/bc-1\tDone\n' > "$FAKE_AD/cursor.poll.out"
  for n in 4 5 6; do printf 'HTTP 502\n' > "$FAKE_AD/cursor.poll.$n.fail"; done
  printf 'bc-1: destroyed mac-1\n' > "$FAKE_AD/cursor.release.out"
  # When
  handoff watch cursor bc-1 --interval 0 --follow
  # Then
  eq exit 1 "$code"
  eq "release calls" 1 "$(cat "$FAKE_AD/cursor.release.calls")"
  eq "release args" "bc-1" "$(cat "$FAKE_AD/cursor.release.args")"
  eq stdout "finished https://cursor.com/agents/bc-1 :: Done" "$(unstamped)"
}

t_watch_once_releases_before_pr() {
  # Given: the poll that ends the run also brings the first PR
  fake_adapters
  printf 'working\trun-2|RUNNING\t-\thttps://cursor.com/agents/bc-1\t-\n' > "$FAKE_AD/cursor.poll.1.out"
  printf 'finished\trun-2|FINISHED\thttps://github.com/o/r/pull/9\thttps://cursor.com/agents/bc-1\tDone\n' > "$FAKE_AD/cursor.poll.out"
  printf 'bc-1: destroyed mac-1\n' > "$FAKE_AD/cursor.release.out"
  # When
  handoff watch cursor bc-1 --interval 0 --once
  # Then
  eq exit 0 "$code"
  eq stdout "pr https://github.com/o/r/pull/9" "$(unstamped)"
  eq "release calls" 1 "$(cat "$FAKE_AD/cursor.release.calls" 2>/dev/null || echo 0)"
}

t_status_never_releases() {
  # Given
  fake_adapters
  printf 'finished\trun-2|FINISHED\t-\thttps://cursor.com/agents/bc-1\tDone\n' > "$FAKE_AD/cursor.poll.out"
  # When
  handoff status cursor bc-1
  # Then
  eq exit 0 "$code"
  eq "line 1" "state: finished" "$(printf '%s\n' "$out" | sed -n 1p)"
  [ ! -f "$FAKE_AD/cursor.release.calls" ] || eq "release calls" "" "$(cat "$FAKE_AD/cursor.release.calls")"
}

cases=(
  "watch returns the Mac once when the run ends|t_watch_releases_once"
  "watch --once gives the Mac back before it prints a PR|t_watch_once_releases_before_pr"
  "status never releases|t_status_never_releases"
  "release frees the session through its executor|t_release_through_adapter"
  "a new adapter file adds an executor|t_new_adapter_file"
  "start records the session in the ledger|t_start_records_row"
  "start passes adapter options through|t_start_passes_options"
  "route follows the executor the ledger has|t_route_follows_ledger"
  "route follows the named executor's own session|t_route_follows_named"
  "route starts an issue with no session on devin|t_route_new_issue_devin"
  "status reads the session through the adapter named|t_status_through_adapter"
  "say sends the note through the adapter named|t_say_through_adapter"
  "watch prints events as they come and stops when finished|t_watch_events"
  "watch --once exits on a new PR|t_watch_once_on_pr"
  "watch goes on after one failed poll|t_watch_survives_a_failed_poll"
  "watch stops after three failed polls in a row|t_watch_stops_on_failing_polls"
  "watch gives a finished run's Mac back before it stops|t_watch_releases_before_it_stops"
)
