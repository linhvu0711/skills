# sync-harnesses.sh: the cases for this skill's sync-harnesses.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# mac: a healthy fake Mac in $T/mac, per fixtures/mac.sh. Sets T, and H, its
# home.
mac() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  bash "$here/fixtures/mac.sh" "$T/mac"
  H="$T/mac/home"
}

# sync_mac: run the check on the fake Mac.
sync_mac() { run "$T/mac/sync"; }

# json <file> <filter>: rewrite a JSON file through jq.
json() { jq "$2" "$1" > "$1.new"; mv "$1.new" "$1"; }

healthy='claude       skills 2/2 · subagents 1/1 · gates 6/6 · rules 1/1
codex        skills 2/2 · subagents 1/1 · gates 6/6 · rules 1/1
antigravity  skills 2/2 · gates 6/6 · rules 2/2
devin in T3  on · swe-2-1-medium answers'

t_sync_gate_not_wired() {
  # Given: Codex's hooks with the question gate taken out
  mac
  json "$H/.codex/hooks.json" '.hooks.UserPromptSubmit[0].hooks |= map(select(.command | contains("question-gate") | not))'
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has codex 'codex        skills 2/2 · subagents 1/1 · gates 5/6 · rules 1/1' "$out"
  has problem 'problem: codex gate question-gate is not wired in ~/.codex/hooks.json' "$out"
}

t_sync_remakes_skill_link() {
  # Given: Claude Code's link to the demo skill removed
  mac
  rm "$H/.claude/skills/demo"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  eq stdout "$healthy
fixed: linked ~/.claude/skills/demo" "$out"
}

t_sync_rewrites_subagent_file() {
  # Given: Codex's helper agent file removed
  mac
  rm "$H/.codex/agents/helper.toml"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has fixed 'fixed: wrote ~/.codex/agents/helper.toml' "$out"
  has codex 'codex        skills 2/2 · subagents 1/1 · gates 6/6 · rules 1/1' "$out"
}

t_sync_puts_back_subagent_gate() {
  # Given: Claude Code's settings with the subagent gate's entry taken out
  mac
  json "$H/.claude/settings.json" '.hooks.PreToolUse |= map(select(any(.hooks[]?; .command | contains("shared/gate/subagent-gate.sh")) | not))'
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has fixed 'fixed: wrote ~/.claude/settings.json' "$out"
  has claude 'claude       skills 2/2 · subagents 1/1 · gates 6/6 · rules 1/1' "$out"
}

t_sync_names_stale_tier_model() {
  # Given: T3's Antigravity list without the tier tables' Antigravity model
  mac
  printf '{"models":[{"slug":"gemini-4-argon"}]}\n' > "$H/.t3/caches/antigravity.json"
  before="$(cat "$T/mac/repo/skills/demo/agents/helper.md")"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has problem 'problem: shared/model-tiers.md: T3 Antigravity does not offer gemini-4-neon' "$out"
  eq agent "$before" "$(cat "$T/mac/repo/skills/demo/agents/helper.md")"
}

t_sync_devin_missing_from_t3() {
  # Given: T3 with no Devin entry at all
  mac
  json "$H/.t3/userdata/settings.json" '.providerInstances |= del(.acpRegistry_devin)'
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has devin 'devin in T3  off' "$out"
  has warn 'warn: Devin is off in T3, so these move to their next try: helper' "$out"
  [ ! -e "$T/mac/devin.calls" ] || eq devin.calls absent there
}

t_sync_names_agent_link_cannot_render() {
  # Given: a second agent with no tier line
  mac
  sed -e 's/^name: helper$/name: helper2/' -e '/^tier: 2$/d' \
    "$T/mac/repo/skills/demo/agents/helper.md" > "$T/mac/repo/skills/demo/agents/helper2.md"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has claude 'claude       skills 2/2 · subagents 1/2 · gates 6/6 · rules 1/1' "$out"
  has codex 'codex        skills 2/2 · subagents 1/2 · gates 6/6 · rules 1/1' "$out"
  has antigravity 'antigravity  skills 2/2 · gates 6/6 · rules 2/2' "$out"
  eq problems 'problem: skills/demo/agents/helper2.md:5: no tier line' "$(grep '^problem:' <<<"$out")"
}

t_sync_names_gates_beside_unread_plugin_hooks() {
  # Given: another plugin's hooks.json that is not JSON, and the personal
  # plugin with the question gate taken out
  mac
  mkdir -p "$H/.gemini/config/plugins/other"
  printf 'not json\n' > "$H/.gemini/config/plugins/other/hooks.json"
  json "$H/.gemini/config/plugins/personal/hooks.json" '.personal.PreToolUse[0].hooks |= map(select(.command | contains("question-gate") | not))'
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has antigravity 'antigravity  skills 2/2 · gates 5/6 · rules 2/2' "$out"
  has "question gate" 'problem: antigravity gate question-gate is not wired in ~/.gemini/config/plugins' "$out"
}

cases=(
  "sync names a gate that is not wired|t_sync_gate_not_wired"
  "sync remakes a missing skill link|t_sync_remakes_skill_link"
  "sync rewrites a missing subagent file|t_sync_rewrites_subagent_file"
  "sync puts back the subagent gate|t_sync_puts_back_subagent_gate"
  "sync names a tier model T3 no longer offers|t_sync_names_stale_tier_model"
  "sync takes Devin missing from T3 as off|t_sync_devin_missing_from_t3"
  "sync names an agent link.sh cannot render once|t_sync_names_agent_link_cannot_render"
  "sync names the gates beside a plugin hooks file it cannot read|t_sync_names_gates_beside_unread_plugin_hooks"
)
