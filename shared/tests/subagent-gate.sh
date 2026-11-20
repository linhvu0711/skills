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

cases=(
  "gate lets a claude checker start the explorer|t_gate_claude_checker_starts_explorer"
  "gate blocks a claude scope reviewer's start|t_gate_claude_blocks_scope_reviewer_start"
  "gate blocks a claude explorer's start|t_gate_claude_blocks_explorer_start"
  "gate lets the claude main agent start any agent|t_gate_claude_main_starts_any"
  "gate prints the claude matcher|t_gate_claude_matcher"
)
