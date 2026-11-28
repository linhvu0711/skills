# link.sh: the cases for scripts/link.sh and the post-commit, post-checkout,
# post-merge, and post-rewrite hooks that run it. tests/run.sh sources this
# file after lib.sh and runs its cases.

# linked [<skill>...]: repo with skills/<skill>/SKILL.md for each, and empty
# local skills folders at $T/agents, $T/claude, and $T/gskills (Antigravity),
# and one T3 Antigravity folder, $T/t3/p1.
linked() {
  repo; local n
  for n in "$@"; do mkdir -p "skills/$n"; printf -- '---\nname: %s\n---\n' "$n" > "skills/$n/SKILL.md"; done
  mkdir -p "$T/agents" "$T/claude" "$T/cagents" "$T/codex" "$T/gskills" "$T/t3/p1"
}

link_sh() { run env SKILLS_HOME="$T/agents" CLAUDE_SKILLS_HOME="$T/claude" CLAUDE_AGENTS_HOME="$T/cagents" CODEX_AGENTS_HOME="$T/codex" \
  ANTIGRAVITY_SKILLS_HOME="$T/gskills" ANTIGRAVITY_PLUGINS_HOME="$T/gplugins" T3_ANTIGRAVITY_HOME="$T/t3" \
  CLAUDE_SETTINGS_FILE="$T/claude-settings.json" CODEX_HOOKS_FILE="$T/codex-hooks.json" bash "${1:-scripts/link.sh}" "${@:2}"; }

# with_gate: this checkout's shared/gate/ in the repo, so link.sh wires it.
with_gate() { mkdir -p shared && cp -R "$scripts_dir/../shared/gate" shared/; }

t_link_links_new_skill() {
  linked demo; link_sh
  eq exit 0 "$code"
  eq stdout "$(printf 'linked %s\nlinked %s\nlinked %s\nlinked %s' "$T/agents/demo" "$T/claude/demo" "$T/gskills/demo" "$T/t3/p1/config/plugins")" "$out"
  eq "agents link" "$R/skills/demo" "$(readlink "$T/agents/demo")"
  eq "claude link" "$T/agents/demo" "$(readlink "$T/claude/demo")"
  eq "antigravity link" "$T/agents/demo" "$(readlink "$T/gskills/demo")"
  link_sh
  eq "second run" "" "$out$err"
}

t_link_follows_rename() {
  linked old; link_sh
  rm "$T/claude/old"; ln -s ../../.agents/skills/old "$T/claude/old"
  mv skills/old skills/new; link_sh
  eq exit 0 "$code"
  has stdout "unlinked $T/agents/old" "$out"
  has stdout "unlinked $T/claude/old" "$out"
  has stdout "linked $T/claude/new" "$out"
  has stdout "unlinked $T/gskills/old" "$out"
  has stdout "linked $T/gskills/new" "$out"
  eq "ls agents" new "$(ls "$T/agents")"
  eq "ls claude" new "$(ls "$T/claude")"
  eq "ls gskills" new "$(ls "$T/gskills")"
}

t_link_leaves_other_names() {
  linked demo gone; mkdir "$T/agents/demo"; ln -s "$T/elsewhere/gone" "$T/agents/gone"
  link_sh
  eq exit 0 "$code"
  has stderr "skip: $T/agents/demo is not this repo's demo" "$err"
  has stderr "skip: $T/agents/gone is a link to nothing, not made here" "$err"
  [ -d "$T/agents/demo" ] && [ ! -L "$T/agents/demo" ] || eq "agents/demo" "a folder" "changed"
  eq "gone link" "$T/elsewhere/gone" "$(readlink "$T/agents/gone")"
  eq "ls claude" "" "$(ls "$T/claude")"
}

t_link_skips_worktree() {
  linked demo; git add skills; git commit -qm skill
  git worktree add -q "$T/wt" -b wt; cd "$T/wt"; link_sh
  eq exit 0 "$code"
  eq output "" "$out$err"
  eq "ls agents" "" "$(ls "$T/agents")"
}

