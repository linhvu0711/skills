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

t_coa_unreadable_keeps_filters() {
  python3 -c 'import compression.zstd' 2>/dev/null && { echo "skip: this python reads zstd itself" >&2; return 0; }
  command -v zstd >/dev/null 2>&1 || { echo "skip: no zstd to write the fixture" >&2; return 0; }
  # Given: compressed rollouts z1 and z2 changed today, and no zstd on PATH
  coa_rollout z1 "fix the export"; coa_rollout z2 "add the flag"
  zstd -q --rm "$HOME/.codex/sessions/$(date +%Y/%m/%d)/rollout-2026-10-01T10-00-00-z1.jsonl"
  zstd -q --rm "$HOME/.codex/sessions/$(date +%Y/%m/%d)/rollout-2026-10-01T10-00-00-z2.jsonl"
  mkdir -p "$T/nozstd"; ln -sf "$(command -v python3)" "$T/nozstd/python3"
  # When
  code=0; PATH="$T/nozstd" python3 "$A" find --root /p/app --id z2 >"$T/out" 2>"$T/err" || code=$?; out="$(cat "$T/out")"
  # Then
  eq unreadable "rollout-2026-10-01T10-00-00-z2.jsonl.zst: needs Python 3.14+ or zstd, project unknown" "$(printf '%s' "$out" | python3 -c 'import json,os,sys; print(" ".join(os.path.basename(r["path"]) + ": " + r["unreadable"] for r in json.load(sys.stdin)))')"
}

cases=(
  "adapter finds a session in the window|t_coa_find_in_window"
  "adapter keeps unreadable rows to the ids asked|t_coa_unreadable_keeps_filters"
)
