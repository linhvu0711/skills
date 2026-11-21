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

t_sync_names_stale_home_model() {
  # Given: T3's Antigravity list without the helper's home model
  mac
  printf '{"models":[{"slug":"gemini-4-argon"}]}\n' > "$H/.t3/caches/antigravity.json"
  before="$(cat "$T/mac/repo/skills/demo/agents/helper.md")"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has problem 'problem: skills/demo/agents/helper.md: home for antigravity: T3 Antigravity does not offer gemini-4-neon' "$out"
  eq agent "$before" "$(cat "$T/mac/repo/skills/demo/agents/helper.md")"
}

t_sync_names_stale_backup_model() {
  # Given: Codex's own list without the helper's Codex backup
  mac
  printf '{"models":[]}' > "$H/.codex/models_cache.json"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has problem 'problem: skills/demo/agents/helper.md: backup for codex: Codex does not offer gpt-6-luna' "$out"
}

t_sync_skips_models_of_place_off() {
  # Given: Antigravity off in T3, its list empty
  mac
  sed -i.bak '/Antigravity/s/true/false/' "$H/.t3/userdata/settings.json"
  printf '{"models":[]}\n' > "$H/.t3/caches/antigravity.json"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has skip 'skip: Antigravity is off in T3, so its home models are not checked' "$out"
  lacks problem 'problem:' "$out"
}

t_sync_warns_devin_off() {
  # Given: Devin off in T3
  mac
  sed -i.bak '/Devin/s/true/false/' "$H/.t3/userdata/settings.json"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has devin 'devin in T3  off' "$out"
  has warn 'warn: Devin is off in T3, so these run on their backup: helper' "$out"
  [ ! -e "$T/mac/devin.calls" ] || eq devin.calls absent there
}

t_sync_warns_swe2_refused() {
  # Given: Devin refuses every model
  mac
  touch "$H/.devin-refuse"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has devin 'devin in T3  on · swe-2-high refused' "$out"
  has warn "warn: swe-2-high refused (Error: Unknown model: 'swe-2-high'), so these run on their backup: helper" "$out"
}

t_sync_skips_harness_not_installed() {
  # Given: no Antigravity CLI and no GEMINI.md
  mac
  rm "$H/bin/agy" "$H/.gemini/GEMINI.md"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has antigravity 'antigravity  skipped: not installed' "$out"
  lacks problem 'problem: antigravity' "$out"
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
  has warn 'warn: Devin is off in T3, so these run on their backup: helper' "$out"
  [ ! -e "$T/mac/devin.calls" ] || eq devin.calls absent there
}

t_sync_blocked_skill_link_once() {
  # Given: a folder where Claude Code's demo skill link should be
  mac
  rm "$H/.claude/skills/demo"
  mkdir "$H/.claude/skills/demo"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has claude 'claude       skills 1/2 · subagents 1/1 · gates 6/6 · rules 1/1' "$out"
  eq problems "problem: ~/.claude/skills/demo is not this repo's demo" "$(grep '^problem:' <<<"$out")"
}

t_sync_settings_not_json_once() {
  # Given: Claude Code's settings that are not JSON
  mac
  printf 'not json\n' > "$H/.claude/settings.json"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  eq problems 'problem: ~/.claude/settings.json is not JSON' "$(grep '^problem:' <<<"$out")"
}

t_sync_rules_need_shared_file() {
  # Given: no shared rules file
  mac
  rm "$H/.agents/rules/shared.md"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has claude 'claude       skills 2/2 · subagents 1/1 · gates 6/6 · rules 0/1' "$out"
  has codex 'codex        skills 2/2 · subagents 1/1 · gates 6/6 · rules 0/1' "$out"
}

t_sync_absent_harness_skips_backups() {
  # Given: no Codex CLI, and a Codex model list without the helper's backup
  mac
  rm "$H/bin/codex"
  printf '{"models":[]}' > "$H/.codex/models_cache.json"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  has codex 'codex        skipped: not installed' "$out"
  lacks problem 'problem:' "$out"
}

t_sync_names_shared_skill_blocker() {
  # Given: no Codex CLI, and a folder where the shared demo skill link should be
  mac
  rm "$H/bin/codex" "$H/.agents/skills/demo" "$H/.claude/skills/demo"
  mkdir "$H/.agents/skills/demo"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has problem "problem: ~/.agents/skills/demo is not this repo's demo" "$out"
}