t_link_writes_last_try() {
  # Given: a tier-3 checker
  linked demo; agent demo helper
  sed -i.bak -e 's/^tier: 1$/tier: 3/' -e 's/^checker: no$/checker: yes/' skills/demo/agents/helper.md
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has "claude model" "model: claude-opus-5-5
effort: high" "$(cat "$T/cagents/helper.md")"
  has "codex model" 'model = "gpt-6.2-sol"
model_reasoning_effort = "medium"' "$(cat "$T/codex/helper.toml")"
}

t_link_writes_claude_form() {
  # Given: a skill with one agent file and a Codex openai.yaml
  linked demo; agent demo helper; printf 'interface: {}\n' > skills/demo/agents/openai.yaml
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/cagents/helper.md" "$out"
  [ ! -L "$T/cagents/helper.md" ] || eq "cagents/helper.md" "a file" "a link"
  eq "claude form" "$(printf '%s\n' '---' \
    '# Made by scripts/link.sh from skills/demo/agents/helper.md. Edit that file, not this one.' \
    'name: helper' 'description: Reviews one "demo" diff.' 'tools: Read, Grep, Glob, Bash' \
    'model: claude-haiku-5-5' 'effort: high' '---' 'Review the diff.' 'Match \d+ in "x".')" \
    "$(cat "$T/cagents/helper.md")"
  eq "ls cagents" helper.md "$(ls "$T/cagents")"
  link_sh
  eq "second run" "" "$out$err"
}

t_link_writes_codex_form() {
  # Given: a skill with one agent file
  linked demo; agent demo helper
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/codex/helper.toml" "$out"
  eq "codex form" "$(printf '%s\n' \
    '# Made by scripts/link.sh from skills/demo/agents/helper.md. Edit that file, not this one.' \
    'name = "helper"' 'description = "Reviews one \"demo\" diff."' 'model = "gpt-6.1-terra"' \
    'model_reasoning_effort = "low"' 'developer_instructions = """' 'Review the diff.' \
    'Match \\d+ in "x".' '"""')" "$(cat "$T/codex/helper.toml")"
  link_sh
  eq "second run" "" "$out$err"
}

t_link_leaves_other_codex_agent() {
  # Given: a Codex agent file of the user's own holds the agent's name
  linked demo; agent demo helper; printf 'name = "mine"\n' > "$T/codex/helper.toml"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stderr "skip: $T/codex/helper.toml is not this repo's helper.toml" "$err"
  eq "own file" 'name = "mine"' "$(cat "$T/codex/helper.toml")"
}

t_link_keeps_agent_on_tier_model_none() {
  # Given: an agent linked, then its tier-1 Claude model set to none
  linked demo; agent demo helper; link_sh
  awk -F '\t' -v OFS='\t' 'NR == 41 { $2 = "none" } { print }' shared/model-tiers.md > shared/model-tiers.md.new; mv shared/model-tiers.md.new shared/model-tiers.md
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stderr "skip: skills/demo/agents/helper.md:5: tier 1 for claude: none is no model it can run" "$err"
  has "cagents/helper.md" "model: claude-haiku-5-5" "$(cat "$T/cagents/helper.md")"
}

t_link_writes_codex_form_when_claude_try_fails() {
  # Given: an agent whose tier-1 Claude model is none and whose Codex model is good
  linked demo; agent demo helper
  awk -F '\t' -v OFS='\t' 'NR == 41 { $2 = "none" } { print }' shared/model-tiers.md > shared/model-tiers.md.new; mv shared/model-tiers.md.new shared/model-tiers.md
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has "codex/helper.toml" 'model = "gpt-6.1-terra"' "$(cat "$T/codex/helper.toml")"
  [ ! -e "$T/cagents/helper.md" ] || eq "cagents/helper.md" "none" "written"
}

t_link_status_names_codex_form_it_cannot_render() {
  # Given: everything linked, then the tier-1 Codex model set to none
  linked demo; agent demo helper; with_gate; link_sh
  awk -F '\t' -v OFS='\t' 'NR == 41 { $3 = "none" } { print }' shared/model-tiers.md > shared/model-tiers.md.new; mv shared/model-tiers.md.new shared/model-tiers.md
  # When
  link_sh scripts/link.sh --status
  # Then
  eq "agent lines" "$(printf 'ok\tagent\tclaude\thelper\t%s\t%s\n' "$T/cagents/helper.md" "$T/cagents"
    printf 'stale\tagent\tcodex\thelper\t%s\t%s\t%s\n' "$T/codex/helper.toml" "$T/codex" "skills/demo/agents/helper.md:5: tier 1 for codex: none is no model it can run")" \
    "$(awk -F '\t' '$2 == "agent"' <<<"$out")"
}

