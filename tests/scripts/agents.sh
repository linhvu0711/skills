# agents.sh: the cases for scripts/agents.sh. tests/run.sh sources this file
# after lib.sh and runs its cases.

t_agents_lists_tools() {
  # Given: an agent whose tools line names the Agent tool
  repo; agent demo helper
  sed -i.bak 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Grep, Glob, Bash, Agent/' skills/demo/agents/helper.md
  # When
  run bash scripts/agents.sh tools < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "Read Grep Glob Bash Agent" "$out"
}

t_agents_tries_lists_checker() {
  # Given: a tier-3 checker
  repo; agent demo helper
  sed -i.bak -e 's/^tier: 1$/tier: 3/' -e 's/^checker: no$/checker: yes/' skills/demo/agents/helper.md
  # When
  run bash scripts/agents.sh tries claude < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf '%s\n' 'antigravity gemini-4-neon medium' 'claude claude-opus-5-5 high')" "$out"
}

t_agents_tries_follow_tier_cell() {
  # Given: two tier-2 agents, one a checker, and the tier-2 Claude cell
  # changed to claude-opus-5-5 medium
  repo; agent demo helper; agent demo helper2
  sed -i.bak 's/^tier: 1$/tier: 2/' skills/demo/agents/helper.md skills/demo/agents/helper2.md
  sed -i.bak 's/^checker: no$/checker: yes/' skills/demo/agents/helper2.md
  sed -i.bak "s/^2$(printf '\t')claude-sonnet-5-5 high$(printf '\t')/2$(printf '\t')claude-opus-5-5 medium$(printf '\t')/" shared/model-tiers.md
  want="$(printf '%s\n' 'devin swe-2-1-medium high' 'claude claude-opus-5-5 medium')"
  # When
  run bash scripts/agents.sh tries claude < skills/demo/agents/helper.md
  # Then
  eq "helper stdout" "$want" "$out"
  run bash scripts/agents.sh tries claude < skills/demo/agents/helper2.md
  eq "helper2 stdout" "$want" "$out"
}

t_agents_start_names_first_try() {
  # Given: a tier-2 agent, whose first try under Claude is Devin
  repo; agent demo helper
  sed -i.bak 's/^tier: 1$/tier: 2/' skills/demo/agents/helper.md
  # When
  run bash scripts/agents.sh start claude < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "t3 devin swe-2-1-medium high" "$out"
}

t_agents_start_by_name_when_first_try_is_harness() {
  # Given: a tier-1 agent, whose only try under Codex is Codex
  repo; agent demo helper
  # When
  run bash scripts/agents.sh start codex < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "name" "$out"
}

cases=(
  "agents.sh lists an agent's tools|t_agents_lists_tools"
  "agents.sh lists a tier-3 checker's try list|t_agents_tries_lists_checker"
  "agents.sh moves every agent of a tier when one cell changes|t_agents_tries_follow_tier_cell"
  "agents.sh start names a tier-2 agent's first try|t_agents_start_names_first_try"
  "agents.sh start says name when the first try is the harness|t_agents_start_by_name_when_first_try_is_harness"
)
