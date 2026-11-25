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

# coe_log: a fresh temp folder T and a Codex rollout at $T/r.jsonl of /p/app:
# a user message as a response item and two as events, an exec-wrapped
# apply_patch of a.py, a 600-character tool result, and two replies.
coe_log() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  local r; r="$(printf 'r%.0s' $(seq 600))"
  {
    printf '{"type":"session_meta","payload":{"id":"c1","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z","source":"cli"}}\n'
    printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"from the item row"}]}}\n'
    printf '{"type":"event_msg","payload":{"type":"user_message","message":"fix the export"}}\n'
    printf '{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const r = await tools.apply_patch(\\"*** Begin Patch\\\\n*** Update File: a.py\\\\n@@\\\\n-x\\\\n+y\\\\n*** End Patch\\"); text(r);"}}\n'
    printf '{"type":"response_item","payload":{"type":"custom_tool_call_output","output":"%s"}}\n' "$r"
    printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"first reply"}]}}\n'
    printf '{"type":"event_msg","payload":{"type":"user_message","message":"second ask"}}\n'
    printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"last reply"}]}}\n'
    printf '{"type":"event_msg","payload":{"type":"token_count"}}\n'
  } > "$T/r.jsonl"
}

# users: how many lines of the output are a user block's heading.
users() { printf '%s\n' "$out" | grep -c '^## 🧑 User$' || true; }

t_coe_event_over_item() {
  # Given: the rollout, with user messages as events and as a response item
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl" --summary
  # Then
  lacks item "from the item row" "$out"
}

t_coe_item_completed() {
  # Given: a rollout whose one prompt is an item_completed event
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  printf '{"type":"session_meta","payload":{"id":"c1","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z","source":"cli"}}\n' > "$T/n.jsonl"
  printf '{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"type":"input_text","text":"from the new event"}]}}}\n' >> "$T/n.jsonl"
  # When
  run python3 "$X" "$T/n.jsonl" --summary
  # Then
  has prompt "from the new event" "$out"
}

t_coe_exec_apply_patch() {
  # Given: the rollout, with an exec-wrapped apply_patch of a.py
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl"
  # Then
  has call "→ exec(apply_patch: a.py)" "$out"
}

t_coe_full() {
  # Given: the rollout, with a 600-character tool result
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl" --full
  # Then
  has result "$(printf 'r%.0s' $(seq 600))" "$out"
}

t_coe_tail() {
  # Given: the rollout, with two prompts
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl" --summary --tail 1
  # Then
  eq users 1 "$(users)"
}

t_coe_max_result_chars() {
  # Given: the rollout, with a 600-character tool result
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl" --max-result-chars 100
  # Then
  has cut "… [+500 chars truncated]" "$out"
}

t_coe_list() {
  # Given: the rollout, with two prompts
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl" --list
  # Then
  has turns "turns:  2 user prompts" "$out"
}

t_coe_skeleton() {
  # Given: the rollout, with an exec-wrapped apply_patch of a.py
  coe_log
  # When
  run python3 "$X" "$T/r.jsonl" --skeleton
  # Then
  has patched '- `a.py`' "$out"
}

cases=(
  "extractor reads a rollout by path|t_coe_rollout_by_path"
  "extractor reads a compressed rollout by path|t_coe_zst_by_path"
  "extractor takes event prompts over item prompts|t_coe_event_over_item"
  "extractor reads a prompt from an item_completed event|t_coe_item_completed"
  "extractor names the files an exec apply_patch changes|t_coe_exec_apply_patch"
  "extractor --full keeps a tool result whole|t_coe_full"
  "extractor --tail keeps the last prompts|t_coe_tail"
  "extractor --max-result-chars cuts a tool result|t_coe_max_result_chars"
  "extractor --list counts the prompts|t_coe_list"
  "extractor --skeleton lists the files an exec apply_patch changes|t_coe_skeleton"
)
