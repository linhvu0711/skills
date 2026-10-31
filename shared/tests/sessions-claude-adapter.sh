# sessions-claude-adapter.sh: the cases for the shared core's
# sessions/claude/adapter.py. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
A="$here/../sessions/claude/adapter.py"

# cca_session <id> <prompt> [<days ago>]: a Claude transcript of /p/app,
# last changed <days ago> days back (default 0), under a fresh HOME made once.
cca_session() {
  [ -n "${T:-}" ] || { T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"; }
  local f="$HOME/.claude/projects/-p-app/$1.jsonl"
  mkdir -p "$(dirname "$f")"
  printf '{"type":"user","message":{"role":"user","content":"%s"},"timestamp":"2026-10-01T10:00:00Z","cwd":"/p/app","sessionId":"%s"}\n' "$2" "$1" > "$f"
  python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2])*86400; os.utime(sys.argv[1],(t,t))' "$f" "${3:-0}"
}

# days_ago <n>: the local date n days back, YYYY-MM-DD.
days_ago() { python3 -c 'import datetime as d,sys; print(d.date.today()-d.timedelta(days=int(sys.argv[1])))' "$1"; }

t_cca_find_in_window() {
  # Given: one session of /p/app, changed today
  cca_session s1 "fix the export"
  # When
  run python3 "$A" find --root /p/app --since "$(days_ago 0)"
  # Then
  eq exit 0 "$code"
  eq row "claude s1 fix the export" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(" ".join(r["harness"] + " " + r["id"] + " " + r["title"] for r in json.load(sys.stdin)))')"
}

t_cca_probe_counts_window() {
  # Given: s1 changed today, s2 changed 30 days ago
  cca_session s1 "fix the export"; cca_session s2 "tidy the docs" 30
  # When
  run python3 "$A" probe --root /p/app --since "$(days_ago 7)"
  # Then
  eq stdout '{"harness": "claude", "label": "Claude Code", "sessions": 1, "installed": true}' "$out"
}

t_cca_rows_carry_query_fields() {
  # Given: one session of /p/app, and it is the one this command runs in
  cca_session s1 "fix the export"; export CLAUDE_CODE_SESSION_ID=s1
  # When
  run python3 "$A" find --root /p/app --query export
  # Then
  eq row "s1 25 True 1 fix the export 0m ago float" "$(printf '%s' "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["id"], r["score"], r["current"], r["prompts"], r["first_prompt"], r["age"], type(r["active"]).__name__)')"
}

t_cca_extract_summary() {
  # Given: one session of /p/app
  cca_session s1 "fix the export"
  # When
  run python3 "$A" extract "$HOME/.claude/projects/-p-app/s1.jsonl" --summary --after-compact
  # Then
  eq exit 0 "$code"
  has mode "**Render mode:** summary · after last compaction" "$out"
}

cases=(
  "adapter finds a session in the window|t_cca_find_in_window"
  "probe counts the sessions in the window|t_cca_probe_counts_window"
  "adapter rows carry the score, current flag, and prompt count|t_cca_rows_carry_query_fields"
  "adapter extract renders the summary after the last compaction|t_cca_extract_summary"
)
