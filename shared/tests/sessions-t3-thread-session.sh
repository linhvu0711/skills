# sessions-t3-thread-session.sh: the cases for the shared core's
# sessions/t3/thread_session.py. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
M="$here/../sessions/t3/thread_session.py"

# t3_home: a fresh HOME with T3's provider log folder.
t3_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  mkdir -p "$HOME/.t3/userdata/logs/provider"
}

t_t3_maps_claude_thread() {
  # Given: thread t1's log names its Claude session in query.open
  t3_home
  printf '[2026-10-30T03:45:32.026Z] NTIVE: {"provider":"claudeAgent","event":{"payload":{"type":"query.open","options":{"sessionId":"cad53cbd-dacd-4191-9903-0b67e9fb883b"}}}}\n' > "$HOME/.t3/userdata/logs/provider/events.t1.log"
  # When
  run python3 "$M" t1
  # Then
  eq stdout '{"thread": "t1", "harness": "claude", "session": "cad53cbd-dacd-4191-9903-0b67e9fb883b"}' "$out"
}

t_t3_no_log() {
  # Given: no log for thread t9
  t3_home
  # When
  run python3 "$M" t9
  # Then
  eq exit 0 "$code"
  eq stdout '{"thread": "t9", "error": "not found"}' "$out"
}

cases=(
  "maps a Claude thread to its session|t_t3_maps_claude_thread"
  "a thread with no log is a not found row|t_t3_no_log"
)
