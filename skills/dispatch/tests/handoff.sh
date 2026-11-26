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

t_unknown_executor() {
  fake_adapters
  printf '# Brief\n' > p.md
  handoff start foo p.md --issue "$issue12"
  eq exit 64 "$code"
  eq "stderr line 1" "stop: executor must be devin or cursor" "${err%%$'\n'*}"
  has stderr "handoff.sh start <executor> <prompt-file>" "$err"
}

t_failed_start_keeps_ledger() {
  fake_adapters
  row="2026-10-01T10:00:00Z	devin	devin-a	https://app.devin.ai/sessions/a	https://github.com/o/r/issues/11	#11 Old"
  printf '%s\n' "$row" > "$(ledger)"
  printf 'stop: HTTP 400 on POST /sessions: platform must be one of linux, macos\n' > "$FAKE_AD/devin.start.fail"
  printf '# Brief\n' > p.md
  handoff start devin p.md --issue "$issue12" --title "#12 Export" --platform mac
  eq exit 1 "$code"
  eq stderr "stop: HTTP 400 on POST /sessions: platform must be one of linux, macos" "$err"
  eq ledger "$row" "$(cat "$(ledger)")"
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

t_route_unknown_executor() {
  fake_adapters
  printf '%s\n' "$row_cursor12" > "$(ledger)"
  handoff route "$issue12" foo
  eq exit 64 "$code"
  eq "stderr line 1" "stop: executor must be devin or cursor" "${err%%$'\n'*}"
  has stderr "handoff.sh start <executor> <prompt-file>" "$err"
}

t_start_names_other_executor() {
  fake_adapters
  printf '%s\n' "$row_devin12" > "$(ledger)"
  printf 'bc-9\thttps://cursor.com/agents/bc-9\n' > "$FAKE_AD/cursor.start.out"
  printf '# Brief\n' > p.md
  handoff start cursor p.md --issue "$issue12" --title "#12 Export" --repo o/r
  eq exit 0 "$code"
  eq stderr "#12 already has a devin session" "$err"
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

t_watch_time_limit() {
  fake_adapters
  printf 'working\tworking|-\t-\thttps://app.devin.ai/sessions/abc\t-\n' > "$FAKE_AD/devin.poll.out"
  handoff watch devin devin-abc --interval 1 --max 1
  eq exit 0 "$code"
  eq stdout "still running https://app.devin.ai/sessions/abc" "$(unstamped)"
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

t_watch_names_why_a_poll_call_is_wrong() {
  # Given: every poll stops on a wrong command line, its usage after the why
  fake_adapters
  printf 'stop: --repo and --issue go together\nusage: cursor.sh poll <agent> [--repo <owner/repo> --issue <n>]\n' > "$FAKE_AD/devin.poll.fail"
  # When
  handoff watch devin devin-abc --interval 0
  # Then
  eq exit 1 "$code"
  eq "stderr last line" "stop: poll failed devin-abc :: --repo and --issue go together" "$(printf '%s\n' "$err" | tail -n 1)"
}

t_watch_shows_poll_warning() {
  # Given: a poll that works and warns of a Mac it could not give back
  fake_adapters
  printf 'stop: could not destroy mac-1 (Failed: timeout). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force\n' > "$FAKE_AD/cursor.poll.1.err"
  printf 'finished\tfinished|Done\t-\thttps://cursor.com/agents/bc-1\tDone\n' > "$FAKE_AD/cursor.poll.1.out"
  # When
  handoff watch cursor bc-1 --interval 0
  # Then
  eq exit 0 "$code"
  eq stdout "stop: could not destroy mac-1 (Failed: timeout). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force
finished https://cursor.com/agents/bc-1 :: Done" "$(unstamped)"
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

t_watch_interval_from_adapter() {
  # Given: the zed adapter gives a 0 s interval
  fake_adapters
  cp "$T/adapters/devin.sh" "$T/adapters/zed.sh"
  printf '0\n' > "$FAKE_AD/zed.interval.out"
  printf 'finished\tfinished|Done\t-\thttps://zed.test/1\tDone\n' > "$FAKE_AD/zed.poll.out"
  : > "$FAKE_AD/zed.release.out"
  # When
  handoff watch zed zed-1 --max 5
  # Then
  eq exit 0 "$code"
  eq "interval calls" 1 "$(cat "$FAKE_AD/zed.interval.calls")"
  eq stdout "finished https://zed.test/1 :: Done" "$(unstamped)"
}

t_facts_through_adapter() {
  # Given
  fake_adapters
  printf 'repo\thttps://github.com/o/r\nmodel\tgpt-5.5\tGPT-5.5\n' > "$FAKE_AD/cursor.facts.out"
  # When
  handoff facts cursor
  # Then
  eq exit 0 "$code"
  eq stdout "repo	https://github.com/o/r
model	gpt-5.5	GPT-5.5" "$out"
  eq "adapter args" "" "$(cat "$FAKE_AD/cursor.facts.args")"
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

t_release_unknown_session() {
  # Given
  fake_adapters
  printf '%s\n%s\n' "$row_devin12" "$row_cursor12" > "$(ledger)"
  printf 'bc-1: destroyed mac-1\n' > "$FAKE_AD/cursor.release.out"
  # When
  handoff release bc-404
  # Then
  eq exit 1 "$code"
  eq stderr "stop: no session bc-404 in the ledger" "$err"
  [ ! -f "$FAKE_AD/cursor.release.calls" ] || eq "release calls" "" "$(cat "$FAKE_AD/cursor.release.calls")"
}

t_watch_releases_once() {
  # Given: the run ends on poll 2 and stays ended
  fake_adapters
  printf 'working\trun-2|RUNNING\t-\thttps://cursor.com/agents/bc-1\t-\n' > "$FAKE_AD/cursor.poll.1.out"
  printf 'finished\trun-2|FINISHED\t-\thttps://cursor.com/agents/bc-1\tDone\n' > "$FAKE_AD/cursor.poll.out"
  printf 'bc-1: destroyed mac-1\n' > "$FAKE_AD/cursor.release.out"
  # When
  handoff watch cursor bc-1 --interval 0 --follow --max 2
  # Then
  eq exit 0 "$code"
  eq "release calls" 1 "$(cat "$FAKE_AD/cursor.release.calls")"
  eq "release args" "bc-1" "$(cat "$FAKE_AD/cursor.release.args")"
  eq stdout "finished https://cursor.com/agents/bc-1 :: Done
still running https://cursor.com/agents/bc-1" "$(unstamped)"
}

t_watch_retries_release() {
  # Given: as t_watch_releases_once, and the first release cannot give the Mac back
  fake_adapters
  printf 'working\trun-2|RUNNING\t-\thttps://cursor.com/agents/bc-1\t-\n' > "$FAKE_AD/cursor.poll.1.out"
  printf 'finished\trun-2|FINISHED\t-\thttps://cursor.com/agents/bc-1\tDone\n' > "$FAKE_AD/cursor.poll.out"
  printf 'bc-1: destroyed mac-1\n' > "$FAKE_AD/cursor.release.out"
  printf 'stop: could not destroy mac-1 (Failed: timeout). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force\n' > "$FAKE_AD/cursor.release.1.fail"
  # When
  handoff watch cursor bc-1 --interval 0 --follow --max 2
  # Then
  eq exit 0 "$code"
  eq "release calls" 2 "$(cat "$FAKE_AD/cursor.release.calls")"
  eq "line 1" "stop: could not destroy mac-1 (Failed: timeout). It still runs and costs money until you destroy it by hand: nsc destroy mac-1 --force" "$(unstamped | sed -n 1p)"
  eq "line 2" "finished https://cursor.com/agents/bc-1 :: Done" "$(unstamped | sed -n 2p)"
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
  "watch tries the release again on its next poll|t_watch_retries_release"
  "watch --once gives the Mac back before it prints a PR|t_watch_once_releases_before_pr"
  "status never releases|t_status_never_releases"
  "release frees the session through its executor|t_release_through_adapter"
  "release stops on a session the ledger lacks|t_release_unknown_session"
  "facts prints the executor's facts|t_facts_through_adapter"
  "a new adapter file adds an executor|t_new_adapter_file"
  "watch takes its interval from the adapter|t_watch_interval_from_adapter"
  "start records the session in the ledger|t_start_records_row"
  "start passes adapter options through|t_start_passes_options"
  "unknown executor stops|t_unknown_executor"
  "a failed start leaves the ledger as it was|t_failed_start_keeps_ledger"
  "route follows the executor the ledger has|t_route_follows_ledger"
  "route follows the named executor's own session|t_route_follows_named"
  "route starts an issue with no session on devin|t_route_new_issue_devin"
  "route stops on an unknown executor|t_route_unknown_executor"
  "start on another executor's issue names it|t_start_names_other_executor"
  "status reads the session through the adapter named|t_status_through_adapter"
  "say sends the note through the adapter named|t_say_through_adapter"
  "watch prints events as they come and stops when finished|t_watch_events"
  "watch prints still running at its time limit|t_watch_time_limit"
  "watch --once exits on a new PR|t_watch_once_on_pr"
  "watch goes on after one failed poll|t_watch_survives_a_failed_poll"
  "watch stops after three failed polls in a row|t_watch_stops_on_failing_polls"
  "watch names why a poll call is wrong, not its usage|t_watch_names_why_a_poll_call_is_wrong"
  "watch shows a warning a poll printed|t_watch_shows_poll_warning"
)
