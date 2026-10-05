# sessions-codex-extract.sh: the cases for the shared core's
# sessions/codex/extract_session.py. The repo's test.sh sources this file
# after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
X="$here/../sessions/codex/extract_session.py"

t_coe_rollout_by_path() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  printf '{"type":"session_meta","payload":{"id":"c1","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z"}}\n' > "$T/r.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"fix the export"}]}}\n' >> "$T/r.jsonl"
  run python3 "$X" "$T/r.jsonl" --summary
  eq exit 0 "$code"
  has prompt "fix the export" "$out"
}

cases=(
  "extractor reads a rollout by path|t_coe_rollout_by_path"
)
