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
antigravity  skills 2/2 · subagents 1/1 · gates 7/7 · rules 2/2
devin in T3  on · swe-2-high answers'

t_sync_healthy() {
  # Given: a healthy fake Mac
  mac
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  eq stdout "$healthy" "$out"
}

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

t_sync_t3_rules_link_left_to_t3() {
  # Given: T3's Antigravity folder with no GEMINI.md link
  mac
  rm "$H/.t3/userdata/providers/antigravity/p1/GEMINI.md"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has antigravity 'antigravity  skills 2/2 · subagents 1/1 · gates 7/7 · rules 1/2' "$out"
  has problem 'problem: antigravity rules: ~/.t3/userdata/providers/antigravity/p1 has no GEMINI.md link: T3 makes it at the next Antigravity chat' "$out"
  [ ! -e "$H/.t3/userdata/providers/antigravity/p1/GEMINI.md" ] && [ ! -L "$H/.t3/userdata/providers/antigravity/p1/GEMINI.md" ] \
    || eq GEMINI.md absent there
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

t_sync_links_plugins_new_t3_folder() {
  # Given: a new private Antigravity folder from T3, with T3's GEMINI.md link
  mac
  mkdir -p "$H/.t3/userdata/providers/antigravity/p2"
  ln -s "$H/.gemini/GEMINI.md" "$H/.t3/userdata/providers/antigravity/p2/GEMINI.md"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has fixed 'fixed: linked ~/.t3/userdata/providers/antigravity/p2/config/plugins' "$out"
  has antigravity 'antigravity  skills 2/2 · subagents 1/1 · gates 7/7 · rules 3/3' "$out"
}

t_sync_names_hand_made_subagent() {
  # Given: Claude Code's helper agent file written by hand
  mac
  printf 'hand made\n' > "$H/.claude/agents/helper.md"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has claude 'claude       skills 2/2 · subagents 0/1 · gates 6/6 · rules 1/1' "$out"
  has problem "problem: ~/.claude/agents/helper.md is not this repo's helper.md" "$out"
  eq file 'hand made' "$(cat "$H/.claude/agents/helper.md")"
}

t_sync_names_blocked_plugins_link() {
  # Given: a folder where T3's Antigravity plugins link should be
  mac
  rm "$H/.t3/userdata/providers/antigravity/p1/config/plugins"
  mkdir "$H/.t3/userdata/providers/antigravity/p1/config/plugins"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has problem "problem: ~/.t3/userdata/providers/antigravity/p1/config/plugins is not this repo's plugins" "$out"
}

t_sync_second_run_fixes_nothing() {
  # Given: one run that remade Claude Code's demo link
  mac
  rm "$H/.claude/skills/demo"
  "$T/mac/sync" >/dev/null
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  eq stdout "$healthy" "$out"
}

cases=(
  "sync reports every harness green on a healthy Mac|t_sync_healthy"
  "sync names a gate that is not wired|t_sync_gate_not_wired"
  "sync leaves a missing T3 rules link to T3|t_sync_t3_rules_link_left_to_t3"
  "sync remakes a missing skill link|t_sync_remakes_skill_link"
  "sync rewrites a missing subagent file|t_sync_rewrites_subagent_file"
  "sync puts back the subagent gate|t_sync_puts_back_subagent_gate"
  "sync links plugins into a new T3 Antigravity folder|t_sync_links_plugins_new_t3_folder"
  "sync names a hand-made subagent file|t_sync_names_hand_made_subagent"
  "sync names a blocked T3 plugins link|t_sync_names_blocked_plugins_link"
  "sync a second run fixes nothing|t_sync_second_run_fixes_nothing"
)
