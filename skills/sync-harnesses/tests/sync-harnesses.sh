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

cases=(
  "sync reports every harness green on a healthy Mac|t_sync_healthy"
  "sync names a gate that is not wired|t_sync_gate_not_wired"
  "sync leaves a missing T3 rules link to T3|t_sync_t3_rules_link_left_to_t3"
)
