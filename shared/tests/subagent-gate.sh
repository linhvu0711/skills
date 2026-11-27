# subagent-gate.sh: the cases for the shared core's gate/subagent-gate.sh,
# fed one hook payload at a time. The repo's test.sh sources this file after
# test-lib.sh and runs its cases. The gate reads this checkout's real agent
# files, so a case proves the rules as they ship.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# gate <harness> <payload>: run the gate for that harness on the payload,
# outside T3, in a fresh temp folder T that is also its TMPDIR. The test run
# itself may sit in a T3 chat, so T3CODE_THREAD_ID is unset.
gate() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  printf '%s' "$2" > "$T/payload.json"
  run env -u T3CODE_THREAD_ID TMPDIR="$T" bash "$here/../gate/subagent-gate.sh" "$1" < "$T/payload.json"
}

# t3_gate <harness> <payload>: gate, in T3. Its TMPDIR is NOTES when a case
# sets it, so two calls share the gate's notes, else the fresh T.
t3_gate() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  printf '%s' "$2" > "$T/payload.json"
  run env T3CODE_THREAD_ID=t1 TMPDIR="${NOTES:-$T}" bash "$here/../gate/subagent-gate.sh" "$1" < "$T/payload.json"
}

# claude_main_start <agent_type>: a Claude Code payload in which the main
# agent starts that agent.
claude_main_start() {
  printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"x"}}' "$1"
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

edit_rule() {
  printf 'Blocked by the subagent gate: %s may not use a file edit tool, since its agent file lists no Edit or Write tool.' "$1"
}

start_rule() {
  printf 'Blocked by the subagent gate: %s may not start %s. Only an agent whose file lists the Agent tool may start a subagent, and only the explorer or the runner, so nesting stops at two levels.' "$1" "$2"
}

home_rule() {
  printf 'Blocked by the subagent gate: in T3, start %s on its first try, %s, through T3'"'"'s delegate_task, per shared/facts.md § Skill agents. When no try can run, start it by name again: it then runs on its last try.' "$1" "$2"
}

t_gate_claude_refuses_main_first_t3_walker() {
  # Given: T3 is on, and no note exists
  # When
  t3_gate claude "$(claude_main_start walker)"
  # Then
  eq exit 0 "$code"
  eq stdout '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$(home_rule walker 'devin swe-2-1-medium high')"'"}}' "$out"
}

t_gate_t3_second_walker_start_goes_through() {
  # Given: T3 is on; the walker's first start in chat s1 was refused
  NOTES="$(mktemp -d)"; t3_gate claude "$(claude_main_start walker)"
  # When
  t3_gate claude "$(claude_main_start walker)"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
  [ -d "$NOTES/subagent-gate-$(id -u)/s1/walker" ] || { echo "no note at $NOTES/subagent-gate-$(id -u)/s1/walker" >&2; exit 1; }
}

t_gate_t3_refuses_scope_reviewer_after_walker() {
  # Given: T3 is on; the walker's first start in chat s1 was refused
  NOTES="$(mktemp -d)"; t3_gate claude "$(claude_main_start walker)"
  # When
  t3_gate claude "$(claude_main_start scope-reviewer)"
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(home_rule scope-reviewer 'devin swe-2-1-medium high')"'"' "$out"
}

t_gate_codex_refuses_main_first_t3_walker() {
  # Given: T3 is on; the Codex main agent, with no agent_id, starts the walker
  # When
  t3_gate codex '{"session_id":"s1","turn_id":"t1","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"agent_type":"walker","message":"x"}}'
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(home_rule walker 'devin swe-2-1-medium high')"'"' "$out"
}

t_gate_claude_refuses_main_first_t3_logic_reviewer() {
  # Given: T3 is on; the logic reviewer is a tier-3 checker
  # When
  t3_gate claude "$(claude_main_start logic-reviewer)"
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(home_rule logic-reviewer 'antigravity gemini-4-neon medium')"'"' "$out"
}