t_link_removes_renamed_agent_forms() {
  # Given: an agent written once into every harness
  linked demo; agent demo helper; link_sh
  # When: it is renamed
  sed 's/^name: helper$/name: aide/' skills/demo/agents/helper.md > skills/demo/agents/aide.md
  rm skills/demo/agents/helper.md; link_sh
  # Then
  eq exit 0 "$code"
  has stdout "removed $T/cagents/helper.md" "$out"
  has stdout "removed $T/codex/helper.toml" "$out"
  eq "ls cagents" aide.md "$(ls "$T/cagents")"
  eq "ls codex" aide.toml "$(ls "$T/codex")"
}

t_link_writes_shared_agent_forms() {
  # Given: the shared explorer file
  linked demo; with_tiers; mkdir -p shared/agents
  printf -- '---\n%s\n---\nFind the fact.\n' "${full_agent/name: helper/name: explorer}" > shared/agents/explorer.md
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/cagents/explorer.md" "$out"
  has stdout "wrote $T/codex/explorer.toml" "$out"
  eq "mark" "# Made by scripts/link.sh from shared/agents/explorer.md. Edit that file, not this one." \
    "$(sed -n 2p "$T/cagents/explorer.md")"
  link_sh
  eq "second run" "" "$out$err"
}

t_link_leaves_other_agent() {
  # Given: a file of the user's own holds the agent's name
  linked demo; agent demo helper; printf 'mine\n' > "$T/cagents/helper.md"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stderr "skip: $T/cagents/helper.md is not this repo's helper.md" "$err"
  eq "own file" mine "$(cat "$T/cagents/helper.md")"
}

t_link_adds_gate_to_claude_settings() {
  # Given: a settings file with a key and a hook of the user's own
  linked demo; with_gate
  printf '%s' '{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"mine.sh"}]}]}}' > "$T/claude-settings.json"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/claude-settings.json" "$out"
  eq settings '{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"mine.sh"}]},{"matcher":"Agent|Task|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash '"'$R/shared/gate/subagent-gate.sh'"' claude","timeout":5}]}]}}' \
    "$(jq -c . "$T/claude-settings.json")"
}

t_link_adds_gate_to_codex_hooks_once() {
  # Given: no codex hooks file
  linked demo; with_gate
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  eq hooks '{"hooks":{"PreToolUse":[{"matcher":"spawn_agent|Agent|apply_patch|Edit|Write","hooks":[{"type":"command","command":"bash '"'$R/shared/gate/subagent-gate.sh'"' codex","timeout":5}]}]}}' \
    "$(jq -c . "$T/codex-hooks.json")"
  local before; before="$(cat "$T/codex-hooks.json")"
  link_sh
  eq "second run" "" "$out$err"
  eq "same file" "$before" "$(cat "$T/codex-hooks.json")"
}

t_link_keeps_hook_in_gate_group() {
  # Given: an old gate command and a hook of the user's own in one group
  linked demo; with_gate
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Agent","hooks":[{"type":"command","command":"bash /old/shared/gate/subagent-gate.sh claude"},{"type":"command","command":"audit.sh"}]}]}}' > "$T/claude-settings.json"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  eq settings '{"hooks":{"PreToolUse":[{"matcher":"Agent","hooks":[{"type":"command","command":"audit.sh"}]},{"matcher":"Agent|Task|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash '"'$R/shared/gate/subagent-gate.sh'"' claude","timeout":5}]}]}}' \
    "$(jq -c . "$T/claude-settings.json")"
}

