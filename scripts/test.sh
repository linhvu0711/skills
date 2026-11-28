#!/usr/bin/env bash
# test.sh: the tests for check.sh, the pre-commit and commit-msg hooks,
# adopt.sh, link.sh and the hooks that run it. It sources test-lib.sh, the
# helpers, the one fake gh, and the fake curl that every case shares, starts
# its own cases, then sources each skills/*/tests/*.sh and shared/tests/*.sh
# in turn and starts that file's cases.
#
#   test.sh
#
# Each case runs as a background job, one per CPU core at a time. It starts in
# an empty temp folder with set -e on and its own fake home, builds its own git
# repo in a temp folder, copies this scripts/ folder in, and runs the command
# there. Each case's temp folders go when the case ends. Every leak string
# below is joined from two halves at runtime, so this file holds nothing
# check.sh flags.
#
# Prints `ok <case>` or `FAIL <case>: <why>` per case, in case order, then
# `<p> passed, <f> failed`. Exit 1 when any case failed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$here/test-lib.sh"
mac_home="/Us""ers/alice"
linux_home="/ho""me/bob"
email="alice""@""example.com"
word="zebra""corn"; Word="Zebra""corn"

# hooked [<word>...]: repo, with the pre-commit hook on and, when words are
# given, a private word list (a comment and a blank line first) in .git/info.
hooked() {
  repo; git config core.hooksPath scripts/hooks
  [ $# -gt 0 ] || return 0
  printf '# test\n\n' > "$(git rev-parse --git-common-dir)/info/private-words"
  printf '%s\n' "$@" >> "$(git rev-parse --git-common-dir)/info/private-words"
}

t_flags_home_path() {
  repo; printf 'hello\nsee %s/x\n' "$mac_home" > notes.md
  run bash scripts/check.sh notes.md
  eq exit 1 "$code"
  eq "stderr line 1" "notes.md:2: home path: $mac_home" "$(printf '%s\n' "$err" | sed -n 1p)"
  eq "last stderr line" "check: 1 problem(s) found" "$(printf '%s\n' "$err" | tail -1)"
}

t_flags_linux_home_path() {
  repo; printf 'cd %s\n' "$linux_home" > notes.md
  run bash scripts/check.sh notes.md
  eq exit 1 "$code"
  eq "stderr line 1" "notes.md:1: home path: $linux_home" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_passes_clean_file() {
  repo; printf 'see ~/development/x\n' > notes.md
  run bash scripts/check.sh notes.md
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_email() {
  repo; printf 'mail %s\n' "$email" > notes.md
  run bash scripts/check.sh notes.md
  eq exit 1 "$code"
  eq "stderr line 1" "notes.md:1: email: $email" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_hook_stops_private_word() {
  hooked "$word"; printf 'hello\na %s here\n' "$Word" > notes.md; git add notes.md
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "notes.md:2: private word: $Word" "$err"
  eq commits 1 "$(git rev-list --count HEAD)"
}

t_hook_stops_home_path() {
  hooked; printf 'see %s/x\n' "$mac_home" > notes.md; git add notes.md
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "notes.md:1: home path: $mac_home" "$err"
}

t_flags_private_word_in_path() {
  hooked skills/secretskill; mkdir -p skills/secretskill
  printf 'hi\n' > skills/secretskill/SKILL.md; git add skills
  run bash scripts/check.sh --staged
  eq exit 1 "$code"
  has stderr "skills/secretskill/SKILL.md: private word in path: skills/secretskill" "$err"
}

# skills_home <skill-text>: repo with an empty skills/, and a local skills
# folder at $T/home holding demo/SKILL.md with that text.
skills_home() {
  repo; mkdir skills; mkdir -p "$T/home/demo"
  printf '%s\n' "$1" > "$T/home/demo/SKILL.md"
}

t_adopt_moves_links_checks() {
  skills_home "# demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh demo
  eq exit 0 "$code"
  eq stdout "$(printf 'adopted demo\ncheck: clean')" "$out"
  [ -f skills/demo/SKILL.md ] || eq "skills/demo/SKILL.md" "a file" "missing"
  eq link "$R/skills/demo" "$(readlink "$T/home/demo")"
}

t_tree_scans_tracked_files() {
  repo; printf 'hello\n' > a.md; printf 'mail %s\n' "$email" > b.md
  git add a.md b.md; git commit -qm files
  run env PRIVATE_WORDS=/dev/null bash scripts/check.sh
  eq exit 1 "$code"
  has stderr "b.md:1: email: $email" "$err"
}

t_scans_path_from_subfolder() {
  repo; mkdir sub; printf 'hello\n' > notes.md; printf 'mail %s\n' "$email" > sub/notes.md
  cd sub; run bash ../scripts/check.sh notes.md
  eq exit 1 "$code"
  eq "stderr line 1" "sub/notes.md:1: email: $email" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_adopt_stops_on_bad_name() {
  skills_home "# demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh ..
  eq exit 64 "$code"
  eq stderr "stop: not a skill name: ..
usage: adopt.sh <name>" "$err"
  eq "ls home" demo "$(ls "$T/home")"
  eq "ls skills" "" "$(ls skills)"
}

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

# with_tiers: this checkout's shared/model-tiers.md in the repo, which every
# agent file needs for its models.
with_tiers() { mkdir -p shared && cp "$scripts_dir/../shared/model-tiers.md" shared/; }

# full_agent: the frontmatter lines of a skill agent `helper` with every field.
full_agent='name: helper
description: Reviews one "demo" diff.
tools: Read, Grep, Glob, Bash
tier: 1
checker: no'

# agent <skill> <name>: a skill agent file skills/<skill>/agents/<name>.md,
# full_agent under that name, with a two-line body.
agent() {
  [ -f shared/model-tiers.md ] || with_tiers
  mkdir -p "skills/$1/agents"
  printf -- '---\n%s\n---\nReview the diff.\nMatch \\d+ in "x".\n' "${full_agent/name: helper/name: $2}" > "skills/$1/agents/$2.md"
}

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

t_flags_missing_own_path() {
  repo; mkdir -p skills/demo/scripts; printf 'hi\n' > skills/demo/scripts/ok.sh
  printf 'run `scripts/ok.sh`\nrun `scripts/nope.sh`\n' > skills/demo/SKILL.md
  run bash scripts/check.sh skills
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md:2: missing path: scripts/nope.sh" "$(printf '%s\n' "$err" | sed -n 1p)"
  eq "last stderr line" "check: 1 problem(s) found" "$(printf '%s\n' "$err" | tail -1)"
}

t_flags_missing_skill_path() {
  repo; mkdir -p skills/a; printf 'read `../nope/SKILL.md`\n' > skills/a/SKILL.md
  run bash scripts/check.sh skills
  eq exit 1 "$code"
  eq "stderr line 1" "skills/a/SKILL.md:1: missing path: ../nope/SKILL.md" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_hook_stops_missing_path() {
  hooked; mkdir -p skills/demo; printf 'see `../nope/SKILL.md`\n' > skills/demo/SKILL.md; git add skills
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "skills/demo/SKILL.md:1: missing path: ../nope/SKILL.md" "$err"
  eq commits 1 "$(git rev-list --count HEAD)"
}

t_flags_harness_branch_in_skill() {
  # Given: a skill line that branches on one harness
  repo; skill demo 'In Codex, run it twice.'; git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/SKILL.md:6: harness branch: In Codex" "$err"
}

t_flags_harness_branch_in_shared() {
  # Given: a shared core file that branches on one harness
  repo; mkdir -p shared; printf 'Run it in Claude Code only.\n' > shared/notes.md; git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "shared/notes.md:1: harness branch: in Claude Code" "$err"
}

t_hook_stops_harness_branch() {
  # Given: the hook on, and a staged skill line that branches on one harness
  hooked; skill demo 'In Codex, run it twice.'; git add skills
  # When
  run git commit -m test
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "skills/demo/SKILL.md:6: harness branch: In Codex" "$err"
  eq commits 1 "$(git rev-list --count HEAD)"
}

t_flags_skill_tool_in_skill() {
  # Given: a skill line that names one harness's tool to start a skill
  repo; skill demo 'Then invoke to-issue with the Skill tool.'; git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/SKILL.md:6: harness tool: with the Skill tool" "$err"
}

# skill_md <name>: skills/<name>/SKILL.md with a frontmatter whose name is
# the folder and whose description is not empty.
skill_md() {
  mkdir -p "skills/$1"
  printf -- '---\nname: %s\ndescription: A %s skill.\n---\n# %s\n' "$1" "$1" "$1" > "skills/$1/SKILL.md"
}

# skill <name> [<line>]: skills/<name> with a SKILL.md, plus <line> when
# given, and a README that has the four template headings.
skill() {
  skill_md "$1"
  [ $# -lt 2 ] || printf '%s\n' "$2" >> "skills/$1/SKILL.md"
  printf '# %s\n\n## Use it when\n\n## What you get\n\n## Needs\n\n## Fits with\n' "$1" > "skills/$1/README.md"
}

# readme <heading>...: skills/demo with a SKILL.md and a README that has
# these `## ` headings.
readme() {
  skill_md demo
  printf '# demo\n' > skills/demo/README.md
  for h in "$@"; do printf '\n## %s\n' "$h" >> skills/demo/README.md; done
}

# demo_skill: skills/demo with a SKILL.md and a README that has the template
# headings, Credits included.
demo_skill() { readme "Use it when" "What you get" "Needs" "Fits with" "Credits"; }

# notices <path> <level>: THIRD_PARTY_NOTICES.md for upstream acme/tools with
# one row, on line 5, for that path at that level.
notices() {
  printf '## acme/tools\n\n| Skill or file | Upstream path | Level |\n|---|---|---|\n| `%s` | `x/demo` | %s |\n' "$1" "$2" > THIRD_PARTY_NOTICES.md
}

t_flags_copy_without_license() {
  repo; demo_skill; notices skills/demo copy; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "THIRD_PARTY_NOTICES.md:5: missing license: skills/demo/LICENSE" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_core_row_without_license() {
  repo; mkdir -p shared; printf 'hi\n' > shared/x.md
  notices shared/x.md "heavy adaptation"; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "THIRD_PARTY_NOTICES.md:5: missing license: shared/LICENSE-acme" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_hook_stops_row_without_license() {
  hooked; demo_skill; notices skills/demo copy; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "THIRD_PARTY_NOTICES.md:5: missing license: skills/demo/LICENSE" "$err"
  eq commits 1 "$(git rev-list --count HEAD)"
}

t_flags_skill_without_readme() {
  repo; mkdir -p skills/demo; printf '# demo\n' > skills/demo/SKILL.md; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo: missing file: README.md" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_missing_heading() {
  repo; readme "Use it when" "What you get" "Fits with"; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/README.md: missing heading: ## Needs" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_listed_without_credits() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"; printf 'MIT\n' > skills/demo/LICENSE
  notices skills/demo copy; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/README.md: missing heading: ## Credits" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_listed_file_without_credits() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"; printf 'MIT\n' > skills/demo/LICENSE
  notices skills/demo/references/x.md copy; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/README.md: missing heading: ## Credits" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_no_frontmatter() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"; printf '# demo\n' > skills/demo/SKILL.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: missing frontmatter" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_name_not_folder() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: other\ndescription: A demo skill.\n---\n' > skills/demo/SKILL.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: name does not match folder: other" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_empty_description() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: demo\ndescription: ""\n---\n' > skills/demo/SKILL.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: empty description" "$(printf '%s\n' "$err" | sed -n 1p)"
}

# header <frontmatter lines>: repo with skills/demo, its README headings, and a
# SKILL.md of `---`, these lines, `---`, committed; then run check.sh.
header() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\n%s\n---\n' "$1" > skills/demo/SKILL.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
}

# invocation <lock line> <yaml text>: repo with skills/demo, its README
# headings, a SKILL.md with <lock line> in its frontmatter when not empty, and
# skills/demo/agents/openai.yaml of <yaml text> when not empty, committed;
# then run check.sh.
invocation() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  { printf -- '---\nname: demo\ndescription: A demo skill.\n'
    [ -z "$1" ] || printf '%s\n' "$1"
    printf -- '---\n'; } > skills/demo/SKILL.md
  if [ -n "$2" ]; then mkdir -p skills/demo/agents; printf '%s\n' "$2" > skills/demo/agents/openai.yaml; fi
  git add -A; git commit -qm files
  run bash scripts/check.sh
}

t_flags_locked_without_codex_file() {
  # Given: SKILL.md locks the skill, and it has no Codex file
  # When
  invocation 'disable-model-invocation: true' ''
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/openai.yaml: missing file: SKILL.md sets disable-model-invocation: true" "$err"
}

t_flags_locked_codex_free() {
  # Given: SKILL.md locks the skill, and its Codex file has no policy
  # When
  invocation 'disable-model-invocation: true' "$(printf 'interface:\n  display_name: "Demo"')"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/openai.yaml: allow_implicit_invocation is not false, but SKILL.md sets disable-model-invocation: true" "$err"
}

t_flags_only_codex_locked() {
  # Given: the Codex file locks the skill, and SKILL.md does not
  # When
  invocation '' "$(printf 'policy:\n  allow_implicit_invocation: false')"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/openai.yaml: allow_implicit_invocation is false, but SKILL.md does not set disable-model-invocation: true" "$err"
}

# agent_md <frontmatter lines>: header's repo with a good SKILL.md, and
# skills/demo/agents/helper.md of `---`, these lines, `---`, committed; then
# run check.sh.
agent_md() {
  repo; with_tiers; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: demo\ndescription: A demo skill.\n---\n' > skills/demo/SKILL.md
  mkdir -p skills/demo/agents; printf -- '---\n%s\n---\n' "$1" > skills/demo/agents/helper.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
}

t_flags_agent_no_frontmatter() {
  # Given: an agent file with no frontmatter
  agent_md x; printf '# helper\n' > skills/demo/agents/helper.md; git add -A; git commit -qm bare
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: missing frontmatter" "$err"
}

t_flags_agent_name_not_file() {
  agent_md "$(printf 'name: other\ndescription: d\nmodel: sonnet\neffort: high')"
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: name does not match file: other" "$err"
}

t_flags_agent_empty_description() {
  agent_md "$(printf 'name: helper\ndescription: ""\nmodel: sonnet\neffort: high')"
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: empty description" "$err"
}




t_flags_agent_block_name() {
  # Given: every field, with the name as a block
  # When
  agent_md "${full_agent/name: helper/name: |-
  helper}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md:2: name on more than one line" "$err"
}









t_flags_shared_agent_no_tier() {
  # Given: a good skill, and the shared explorer with every field but the tier line
  repo; with_tiers; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: demo\ndescription: A demo skill.\n---\n' > skills/demo/SKILL.md
  mkdir -p shared/agents
  printf -- '---\n%s\n---\n' "$(printf '%s\n' "${full_agent/name: helper/name: explorer}" | grep -v '^tier: 1$')" > shared/agents/explorer.md
  git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "shared/agents/explorer.md:6: no tier line" "$err"
}

t_flags_agent_no_tier() {
  # Given: every field but the tier line
  # When
  agent_md "$(printf '%s\n' "$full_agent" | grep -v '^tier: 1$')"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md:6: no tier line" "$err"
}

t_flags_agent_no_checker() {
  # Given: every field but the checker line
  # When
  agent_md "$(printf '%s\n' "$full_agent" | grep -v '^checker: no$')"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md:6: no checker line" "$err"
}

t_flags_unknown_tier() {
  # Given: every field, with a tier the tier file has no row for
  # When
  agent_md "${full_agent/tier: 1/tier: 5}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md:5: unknown tier: 5" "$err"
}

# tier_line <n> <line>: line <n> of shared/model-tiers.md replaced by <line>,
# its `\t` read as tabs, and committed; then run check.sh.
tier_line() {
  awk -v n="$1" -v l="$(printf '%b' "$2")" 'NR == n { print l; next } { print }' shared/model-tiers.md > shared/model-tiers.md.new
  mv shared/model-tiers.md.new shared/model-tiers.md; git add -A; git commit -qm tiers
  run bash scripts/check.sh
}

t_flags_tier_row_bad_format() {
  # Given: a good agent, and a tier-models row cut to four cells
  agent_md "$full_agent"
  # When
  tier_line 42 '2\tclaude-sonnet-5-5 high\tgpt-6.1-terra high\tgemini-4-neon low'
  # Then
  eq exit 1 "$code"
  has stderr "shared/model-tiers.md:42: row has 4 cells, its header has 5" "$err"
}

t_flags_try_cell_no_model_at_tier() {
  # Given: a good agent, and a tier-4 Claude try cell that names Devin, which has no tier-4 model
  agent_md "$full_agent"
  # When
  tier_line 60 '4 yes\tdevin, claude\tclaude, codex\tclaude, antigravity'
  # Then
  eq exit 1 "$code"
  has stderr "shared/model-tiers.md:60: 4 yes for claude: devin has no model at tier 4" "$err"
}

t_flags_claude_try_list_ending_elsewhere() {
  # Given: a good agent, and a Claude try cell whose last try is Devin
  agent_md "$full_agent"
  # When
  tier_line 55 '2 no\tclaude, devin\tdevin, codex\tdevin, antigravity'
  # Then
  eq exit 1 "$code"
  has stderr "shared/model-tiers.md:55: 2 no for claude: the last try is devin, not claude" "$err"
}

t_flags_try_order_row_odd_key() {
  # Given: a good agent, and a try-order key with two spaces
  agent_md "$full_agent"
  # When
  tier_line 55 '2  no\tdevin, claude\tdevin, codex\tdevin, antigravity'
  # Then
  eq exit 1 "$code"
  has stderr "shared/model-tiers.md:55: row 2  no is not <tier> <yes|no>" "$err"
}

t_flags_missing_try_order_row() {
  # Given: a good agent, and the try-order row 2 no taken out
  agent_md "$full_agent"
  sed 55d shared/model-tiers.md > shared/model-tiers.md.new; mv shared/model-tiers.md.new shared/model-tiers.md; git add -A; git commit -qm tiers
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "shared/model-tiers.md:52: no try order row 2 no" "$err"
}

t_flags_null_description() {
  header "$(printf 'name: demo\ndescription: null')"
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: empty description" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_comment_description() {
  header "$(printf 'name: demo\ndescription: # add later')"
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: empty description" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_escaped_quote_name() {
  header "$(printf "name: 'demo''-other'\ndescription: A demo skill.")"
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: name does not match folder: demo'-other" "$(printf '%s\n' "$err" | sed -n 1p)"
}

# times <n> <text>: <text> written <n> times, with no newline.
times() { local i; for ((i = 0; i < $1; i++)); do printf '%s' "$2"; done; }

# body <n>: repo with skills/demo, its README headings, and a SKILL.md whose
# body under the frontmatter is <n> lines of `x`, committed; then run check.sh.
body() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: demo\ndescription: A demo skill.\n---\n' > skills/demo/SKILL.md
  for ((i = 0; i < $1; i++)); do printf 'x\n'; done >> skills/demo/SKILL.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
}

t_flags_long_body() {
  # Given: a body of 500 lines. When: check.sh
  body 500
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: body too long: 500 lines (limit: under 500)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_long_description() {
  # Given: a quoted description of 1025 characters. When: check.sh
  header "name: demo
description: \"$(times 1025 a)\""
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: description too long: 1025 characters (limit: 1024)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_counts_block_nested_indent() {
  # Given: a block description of 510, then 512 indented two more, so YAML
  # keeps those two spaces: 510 + 1 newline + 2 + 512 = 1025. When: check.sh
  header "name: demo
description: |
  $(times 510 a)
    $(times 512 a)"
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: description too long: 1025 characters (limit: 1024)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

# agents_md <n>: repo with skills/demo, its README headings, and an AGENTS.md
# of <n> lines of `x`, committed; then run check.sh.
agents_md() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  for ((i = 0; i < $1; i++)); do printf 'x\n'; done > AGENTS.md
  git add -A; git commit -qm files
  run bash scripts/check.sh
}

t_flags_long_agents_md() {
  # Given: an AGENTS.md of 200 lines. When: check.sh
  agents_md 200
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "AGENTS.md: too long: 200 lines (limit: under 200)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_shebang_not_executable() {
  # Given: a file that starts with #! and has no run bit, committed
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf '#!/bin/sh\n' > run.sh; chmod 644 run.sh
  git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "run.sh: starts with #! but is not executable" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_long_name() {
  # Given: a skill whose folder and name are 65 characters
  local n; n="$(times 65 a)"
  repo; skill "$n"
  git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/$n/SKILL.md: name too long: 65 characters (limit: 64)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

# readme_msg <skill>: the line the commit-msg hook prints for a skill
# changed without its README.
readme_msg() { printf '%s: changed without its README; add "Readme: unchanged" to the message to skip' "$1"; }

t_readme_hook_stops_skill_change() {
  hooked; skill demo; git add -A; git commit -qm skill
  printf 'more\n' >> skills/demo/SKILL.md; git add skills
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_marked_change_runs_leak_check() {
  hooked; skill demo; git add -A; git commit -qm skill
  printf 'see %s/x\n' "$mac_home" >> skills/demo/SKILL.md; git add skills
  run git commit -m test -m 'Readme: unchanged'
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "skills/demo/SKILL.md:6: home path: $mac_home" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

# subject_msg <n>: the line the commit-msg hook prints for an <n>-character subject.
subject_msg() { printf 'commit subject too long: %s characters (limit: 50)' "$1"; }

t_subject_hook_stops_long_subject() {
  # Given
  hooked; printf 'x\n' > a.md; git add a.md
  # When
  run git commit -m "$(times 51 a)"
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(subject_msg 51)" "$err"
  eq commits 1 "$(git rev-list --count HEAD)"
}

# core: a shared core with two top-level files, and a handoff/ folder whose
# rules.md includes ../size.md.
core() {
  mkdir -p shared/handoff
  printf 'hi\n' > shared/x.md; printf 'hi\n' > shared/size.md
  printf 'hi\n' > shared/handoff/render.sh
  printf '<!-- include ../size.md -->\n' > shared/handoff/rules.md
}

# bare_core_skill <text>: a hooked repo with core, shared/y.md holding <text>,
# and skill demo reading y.md, committed.
bare_core_skill() {
  hooked; core; printf '%s\n' "$1" > shared/y.md; skill demo 'read `../../shared/y.md`'
  git add -A; git commit -qm skill
}

t_readme_hook_asks_named_core() {
  hooked; core; skill demo 'read `../../shared/x.md`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared/x.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_named_bare() {
  # Given: skill demo reads shared/y.md, which names its sibling x.md bare
  bare_core_skill 'see x.md'
  # When
  printf 'more\n' >> shared/x.md; git add -A
  run git commit -m test
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_named_bare_at_end() {
  # Given: as above, with the bare name at the end of a sentence
  bare_core_skill 'see x.md.'
  # When
  printf 'more\n' >> shared/x.md; git add -A
  run git commit -m test
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_named_bare_deleted() {
  # Given: skill demo reads shared/y.md, which names its sibling x.md bare
  bare_core_skill 'see x.md'
  # When: the commit deletes x.md
  git rm -q shared/x.md
  run git commit -m test
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_named_bare_staged_only() {
  # Given: skill demo reads shared/y.md, which names new.md bare; HEAD has
  # no shared/new.md
  bare_core_skill 'see new.md'
  # When: the commit adds new.md, and its working copy is removed
  printf 'hi\n' > shared/new.md; git add -A; rm shared/new.md
  run git commit -m test
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

# t_runner_keeps_cases_out_of_caller: from a caller repo with an origin, a
# run of its own (run_init, run_cases, run_wait) runs two broken cases. One
# fails, then would write a marker. One loses its cd behind `|| true`, then
# commits and pushes. Both report FAIL; the caller and its origin are
# unchanged and no marker exists.
t_runner_keeps_cases_out_of_caller() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q --bare "$T/origin.git"; git init -q "$T/caller"; cd "$T/caller"
  git config user.email t@example.invalid; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  git remote add origin "$T/origin.git"
  git commit -q --allow-empty -m init; git push -q origin HEAD:refs/heads/main
  local head; head="$(git rev-parse HEAD)"
  t_stops_at_error() { false; touch "$T/marker"; }
  t_lost_cd() { cd "$T/missing" 2>/dev/null || true; git commit -q --allow-empty -m lost; git push -q origin HEAD:refs/heads/lost; }
  cases=("stops|t_stops_at_error" "lost|t_lost_cd")
  # Called directly: `run` uses `||`, which turns set -e off for all it calls.
  { run_init; run_cases; run_wait; } >"$T/out" 2>&1
  eq failed 2 "$fail"
  eq marker no "$([ -e "$T/marker" ] && echo yes || echo no)"
  eq "caller HEAD" "$head" "$(git -C "$T/caller" rev-parse HEAD)"
  eq "origin branches" refs/heads/main "$(git -C "$T/origin.git" for-each-ref --format='%(refname)' refs/heads)"
}

# t_runner_removes_case_temp_folders: a run of its own runs one passing and
# one failing case, each making a temp folder and a temp file with a bare mktemp. None of
# the four is left after either case.
t_runner_removes_case_temp_folders() {
  # Given: a passing and a failing case that each note the temp paths they make
  T="$(cd "$(mktemp -d)" && pwd -P)"
  t_temp_pass() { mktemp -d >>"$T/made.pass"; mktemp >>"$T/made.pass"; }
  t_temp_fail() { mktemp -d >>"$T/made.fail"; mktemp >>"$T/made.fail"; false; }
  local -a cases=("pass|t_temp_pass" "fail|t_temp_fail")
  local p left=""
  # When
  { run_init; run_cases; run_wait; } >"$T/out" 2>&1
  # Then
  eq failed 1 "$fail"
  cat "$T/made.pass" "$T/made.fail" >"$T/made"
  while IFS= read -r p; do [ ! -e "$p" ] || left="$left $p"; done <"$T/made"
  eq "temp left" "" "$left"
}

cases=(
  "flags a home path|t_flags_home_path"
  "flags a linux home path|t_flags_linux_home_path"
  "passes a clean file|t_passes_clean_file"
  "flags an email|t_flags_email"
  "hook stops a commit that adds a private word|t_hook_stops_private_word"
  "hook stops a commit that adds a home path|t_hook_stops_home_path"
  "flags a private word in an added path|t_flags_private_word_in_path"
  "adopt moves, links, and checks a skill|t_adopt_moves_links_checks"
  "tree mode scans every tracked file|t_tree_scans_tracked_files"
  "scans a path given from a subfolder|t_scans_path_from_subfolder"
  "adopt stops on a name that is not a skill name|t_adopt_stops_on_bad_name"
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
  "agents.sh lists an agent's tools|t_agents_lists_tools"
  "agents.sh lists a tier-3 checker's try list|t_agents_tries_lists_checker"
  "agents.sh moves every agent of a tier when one cell changes|t_agents_tries_follow_tier_cell"
  "agents.sh start names a tier-2 agent's first try|t_agents_start_names_first_try"
  "agents.sh start says name when the first try is the harness|t_agents_start_by_name_when_first_try_is_harness"
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
  "flags a missing path in a skill|t_flags_missing_own_path"
  "flags a missing path to another skill|t_flags_missing_skill_path"
  "hook stops a commit that adds a missing path|t_hook_stops_missing_path"
  "flags a harness branch in a skill file|t_flags_harness_branch_in_skill"
  "flags a harness branch in a shared core file|t_flags_harness_branch_in_shared"
  "hook stops a commit that adds a harness branch|t_hook_stops_harness_branch"
  "flags a Skill tool name in a skill file|t_flags_skill_tool_in_skill"
  "flags a listed copy with no license|t_flags_copy_without_license"
  "flags a shared core row with no owner license|t_flags_core_row_without_license"
  "hook stops a notices row with no license|t_hook_stops_row_without_license"
  "flags a skill with no README|t_flags_skill_without_readme"
  "flags a README with a missing heading|t_flags_missing_heading"
  "flags a listed skill with no Credits|t_flags_listed_without_credits"
  "flags a skill with a listed file and no Credits|t_flags_listed_file_without_credits"
  "flags a SKILL.md with no frontmatter|t_flags_no_frontmatter"
  "flags a SKILL.md name that is not its folder|t_flags_name_not_folder"
  "flags a SKILL.md with an empty description|t_flags_empty_description"
  "flags a locked skill with no Codex file|t_flags_locked_without_codex_file"
  "flags a locked skill that Codex lets start|t_flags_locked_codex_free"
  "flags a skill only Codex locks|t_flags_only_codex_locked"
  "readme hook stops a skill change without its README|t_readme_hook_stops_skill_change"
  "Readme: unchanged still runs the leak check|t_marked_change_runs_leak_check"
  "commit hook stops a 51-character subject|t_subject_hook_stops_long_subject"
  "readme hook asks a skill that names a changed core file|t_readme_hook_asks_named_core"
  "readme hook asks a skill whose core file names the changed file bare|t_readme_hook_asks_core_named_bare"
  "readme hook follows a bare core name that ends a sentence|t_readme_hook_asks_core_named_bare_at_end"
  "readme hook asks a skill whose bare-named core file the commit deletes|t_readme_hook_asks_core_named_bare_deleted"
  "readme hook follows a bare core name the work tree lacks but the commit holds|t_readme_hook_asks_core_named_bare_staged_only"
  "flags a null description|t_flags_null_description"
  "flags a description that is only a comment|t_flags_comment_description"
  "flags a SKILL.md name with an escaped quote|t_flags_escaped_quote_name"
  "flags a SKILL.md body of 500 lines|t_flags_long_body"
  "flags a description over 1024 characters|t_flags_long_description"
  "counts the nested indent of a block description|t_counts_block_nested_indent"
  "flags a name over 64 characters|t_flags_long_name"
  "flags an AGENTS.md of 200 lines|t_flags_long_agents_md"
  "flags a #! file with no run bit|t_flags_shebang_not_executable"
  "flags an agent file with no frontmatter|t_flags_agent_no_frontmatter"
  "flags an agent name that is not its file name|t_flags_agent_name_not_file"
  "flags an agent file with an empty description|t_flags_agent_empty_description"
  "flags an agent file with a block name|t_flags_agent_block_name"
  "flags an agent file with no tier line|t_flags_agent_no_tier"
  "flags an agent file with no checker line|t_flags_agent_no_checker"
  "flags an unknown tier|t_flags_unknown_tier"
  "flags a tier row in a bad format|t_flags_tier_row_bad_format"
  "flags a try cell with no model at its tier|t_flags_try_cell_no_model_at_tier"
  "flags a Claude try list that ends on another company|t_flags_claude_try_list_ending_elsewhere"
  "flags a try-order row whose key has two spaces|t_flags_try_order_row_odd_key"
  "flags a missing try-order row|t_flags_missing_try_order_row"
  "flags a shared agent with no tier line|t_flags_shared_agent_no_tier"
  "runner keeps a broken case out of the caller repo|t_runner_keeps_cases_out_of_caller"
  "runner removes each case's temp folders|t_runner_removes_case_temp_folders"
)

# run_init: a new run: an empty run folder, a pipe that holds one token per
# CPU core, and the counters. A case starts only when it takes a token, and
# its job gives the token back when the case ends, so at most one case per
# core runs at once. A pipe, not `wait -n`: macOS ships Bash 3.2, which has
# no `wait -n`.
run_init() {
  local n
  run_dir="$(mktemp -d)"; mkfifo "$run_dir/slots"; exec 9<>"$run_dir/slots"
  n="$(getconf _NPROCESSORS_ONLN)"
  while [ "$n" -gt 0 ]; do printf '\n' >&9; n=$((n - 1)); done
  names=(); started=0; printed=0; pass=0; fail=0
}

# run_cases: start each case of `cases` as a background job, in a subshell
# with set -e on, from a new empty temp folder that git finds no repo above,
# with its own fake home. The folder sits in a root that is the case's
# TMPDIR, with the mktemp wrapper first on PATH, and the root is removed when
# the case ends, pass or fail. The job keeps the case's output and exit code
# in the run folder; the exit code is written under a temp name and renamed,
# so run_print never reads half of it. Then print the cases that have ended.
run_cases() {
  local c fn
  for c in "${cases[@]}"; do
    fn="${c##*|}"; started=$((started + 1)); names[started]="${c%%|*}"
    read -r -u 9 _
    (
      root="$(mktemp -d)"
      set +e; ( set -e; export TMPDIR="$root" PATH="$case_bin:$PATH"; cd "$(mktemp -d)"; export GIT_CEILING_DIRECTORIES="$(dirname "$PWD")"; fake_home; "$fn" ) >"$run_dir/$started.log" 2>&1; rc=$?
      rm -rf "$root"
      printf '%s' "$rc" > "$run_dir/$started.rc.tmp"; mv "$run_dir/$started.rc.tmp" "$run_dir/$started.rc"
      printf '\n' >&9
    ) &
    run_print
  done
}

# run_print: print each ended case in case order, up to the first that still
# runs, as `ok <name>` or `FAIL <name>: <why>`, and add to pass and fail.
run_print() {
  local n
  while [ -e "$run_dir/$((printed + 1)).rc" ]; do
    n=$((printed + 1)); printed="$n"
    if [ "$(cat "$run_dir/$n.rc")" -eq 0 ]; then
      printf 'ok %s\n' "${names[n]}"; pass=$((pass + 1))
    else
      printf 'FAIL %s: %s\n' "${names[n]}" "$(tail -1 "$run_dir/$n.log")"; fail=$((fail + 1))
    fi
  done
}

# run_wait: wait for every case of the run, then print the rest. A case whose
# job ended with no exit code, as when its temp root could not be made, is a
# FAIL, so a run never passes with a case that did not run.
run_wait() {
  wait; run_print
  while [ "$printed" -lt "$started" ]; do
    printed=$((printed + 1))
    printf 'FAIL %s: no result\n' "${names[printed]}"; fail=$((fail + 1))
    run_print
  done
}

run_tmp="$(mktemp -d)"; case_bin="$run_tmp/case-bin"; mkdir -p "$case_bin"
# A case that links mktemp into a PATH of its own links this wrapper, so the
# wrapper names the real mktemp by its full path.
{ printf '#!/bin/sh\nreal='\''%s'\''\n' "$(command -v mktemp)"; cat <<'EOF'
# macOS mktemp ignores TMPDIR when it gets no template (man mktemp), so a
# case's temp files would land outside its root; -p puts them there.
for a in "$@"; do case "$a" in *XXX*) exec "$real" "$@" ;; esac; done
[ -n "${TMPDIR:-}" ] || exec "$real" "$@"
exec "$real" -p "$TMPDIR" "$@"
EOF
} > "$case_bin/mktemp"
chmod +x "$case_bin/mktemp"
# Each test file is sourced only after the jobs of the file before have
# started, and a job keeps the functions it started with, so a helper name in
# one file never replaces another file's.
run_init
trap 'rm -rf "$run_tmp" "$run_dir"' EXIT
run_cases
for f in "$here"/../skills/*/tests/*.sh "$here"/../shared/tests/*.sh; do
  cases=(); . "$f"; run_cases
done
run_wait
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