# codex_log_start <originator>: outside T3's env, a Codex main agent starts
# the walker in a chat whose log was opened by that app.
codex_log_start() {
  local log; log="$(mktemp)"
  printf '{"type":"session_meta","payload":{"id":"s1","originator":"%s"}}\n' "$1" > "$log"
  gate codex '{"session_id":"s1","transcript_path":"'"$log"'","hook_event_name":"PreToolUse","tool_name":"spawn_agent","tool_input":{"agent_type":"walker","message":"x"}}'
}

t_gate_codex_refuses_main_in_t3_log() {
  # Given: T3CODE_THREAD_ID unset; the chat log's first line names T3 Code
  # When
  codex_log_start 'T3 Code'
  # Then
  eq exit 0 "$code"
  has stdout '"permissionDecisionReason":"'"$(home_rule walker 'devin swe-2-1-medium high')"'"' "$out"
}

t_gate_codex_main_outside_t3_log() {
  # Given: the same, with a chat log opened by the Codex CLI
  # When
  codex_log_start codex_cli_rs
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_claude_main_t3_explorer() {
  # Given: T3 is on; the explorer's Claude home is its backup
  # When
  t3_gate claude "$(claude_main_start explorer)"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_claude_main_walker_outside_t3() {
  # Given: T3CODE_THREAD_ID is unset
  # When
  gate claude "$(claude_main_start walker)"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_t3_unreadable_payload() {
  # Given: T3 is on; a payload that is not JSON
  # When
  t3_gate claude 'not json'
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_gate_t3_agent_without_file() {
  # Given: T3 is on; the main agent starts an agent with no file here
  # When
  t3_gate claude "$(claude_main_start general-purpose)"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
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

t_gate_refuses_antigravity() {
  # Given: no payload
  T="$(cd "$(mktemp -d)" && pwd -P)"
  # When
  run bash "$here/../gate/subagent-gate.sh" antigravity matcher
  # Then
  eq exit 64 "$code"
  eq stderr "usage: subagent-gate.sh <claude|codex> [matcher]" "$err"
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

cases=(
  "gate lets a claude checker start the explorer|t_gate_claude_checker_starts_explorer"
  "gate blocks a claude scope reviewer's start|t_gate_claude_blocks_scope_reviewer_start"
  "gate blocks a claude explorer's start|t_gate_claude_blocks_explorer_start"
  "gate lets the claude main agent start any agent|t_gate_claude_main_starts_any"
  "gate prints the claude matcher|t_gate_claude_matcher"
  "gate refuses the antigravity harness|t_gate_refuses_antigravity"
  "gate blocks a claude explorer's edit|t_gate_claude_blocks_explorer_edit"
  "gate lets the claude main agent edit|t_gate_claude_main_edits"
  "gate lets a codex checker start the explorer|t_gate_codex_checker_starts_explorer"
  "gate blocks a codex scope reviewer's start|t_gate_codex_blocks_scope_reviewer_start"
  "gate blocks a codex explorer's start|t_gate_codex_blocks_explorer_start"
  "gate blocks a codex explorer's edit|t_gate_codex_blocks_explorer_edit"
  "gate refuses a claude main agent's first T3 start of the walker|t_gate_claude_refuses_main_first_t3_walker"
  "gate refuses a codex main agent's first T3 start of the walker|t_gate_codex_refuses_main_first_t3_walker"
  "gate refuses a claude main agent's first T3 start of the logic reviewer|t_gate_claude_refuses_main_first_t3_logic_reviewer"
  "gate lets a claude main agent start the explorer in T3|t_gate_claude_main_t3_explorer"
  "gate lets a claude main agent start the walker outside T3|t_gate_claude_main_walker_outside_t3"
  "gate lets an unreadable T3 payload through|t_gate_t3_unreadable_payload"
  "gate lets a T3 start of an agent with no file through|t_gate_t3_agent_without_file"
  "gate lets a second T3 start of the walker through|t_gate_t3_second_walker_start_goes_through"
  "gate refuses the scope reviewer after it refused the walker|t_gate_t3_refuses_scope_reviewer_after_walker"
  "gate refuses a codex main agent's first start of the walker in a T3 chat log|t_gate_codex_refuses_main_in_t3_log"
  "gate lets a codex main agent start the walker outside T3|t_gate_codex_main_outside_t3_log"
)
