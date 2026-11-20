# subagent-gate.sh: the cases for the shared core's gate/subagent-gate.sh,
# fed one hook payload at a time. The repo's test.sh sources this file after
# test-lib.sh and runs its cases. The gate reads this checkout's real agent
# files, so a case proves the rules as they ship.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# gate <harness> <payload>: run the gate for that harness on the payload, in
# a fresh temp folder T.
gate() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  printf '%s' "$2" > "$T/payload.json"
  run bash "$here/../gate/subagent-gate.sh" "$1" < "$T/payload.json"
}

# claude_start <agent_type>: a Claude Code payload in which that subagent
# starts the explorer; an empty type is the main agent's call.
claude_start() {
  local who=''
  [ -z "$1" ] || who='"agent_id":"a1","agent_type":"'"$1"'",'
  printf '{"session_id":"s1",%s"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"explorer","prompt":"x"}}' "$who"
}

# claude_edit <agent_type>: a Claude Code payload in which that subagent
# edits a file; an empty type is the main agent's call.
claude_edit() {
  local who=''
  [ -z "$1" ] || who='"agent_id":"a1","agent_type":"'"$1"'",'
  printf '{"session_id":"s1",%s"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"}}' "$who"
}

# codex_call <agent_type> <tool_name> <tool_input>: a Codex payload for a call
# by that subagent.
codex_call() {
  printf '{"session_id":"s1","turn_id":"t1","cwd":"/tmp","model":"m","permission_mode":"default","transcript_path":"/tmp/t","tool_use_id":"u1","hook_event_name":"PreToolUse","agent_id":"a1","agent_type":"%s","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3"
}
codex_spawn='{"agent_type":"explorer","message":"x"}'

# agy_gate <TypeName> <toolCall>: run the antigravity gate, in a fresh temp
# folder T, on a call of helper chat c2. A TypeName writes the message that
# started c2 as that agent; an empty one writes no messages folder.
agy_gate() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  local chat="$T/brain/c2/.system_generated"
  mkdir -p "$chat/logs"
  if [ -n "$1" ]; then
    mkdir -p "$chat/messages"
    printf '{"id":"m1","recipient":"c2","sender":"c1","content":"x","sourceMetadata":{"tool":{"conversationId":"c1","toolCall":{"id":"k1","name":"invoke_subagent","argumentsJson":"{\\"Prompt\\":\\"x\\",\\"Role\\":\\"check\\",\\"TypeName\\":\\"%s\\"}"}}}}' "$1" > "$chat/messages/m1.json"
  fi
  printf '{"conversationId":"c2","transcriptPath":"%s/logs/transcript_full.jsonl","cwd":"/tmp","hookEventName":"PreToolUse","modelName":"m","stepIdx":3,"toolCall":%s}' "$chat" "$2" > "$T/payload.json"
  run bash "$here/../gate/subagent-gate.sh" antigravity < "$T/payload.json"
}
agy_spawn='{"id":"k2","name":"invoke_subagent","args":{"TypeName":"explorer","Role":"facts","Prompt":"x"}}'

edit_rule() {
  printf 'Blocked by the subagent gate: %s may not use a file edit tool, since its agent file lists no Edit or Write tool.' "$1"
}

start_rule() {
  printf 'Blocked by the subagent gate: %s may not start %s. Only an agent whose file lists the Agent tool may start a subagent, and only the explorer or the runner, so nesting stops at two levels.' "$1" "$2"
}