t_link_writes_through_linked_hook_file() {
  # Given: the settings path is a link to a file in a dotfiles folder
  linked demo; with_gate; mkdir -p "$T/dot"
  printf '%s' '{"model":"opus"}' > "$T/dot/settings.json"; ln -s "$T/dot/settings.json" "$T/claude-settings.json"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  eq link "$T/dot/settings.json" "$(readlink "$T/claude-settings.json")"
  eq model opus "$(jq -r .model "$T/dot/settings.json")"
  eq "gate in target" 1 "$(jq '.hooks.PreToolUse | length' "$T/dot/settings.json")"
}

# old_plugin: the "skills" Antigravity plugin an earlier link.sh wrote, with
# helper's agent file, the plugin.json, and the gate's hooks.json.
old_plugin() {
  mkdir -p "$T/gplugins/skills/agents"
  printf -- '---\n# Made by scripts/link.sh from skills/demo/agents/helper.md. Edit that file, not this one.\nname: helper\n---\n' \
    > "$T/gplugins/skills/agents/helper.md"
  printf '%s\n' '{' '  "name": "skills",' \
    '  "description": "The skill agents of the skills repo, written by its scripts/link.sh."' '}' > "$T/gplugins/skills/plugin.json"
  printf '%s' '{"subagent-gate":{"PreToolUse":[]}}' > "$T/gplugins/skills/hooks.json"
}

t_link_writes_no_antigravity_plugin() {
  # Given: a skill with one agent file, and the gate
  linked demo; agent demo helper; with_gate
  # When
  link_sh
  # Then
  eq plugins "" "$(ls -A "$T/gplugins")"
}

