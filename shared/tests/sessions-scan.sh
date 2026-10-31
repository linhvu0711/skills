# sessions-scan.sh: the cases for the shared core's sessions/scan.py. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
S="$here/../sessions/scan.py"

# scan_home: a fresh HOME with one Claude session and one Codex rollout of
# /p/app, both changed today.
scan_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  mkdir -p "$HOME/.claude/projects/-p-app"
  printf '{"type":"user","message":{"role":"user","content":"fix the export"},"timestamp":"2026-10-01T10:00:00Z","cwd":"/p/app","sessionId":"s1"}\n' > "$HOME/.claude/projects/-p-app/s1.jsonl"
  local d="$HOME/.codex/sessions/$(date +%Y/%m/%d)"; mkdir -p "$d"
  printf '{"type":"session_meta","payload":{"id":"c1","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z","source":"cli"}}\n' > "$d/rollout-2026-10-01T10-00-00-c1.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add the flag"}]}}\n' >> "$d/rollout-2026-10-01T10-00-00-c1.jsonl"
}

t_scan_probes_adapters() {
  # Given: a Claude session and a Codex rollout of /p/app
  scan_home
  # When
  run python3 "$S" --root /p/app --since "$(date +%F)"
  # Then
  eq adapters '[{"harness": "claude", "label": "Claude Code", "sessions": 1, "installed": true}, {"harness": "codex", "label": "Codex", "sessions": 1, "installed": true}]' "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["adapters"]))')"
}

t_scan_names_no_adapter_harness() {
  # Given: OpenCode's database, changed today
  scan_home; mkdir -p "$HOME/.local/share/opencode"; : > "$HOME/.local/share/opencode/opencode.db"
  # When
  run python3 "$S" --root /p/app --since "$(date +%F)"
  # Then
  has unread '"line": "found OpenCode sessions, cannot read them yet"' "$out"
}

cases=(
  "scan probes every adapter folder|t_scan_probes_adapters"
  "scan names a harness with data and no adapter|t_scan_names_no_adapter_harness"
)
