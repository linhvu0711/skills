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
# one exists, else prints <route>.<n>.out or <route>.out.
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
f="$FAKE_AD/$key.$n.out"; [ -f "$f" ] || f="$FAKE_AD/$key.out"
cat "$f"
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
  eq exit 1 "$code"
  eq stderr "handoff.sh: executor must be devin or cursor" "$err"
}

t_failed_start_keeps_ledger() {
  fake_adapters
  row="2026-10-01T10:00:00Z	devin	devin-a	https://app.devin.ai/sessions/a	https://github.com/o/r/issues/11	#11 Old"
  printf '%s\n' "$row" > "$(ledger)"
  printf 'devin.sh: HTTP 400 on POST /sessions: platform must be one of linux, macos\n' > "$FAKE_AD/devin.start.fail"
  printf '# Brief\n' > p.md
  handoff start devin p.md --issue "$issue12" --title "#12 Export" --platform mac
  eq exit 1 "$code"
  eq stderr "devin.sh: HTTP 400 on POST /sessions: platform must be one of linux, macos" "$err"
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

cases=(
  "start records the session in the ledger|t_start_records_row"
  "start passes adapter options through|t_start_passes_options"
  "unknown executor stops|t_unknown_executor"
  "a failed start leaves the ledger as it was|t_failed_start_keeps_ledger"
  "route follows the executor the ledger has|t_route_follows_ledger"
  "route follows the named executor's own session|t_route_follows_named"
  "route starts an issue with no session on devin|t_route_new_issue_devin"
  "start on another executor's issue names it|t_start_names_other_executor"
  "status reads the session through the adapter named|t_status_through_adapter"
  "say sends the note through the adapter named|t_say_through_adapter"
  "watch prints events as they come and stops when finished|t_watch_events"
  "watch prints still running at its time limit|t_watch_time_limit"
)