t_sync_t3_rules_links_need_shared_file() {
  # Given: no shared rules file, and T3's GEMINI.md link in place
  mac
  rm "$H/.agents/rules/shared.md"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has antigravity 'antigravity  skills 2/2 · subagents 1/1 · gates 7/7 · rules 0/2' "$out"
}

t_sync_linked_settings_not_json_once() {
  # Given: Claude Code's settings, a link to a file that is not JSON
  mac
  printf 'not json\n' > "$H/real-settings.json"
  ln -sf "$H/real-settings.json" "$H/.claude/settings.json"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  eq problems 'problem: ~/real-settings.json is not JSON' "$(grep '^problem:' <<<"$out")"
}

t_sync_names_stale_second_home() {
  # Given: the helper's Claude home lists Devin Neon second, a model T3's Devin
  # list lacks
  mac
  sed -i.bak 's/^  claude: devin swe-2-high high$/  claude: devin swe-2-high high, devin gemini-4-neon-high high/' \
    "$T/mac/repo/skills/demo/agents/helper.md"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  has problem 'problem: skills/demo/agents/helper.md: home 2 for claude: T3 Devin does not offer gemini-4-neon-high' "$out"
  eq devin 'devin in T3  on · swe-2-high answers' "$(grep '^devin in T3' <<<"$out")"
  lacks calls gemini-4-neon-high "$(cat "$T/mac/devin.calls")"
}

t_sync_linked_settings_into_absent_harness() {
  # Given: no Codex CLI, and Claude Code's settings a link to a file under
  # ~/.codex that is not JSON
  mac
  rm "$H/bin/codex"
  printf 'not json\n' > "$H/.codex/shared-settings.json"
  ln -sf "$H/.codex/shared-settings.json" "$H/.claude/settings.json"
  # When
  sync_mac
  # Then
  eq exit 1 "$code"
  eq problems 'problem: ~/.codex/shared-settings.json is not JSON' "$(grep '^problem:' <<<"$out")"
}

t_sync_warns_next_home_when_devin_off() {
  # Given: Devin off in T3, and the helper's Claude home lists Antigravity after
  # Devin
  mac
  sed -i.bak '/Devin/s/true/false/' "$H/.t3/userdata/settings.json"
  sed -i.bak 's/^  claude: devin swe-2-high high$/  claude: devin swe-2-high high, antigravity gemini-4-neon high/' \
    "$T/mac/repo/skills/demo/agents/helper.md"
  # When
  sync_mac
  # Then
  eq exit 0 "$code"
  eq warns 'warn: Devin is off in T3, so these move to their next home: helper' "$(grep '^warn:' <<<"$out")"
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
  "sync names a home model T3 no longer offers|t_sync_names_stale_home_model"
  "sync names a backup model Codex no longer offers|t_sync_names_stale_backup_model"
  "sync skips the home models of a place that is off|t_sync_skips_models_of_place_off"
  "sync warns when Devin is off in T3|t_sync_warns_devin_off"
  "sync warns when SWE-2 is refused|t_sync_warns_swe2_refused"
  "sync skips a harness that is not installed|t_sync_skips_harness_not_installed"
  "sync takes Devin missing from T3 as off|t_sync_devin_missing_from_t3"
  "sync names a blocked skill link once|t_sync_blocked_skill_link_once"
  "sync names settings that are not JSON once|t_sync_settings_not_json_once"
  "sync counts rules only with the shared file|t_sync_rules_need_shared_file"
  "sync skips the backups of a harness not installed|t_sync_absent_harness_skips_backups"
  "sync names a blocked shared skill link without Codex|t_sync_names_shared_skill_blocker"
  "sync counts T3 rules links only with the shared file|t_sync_t3_rules_links_need_shared_file"
  "sync names linked settings that are not JSON once|t_sync_linked_settings_not_json_once"
  "sync names a second home model T3 no longer offers|t_sync_names_stale_second_home"
  "sync names linked settings under a harness not installed|t_sync_linked_settings_into_absent_harness"
  "sync warns of the next home when Devin is off|t_sync_warns_next_home_when_devin_off"
)
