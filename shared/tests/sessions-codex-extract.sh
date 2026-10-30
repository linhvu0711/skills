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

t_coe_zst_by_path() {
  command -v zstd >/dev/null 2>&1 || python3 -c 'import compression.zstd' 2>/dev/null || { echo "skip: no zstd here" >&2; return 0; }
  # Given: a compressed rollout whose user text is "fix the export"
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  printf '{"type":"session_meta","payload":{"id":"c1","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z"}}\n' > "$T/r.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"fix the export"}]}}\n' >> "$T/r.jsonl"
  if command -v zstd >/dev/null 2>&1; then zstd -q --rm "$T/r.jsonl"
  else python3 -c 'import os,sys; from compression import zstd; open(sys.argv[1]+".zst","wb").write(zstd.compress(open(sys.argv[1],"rb").read())); os.remove(sys.argv[1])' "$T/r.jsonl"; fi
  # When
  run python3 "$X" "$T/r.jsonl.zst"
  # Then
  eq exit 0 "$code"
  has prompt "fix the export" "$out"
}

cases=(
  "extractor reads a rollout by path|t_coe_rollout_by_path"
  "extractor reads a compressed rollout by path|t_coe_zst_by_path"
)
