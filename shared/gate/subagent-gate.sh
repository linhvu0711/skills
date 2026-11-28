#!/usr/bin/env bash
# subagent-gate.sh: the subagent gate. Claude Code and Codex run it before a
# tool call, with the call's hook payload on stdin.
#
#   subagent-gate.sh <claude|codex>            < payload
#   subagent-gate.sh <claude|codex> matcher
#
# The rules, read from the agent files through scripts/agents.sh tools, so
# no second list of agent names exists here:
#   - The main agent is blocked once per chat and helper in T3, when the
#     helper's first try is not its harness.
#   - A subagent may start another only when its agent file lists the Agent
#     tool, and only a shared agent, one in shared/agents/. Neither of those
#     lists Agent, so nesting stops at two levels.
#   - A subagent whose agent file lists neither Edit nor Write may not use a
#     file edit tool. An agent with no file here is not checked.
#
# Prints one deny line in the harness's own shape, or nothing to allow, and
# exits 0. `matcher` prints the harness's hook matcher: every tool name the
# gate reads, joined by `|`; scripts/link.sh asks it, so the two never
# drift. A bad argument: the usage line on stderr, exit 64.
#
# No set -e: a payload jq cannot read prints nothing and lets the call
# through, as the old gate did, so a broken gate never stops the main work.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$here/../.."
. "$here/../die.sh"
usage='usage: subagent-gate.sh <claude|codex> [matcher]'

harness="${1:-}"
case "$harness" in
  claude) start_tools="Agent Task"; edit_tools="Edit Write MultiEdit NotebookEdit"
    target_field=subagent_type; default_target=general-purpose ;;
  codex) start_tools="spawn_agent Agent"; edit_tools="apply_patch Edit Write"
    target_field=agent_type; default_target=default ;;
  *) die_usage "$usage" ;;
esac
case "${2-}" in
  matcher) [ $# -eq 2 ] || die_usage "$usage"; printf '%s\n' "$start_tools $edit_tools" | tr ' ' '|'; exit 0 ;;
  '') [ $# -eq 1 ] || die_usage "$usage" ;;
  *) die_usage "$usage" ;;
esac

payload="$(cat)"
us=$'\x1f'

# read_hook: caller, tool name, target, chat id, and chat log path, one unit
# separator apart. The caller is empty for the main agent.
read_hook() {
  jq -r --arg f "$target_field" --arg d "$default_target" \
    '[(if (.agent_id // "") != "" then .agent_type // "" else "" end),
      .tool_name // "", .tool_input[$f] // $d, .session_id // "", .transcript_path // ""] | join("\u001f")' <<<"$payload"
}
fields="$(read_hook 2>/dev/null)" || exit 0
IFS="$us" read -r caller tool target session log <<<"$fields"

in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
action=other
in_list "$tool" "$start_tools" && action=start
in_list "$tool" "$edit_tools" && action=edit

# agent_file <name>: the agent's file in this repo, or nothing.
agent_file() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
  local f
  for f in "$repo/shared/agents/$1.md" "$repo"/skills/*/agents/"$1".md; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
}
tools_of() { bash "$repo/scripts/agents.sh" tools < "$1" 2>/dev/null; }

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# in_t3: whether this chat runs in T3. T3 gives Claude Code its thread id, but starts Codex through one shared app server without it,
# so a Codex chat is read from its log, whose first line names the app that
# opened it.
in_t3() {
  [ -n "${T3CODE_THREAD_ID:-}" ] && return 0
  # T3 starts Codex with no thread id, so the log's first originator names T3, see #455
  [ "$harness" = codex ] && [ -f "$log" ] && \
    [ "$(head -1 "$log" | jq -r '.payload.originator // ""' 2>/dev/null)" = "T3 Code" ]
}

if [ -z "$caller" ]; then
  [ "$action" = start ] && in_t3 || exit 0
  f="$(agent_file "$target")"
  [ -n "$f" ] || exit 0
  home="$(bash "$repo/scripts/agents.sh" start "$harness" < "$f" 2>/dev/null)"
  case "$home" in "t3 "*) ;; *) exit 0 ;; esac
  # One mkdir is both the check and the note, so of two starts at once only
  # one is refused. The user id keeps another account's folder in a shared
  # /tmp from blocking the note.
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
  notes="${TMPDIR:-/tmp}/subagent-gate-$(id -u)/$session"
  mkdir -p "$notes" 2>/dev/null && mkdir "$notes/$target" 2>/dev/null || exit 0
  deny "Blocked by the subagent gate: in T3, start $target on its first try, ${home#t3 }, through T3's delegate_task, per shared/facts.md § Skill agents. When no try can run, start it by name again: it then runs on its last try."
fi

if [ "$action" = start ]; then
  f="$(agent_file "$caller")"
  if [ -n "$f" ] && in_list Agent "$(tools_of "$f")" \
     && [[ "$target" =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "$repo/shared/agents/$target.md" ]; then
    exit 0
  fi
  deny "Blocked by the subagent gate: $caller may not start $target. Only an agent whose file lists the Agent tool may start a subagent, and only the explorer or the runner, so nesting stops at two levels."
fi
if [ "$action" = edit ]; then
  f="$(agent_file "$caller")"
  [ -n "$f" ] || exit 0
  t="$(tools_of "$f")"
  in_list Edit "$t" || in_list Write "$t" || \
    deny "Blocked by the subagent gate: $caller may not use a file edit tool, since its agent file lists no Edit or Write tool."
fi
exit 0