# no_jq: $T/nojq, a bin folder with every command on PATH but jq.
no_jq() {
  local d f n dirs; mkdir -p "$T/nojq"; IFS=: read -ra dirs <<<"$PATH"
  for d in "${dirs[@]}"; do
    for f in "$d"/*; do
      n="$(basename "$f")"
      [ -x "$f" ] && [ "$n" != jq ] && [ ! -e "$T/nojq/$n" ] || continue
      ln -s "$f" "$T/nojq/$n"
    done
  done
}

t_link_stops_without_jq() {
  # Given: the old skills plugin, and no jq on PATH
  linked demo; agent demo helper; with_gate; old_plugin; no_jq
  # When
  PATH="$T/nojq" link_sh
  # Then
  eq exit 1 "$code"
  has stderr 'stop: link.sh needs jq to read and write hook files; install it, as with brew install jq' "$err"
  eq files "$T/gplugins/skills/agents/helper.md
$T/gplugins/skills/hooks.json
$T/gplugins/skills/plugin.json" "$(find "$T/gplugins/skills" -type f | sort)"
}

t_link_links_plugins_into_each_t3() {
  # Given: two T3 Antigravity folders and no plugins folder yet
  linked demo; mkdir -p "$T/t3/p2/config"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  eq "p1 plugins" "$T/gplugins" "$(readlink "$T/t3/p1/config/plugins")"
  eq "p2 plugins" "$T/gplugins" "$(readlink "$T/t3/p2/config/plugins")"
  [ -d "$T/gplugins" ] || eq "gplugins" "a folder" "missing"
  link_sh
  eq "second run" "" "$out$err"
}

# status_lines <line>...: the lines, each with its spaces read as tabs.
status_lines() { printf '%s\n' "$@" | tr ' ' '\t'; }

t_link_status_names_every_target_ok() {
  # Given: a skill, an agent, and the gate, all linked
  linked demo; agent demo helper; with_gate; link_sh
  # When
  link_sh scripts/link.sh --status
  # Then
  eq exit 0 "$code"
  eq stderr "" "$err"
  eq stdout "$(status_lines "ok skill shared demo $T/agents/demo $T/agents" "ok skill claude demo $T/claude/demo $T/claude" \
    "ok skill antigravity demo $T/gskills/demo $T/gskills" "ok agent claude helper $T/cagents/helper.md $T/cagents" \
    "ok agent codex helper $T/codex/helper.toml $T/codex" "ok gate claude subagent-gate $T/claude-settings.json $T" \
    "ok gate codex subagent-gate $T/codex-hooks.json $T" "ok plugins antigravity plugins $T/t3/p1/config/plugins $T/t3/p1")" "$out"
}

t_link_status_names_missing_and_held() {
  # Given: everything linked, then Claude Code's skill link gone, a Codex
  # agent file of the user's own, and Claude Code settings that are not JSON
  linked demo; agent demo helper; with_gate; link_sh
  rm "$T/claude/demo"; printf 'mine\n' > "$T/codex/helper.toml"; printf 'not json\n' > "$T/claude-settings.json"
  # When
  link_sh scripts/link.sh --status
  # Then
  eq "lines 2, 5, 6" "$(printf 'missing\tskill\tclaude\tdemo\t%s\t%s\n' "$T/claude/demo" "$T/claude"
    printf 'stale\tagent\tcodex\thelper\t%s\t%s\t%s\n' "$T/codex/helper.toml" "$T/codex" "$T/codex/helper.toml is not this repo's helper.toml"
    printf 'stale\tgate\tclaude\tsubagent-gate\t%s\t%s\t%s\n' "$T/claude-settings.json" "$T" "$T/claude-settings.json is not JSON")" \
    "$(sed -n '2p;5p;6p' <<<"$out")"
}

t_link_status_names_agent_it_cannot_render() {
  # Given: everything linked, then a second agent with no tier line
  linked demo; agent demo helper; with_gate; link_sh
  agent demo helper2; grep -v '^tier: 1$' skills/demo/agents/helper2.md > skills/demo/agents/helper2.md.new; mv skills/demo/agents/helper2.md.new skills/demo/agents/helper2.md
  # When
  link_sh scripts/link.sh --status
  # Then
  eq "helper2 lines" "$(for l in "claude $T/cagents/helper2.md $T/cagents" "codex $T/codex/helper2.toml $T/codex"; do
      read -r h p f <<<"$l"; printf 'missing\tagent\t%s\thelper2\t%s\t%s\tskills/demo/agents/helper2.md:6: no tier line\n' "$h" "$p" "$f"; done)" \
    "$(grep helper2 <<<"$out")"
}

t_link_status_names_held_link_under_held_shared() {
  # Given: everything linked, then folders of the user's own in place of the
  # shared skill link and of Claude Code's
  linked demo; link_sh
  rm "$T/agents/demo" "$T/claude/demo"; mkdir "$T/agents/demo" "$T/claude/demo"
  # When
  link_sh scripts/link.sh --status
  # Then
  eq claude "$(printf 'stale\tskill\tclaude\tdemo\t%s\t%s\t%s' "$T/claude/demo" "$T/claude" "$T/claude/demo is not this repo's demo")" \
    "$(awk -F '\t' '$2 == "skill" && $3 == "claude"' <<<"$out")"
}

t_link_status_names_no_holder_for_own_dangling_link() {
  # Given: everything linked, then the shared skill link pointed at a folder
  # that is gone
  linked demo; link_sh
  rm "$T/agents/demo"; ln -s "$T/gone/skills/demo" "$T/agents/demo"
  # When
  link_sh scripts/link.sh --status
  # Then
  eq "skill lines" "$(printf 'stale\tskill\tshared\tdemo\t%s\t%s\t%s\n' "$T/agents/demo" "$T/agents" "$T/agents/demo is a link to nothing, not made here"
    status_lines "stale skill claude demo $T/claude/demo $T/claude" "stale skill antigravity demo $T/gskills/demo $T/gskills")" \
    "$(awk -F '\t' '$2 == "skill"' <<<"$out")"
}

t_link_status_names_no_holder_for_relative_dangling_link() {
  # Given: everything linked, then Claude Code's skill link in the relative
  # form, pointing to nothing
  linked demo; link_sh
  rm "$T/claude/demo"; ln -s ../../.agents/skills/demo "$T/claude/demo"
  # When
  link_sh scripts/link.sh --status
  # Then
  eq claude "$(status_lines "stale skill claude demo $T/claude/demo $T/claude")" \
    "$(awk -F '\t' '$2 == "skill" && $3 == "claude"' <<<"$out")"
}

t_link_status_names_no_holder_for_dangling_t3_plugins_link() {
  # Given: everything linked, then the plugins folder gone
  linked demo; link_sh
  rm -rf "$T/gplugins"
  # When
  link_sh scripts/link.sh --status
  # Then
  eq plugins "$(status_lines "stale plugins antigravity plugins $T/t3/p1/config/plugins $T/t3/p1")" \
    "$(awk -F '\t' '$2 == "plugins"' <<<"$out")"
}

t_link_status_writes_nothing() {
  # Given: everything linked, then Claude Code's skill link gone
  linked demo; agent demo helper; with_gate; link_sh
  rm "$T/claude/demo"
  # When
  link_sh scripts/link.sh --status
  # Then
  [ ! -e "$T/claude/demo" ] && [ ! -L "$T/claude/demo" ] || eq "claude/demo" "absent" "present"
}

t_hooks_link_committed_skill() {
  linked; git config core.hooksPath scripts/hooks; export SKILLS_HOME="$T/agents" CLAUDE_SKILLS_HOME="$T/claude" CLAUDE_AGENTS_HOME="$T/cagents" ANTIGRAVITY_SKILLS_HOME="$T/gskills" \
    ANTIGRAVITY_PLUGINS_HOME="$T/gplugins" T3_ANTIGRAVITY_HOME="$T/t3"
  local main; main="$(git branch --show-current)"
  mkdir -p skills/demo; printf -- '---\nname: demo\ndescription: d\n---\n' > skills/demo/SKILL.md
  printf '# demo\n## Use it when\n## What you get\n## Needs\n## Fits with\n' > skills/demo/README.md
  git add skills; git commit -qm demo
  eq "after commit" "$R/skills/demo" "$(readlink "$T/agents/demo")"
  git checkout -q -b side HEAD~1
  eq "after checkout" "" "$(ls "$T/agents")"
  git merge -q "$main"
  eq "after merge" "$T/agents/demo" "$(readlink "$T/claude/demo")"
}

cases=(
  "link links a new skill into every folder|t_link_links_new_skill"
  "link follows a renamed skill|t_link_follows_rename"
  "link leaves a name something else holds|t_link_leaves_other_names"
  "link does nothing in a worktree|t_link_skips_worktree"
  "link writes a skill agent's Claude Code form|t_link_writes_claude_form"
  "link keeps an agent whose tier model is none|t_link_keeps_agent_on_tier_model_none"
  "link writes the Codex form when the Claude try fails|t_link_writes_codex_form_when_claude_try_fails"
  "link status names a Codex form it cannot render|t_link_status_names_codex_form_it_cannot_render"
  "link removes the forms of a renamed skill agent|t_link_removes_renamed_agent_forms"
  "link leaves an agent file it did not make|t_link_leaves_other_agent"
  "link adds the gate to claude settings and keeps the rest|t_link_adds_gate_to_claude_settings"
  "link adds the gate to codex hooks once|t_link_adds_gate_to_codex_hooks_once"
  "link keeps a hook that shares the gate's group|t_link_keeps_hook_in_gate_group"
  "link writes through a linked hook file|t_link_writes_through_linked_hook_file"
  "link writes a tier-3 agent on each harness's own last try|t_link_writes_last_try"
  "link writes a shared agent's two forms|t_link_writes_shared_agent_forms"
  "link writes a skill agent's Codex form|t_link_writes_codex_form"
  "link leaves a Codex agent file it did not make|t_link_leaves_other_codex_agent"
  "link writes no Antigravity plugin|t_link_writes_no_antigravity_plugin"
  "link stops when jq is missing|t_link_stops_without_jq"
  "link links the plugins folder into each T3 Antigravity folder|t_link_links_plugins_into_each_t3"
  "link status names every target ok|t_link_status_names_every_target_ok"
  "link status names missing and held targets|t_link_status_names_missing_and_held"
  "link status writes nothing|t_link_status_writes_nothing"
  "link status names each file of an agent it cannot render|t_link_status_names_agent_it_cannot_render"
  "link status names a held Claude Code link under a held shared link|t_link_status_names_held_link_under_held_shared"
  "link status names no holder for its own dangling link|t_link_status_names_no_holder_for_own_dangling_link"
  "link status names no holder for Claude Code's relative dangling link|t_link_status_names_no_holder_for_relative_dangling_link"
  "link status names no holder for a T3 link to a missing plugins folder|t_link_status_names_no_holder_for_dangling_t3_plugins_link"
  "hooks link a skill on commit, checkout, and merge|t_hooks_link_committed_skill"
)
