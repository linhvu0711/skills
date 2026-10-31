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

t_coa_find_archived() {
  # Given: one rollout of /p/app, moved to the archive
  coa_rollout c1 "fix the export"
  mkdir -p "$HOME/.codex/archived_sessions"
  mv "$HOME/.codex/sessions/$(date +%Y/%m/%d)/rollout-2026-10-01T10-00-00-c1.jsonl" "$HOME/.codex/archived_sessions/"
  # When
  run python3 "$A" find --root /p/app
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

t_coa_rows_carry_query_fields() {
  # Given: one rollout of /p/app, and it is the session this command runs in
  coa_rollout c1 "fix the export"; export CODEX_THREAD_ID=c1
  # When
  run python3 "$A" find --root /p/app --query export
  # Then
  eq row "c1 25 True 1 fix the export 0m ago float" "$(printf '%s' "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["id"], r["score"], r["current"], r["prompts"], r["first_prompt"], r["age"], type(r["active"]).__name__)')"
}

t_coa_extract_summary() {
  # Given: one rollout of /p/app
  coa_rollout c1 "fix the export"
  # When
  run python3 "$A" extract c1 --summary --after-compact
  # Then
  eq exit 0 "$code"
  eq mode "**Render mode:** summary" "$(printf '%s\n' "$out" | grep -F '**Render mode:**')"
}

t_coa_probe_not_installed() {
  # Given: a fresh HOME with no .codex folder
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"; mkdir -p "$HOME"
  # When
  run python3 "$A" probe --root /p/app
  # Then
  eq stdout '{"harness": "codex", "label": "Codex", "sessions": 0, "installed": false}' "$out"
}

cases=(
  "adapter finds a session in the window|t_coa_find_in_window"
  "adapter keeps unreadable rows to the ids asked|t_coa_unreadable_keeps_filters"
  "adapter finds a session only in the archive|t_coa_find_archived"
  "adapter rows carry the score, current flag, and prompt count|t_coa_rows_carry_query_fields"
  "adapter extract renders the summary and drops --after-compact|t_coa_extract_summary"
  "probe says Codex is not installed|t_coa_probe_not_installed"
)