t_gate_claude_checker_starts_explorer() {
  # Given: plan-correctness-checker starts the explorer
  # When
  gate claude "$(claude_start plan-correctness-checker)"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_claude_blocks_scope_reviewer_start() {
  # Given: the scope reviewer starts the explorer
  # When
  gate claude "$(claude_start scope-reviewer)"
  # Then
  eq exit 0 "$code"
  eq stdout '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$(start_rule scope-reviewer explorer)"'"}}' "$out"
}

t_gate_claude_blocks_explorer_start() {
  # Given: the explorer, itself started by a checker, starts the explorer
  # When
  gate claude "$(claude_start explorer)"
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(start_rule explorer explorer)"'"' "$out"
}

t_gate_claude_main_starts_any() {
  # Given: the main agent starts the explorer
  # When
  gate claude "$(claude_start '')"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_claude_matcher() {
  # Given: no payload
  T="$(cd "$(mktemp -d)" && pwd -P)"
  # When
  run bash "$here/../gate/subagent-gate.sh" claude matcher
  # Then
  eq exit 0 "$code"
  eq stdout "Agent|Task|Edit|Write|MultiEdit|NotebookEdit" "$out"
}

t_gate_claude_blocks_explorer_edit() {
  # Given: the explorer edits a file
  # When
  gate claude "$(claude_edit explorer)"
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(edit_rule explorer)"'"' "$out"
}

t_gate_claude_main_edits() {
  # Given: the main agent edits a file
  # When
  gate claude "$(claude_edit '')"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_codex_checker_starts_explorer() {
  # Given: plan-correctness-checker starts the explorer
  # When
  gate codex "$(codex_call plan-correctness-checker spawn_agent "$codex_spawn")"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_codex_blocks_scope_reviewer_start() {
  # Given: the scope reviewer starts the explorer
  # When
  gate codex "$(codex_call scope-reviewer spawn_agent "$codex_spawn")"
  # Then
  eq exit 0 "$code"
  eq stdout '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$(start_rule scope-reviewer explorer)"'"}}' "$out"
}

t_gate_codex_blocks_explorer_start() {
  # Given: the explorer, itself started by a checker, starts the explorer
  # When
  gate codex "$(codex_call explorer spawn_agent "$codex_spawn")"
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(start_rule explorer explorer)"'"' "$out"
}

t_gate_codex_blocks_explorer_edit() {
  # Given: the explorer adds a file with apply_patch
  # When
  gate codex "$(codex_call explorer apply_patch '{"command":"*** Begin Patch\n*** Add File: x\n+hi\n*** End Patch"}')"
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(edit_rule explorer)"'"' "$out"
}

t_gate_agy_checker_starts_explorer() {
  # Given: plan-correctness-checker starts the explorer
  # When
  agy_gate plan-correctness-checker "$agy_spawn"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_agy_blocks_scope_reviewer_start() {
  # Given: the scope reviewer starts the explorer
  # When
  agy_gate scope-reviewer "$agy_spawn"
  # Then
  eq exit 0 "$code"
  eq stdout '{"decision":"deny","reason":"'"$(start_rule scope-reviewer explorer)"'"}' "$out"
}

t_gate_agy_blocks_explorer_start() {
  # Given: the explorer, itself started by a checker, starts the explorer
  # When
  agy_gate explorer "$agy_spawn"
  # Then
  eq exit 0 "$code"
  has stdout '"reason":"'"$(start_rule explorer explorer)"'"' "$out"
}

t_gate_agy_blocks_explorer_edit() {
  # Given: the explorer writes a file
  # When
  agy_gate explorer '{"id":"k2","name":"write_file","args":{"TargetFile":"/tmp/x"}}'
  # Then
  eq exit 0 "$code"
  has stdout '"reason":"'"$(edit_rule explorer)"'"' "$out"
}

t_gate_agy_no_start_message_is_main() {
  # Given: a chat with no messages folder starts the explorer
  # When
  agy_gate '' "$agy_spawn"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

cases=(
  "gate lets a claude checker start the explorer|t_gate_claude_checker_starts_explorer"
  "gate blocks a claude scope reviewer's start|t_gate_claude_blocks_scope_reviewer_start"
  "gate blocks a claude explorer's start|t_gate_claude_blocks_explorer_start"
  "gate lets the claude main agent start any agent|t_gate_claude_main_starts_any"
  "gate prints the claude matcher|t_gate_claude_matcher"
  "gate blocks a claude explorer's edit|t_gate_claude_blocks_explorer_edit"
  "gate lets the claude main agent edit|t_gate_claude_main_edits"
  "gate lets a codex checker start the explorer|t_gate_codex_checker_starts_explorer"
  "gate blocks a codex scope reviewer's start|t_gate_codex_blocks_scope_reviewer_start"
  "gate blocks a codex explorer's start|t_gate_codex_blocks_explorer_start"
  "gate blocks a codex explorer's edit|t_gate_codex_blocks_explorer_edit"
  "gate lets an antigravity checker start the explorer|t_gate_agy_checker_starts_explorer"
  "gate blocks an antigravity scope reviewer's start|t_gate_agy_blocks_scope_reviewer_start"
  "gate blocks an antigravity explorer's start|t_gate_agy_blocks_explorer_start"
  "gate blocks an antigravity explorer's edit|t_gate_agy_blocks_explorer_edit"
  "gate reads an antigravity chat with no start message as the main agent|t_gate_agy_no_start_message_is_main"
)
