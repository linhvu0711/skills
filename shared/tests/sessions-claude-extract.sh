# sessions-claude-extract.sh: the cases for the shared core's
# sessions/claude/extract_session.py. The repo's test.sh sources this file
# after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
X="$here/../sessions/claude/extract_session.py"

t_cce_helper_log_by_path() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  local f="$HOME/.claude/projects/-p-app/s1/subagents/agent-a1.jsonl"
  mkdir -p "$(dirname "$f")"
  printf '{"type":"user","message":{"role":"user","content":"read the config"},"isSidechain":true}\n' > "$f"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"found it"}]},"isSidechain":true}\n' >> "$f"
  run python3 "$X" "$f" --summary
  eq exit 0 "$code"
  has prompt "read the config" "$out"
  has reply "found it" "$out"
}

# cce_log: a fresh temp folder T and a Claude log at $T/s.jsonl of /p/app:
# a prompt, a reply with thinking and an Edit of /p/app/a.py, a 600-character
# tool result, a compaction summary, a task notification, a second prompt,
# and a last reply.
cce_log() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  local r; r="$(printf 'r%.0s' $(seq 600))"
  {
    printf '{"type":"user","message":{"role":"user","content":"fix the export"},"cwd":"/p/app","sessionId":"s1","timestamp":"2026-10-01T10:00:00Z"}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"weigh the csv path"},{"type":"text","text":"first reply"},{"type":"tool_use","name":"Edit","input":{"file_path":"/p/app/a.py","old_string":"x","new_string":"y"}}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"%s"}]}}\n' "$r"
    printf '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"recap of the export work"}}\n'
    printf '{"type":"user","message":{"role":"user","content":"<task-notification>\\n<task-id>b1</task-id>\\n<status>completed</status>\\n<summary>Build finished</summary>\\n<result>ok</result>\\n</task-notification>"}}\n'
    printf '{"type":"user","message":{"role":"user","content":"second ask"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"last reply"}]}}\n'
  } > "$T/s.jsonl"
}

# users: how many lines of the output are a user block's heading.
users() { printf '%s\n' "$out" | grep -c '^## 🧑 User$' || true; }

t_cce_compaction() {
  # Given: the log
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --summary
  # Then
  has compaction "## 📦 Compaction summary (auto-generated recap of everything above it)" "$out"
}

t_cce_task_notification() {
  # Given: the log
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --summary
  # Then
  has note "[task notification] Build finished · completed · ok" "$out"
}

t_cce_full() {
  # Given: the log
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --full
  # Then
  has thinking "## 💭 Thinking" "$out"
}

t_cce_tail() {
  # Given: the log, with two prompts
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --summary --tail 1
  # Then
  eq users 1 "$(users)"
}

t_cce_after_compact() {
  # Given: the log, one prompt before the compaction and one after
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --summary --after-compact
  # Then
  eq users 1 "$(users)"
}

t_cce_max_result_chars() {
  # Given: the log, with a 600-character tool result
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --max-result-chars 100
  # Then
  has cut "… [+500 chars truncated]" "$out"
}

t_cce_list() {
  # Given: the log, with two prompts
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --list
  # Then
  has turns "turns:  2 user prompts" "$out"
}

t_cce_skeleton() {
  # Given: the log, with an Edit of /p/app/a.py
  cce_log
  # When
  run python3 "$X" "$T/s.jsonl" --skeleton
  # Then
  has edited '- `/p/app/a.py`' "$out"
}


t_cce_drops_injected_text() {
  # Given: a log whose first user row is a command's output, then a prompt
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  {
    printf '{"type":"user","message":{"role":"user","content":"<local-command-stdout>built ok</local-command-stdout>"},"cwd":"/p/app","sessionId":"s1","timestamp":"2026-10-01T10:00:00Z"}\n'
    printf '{"type":"user","message":{"role":"user","content":"fix the export"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n'
  } > "$T/s.jsonl"
  # When
  run python3 "$X" "$T/s.jsonl" --summary
  # Then
  eq exit 0 "$code"
  lacks injected "built ok" "$out"
  has prompt "fix the export" "$out"
}

cases=(
  "extractor drops text the harness injected|t_cce_drops_injected_text"
  "extractor reads a helper log by path|t_cce_helper_log_by_path"
  "extractor marks a compaction summary|t_cce_compaction"
  "extractor turns a task notification into one line|t_cce_task_notification"
  "extractor --full shows thinking|t_cce_full"
  "extractor --tail keeps the last prompts|t_cce_tail"
  "extractor --after-compact starts at the last compaction|t_cce_after_compact"
  "extractor --max-result-chars cuts a tool result|t_cce_max_result_chars"
  "extractor --list counts the prompts|t_cce_list"
  "extractor --skeleton lists the edited files|t_cce_skeleton"
)
