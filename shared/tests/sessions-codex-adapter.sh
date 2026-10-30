# sessions-codex-adapter.sh: the cases for the shared core's
# sessions/codex/adapter.py. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
A="$here/../sessions/codex/adapter.py"

# coa_rollout <id> <prompt>: a Codex rollout of /p/app in today's folder,
# under a fresh HOME made once.
coa_rollout() {
  [ -n "${T:-}" ] || { T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"; }
  local d="$HOME/.codex/sessions/$(date +%Y/%m/%d)"
  mkdir -p "$d"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z","source":"cli"}}\n' "$1" > "$d/rollout-2026-10-01T10-00-00-$1.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$2" >> "$d/rollout-2026-10-01T10-00-00-$1.jsonl"
}

t_coa_find_in_window() {
  # Given: one rollout of /p/app, changed today
  coa_rollout c1 "fix the export"
  # When
  run python3 "$A" find --root /p/app --since "$(date +%F)"
  # Then
  eq exit 0 "$code"
  eq row "codex c1 fix the export" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(" ".join(r["harness"] + " " + r["id"] + " " + r["title"] for r in json.load(sys.stdin)))')"
}

cases=(
  "adapter finds a session in the window|t_coa_find_in_window"
)
