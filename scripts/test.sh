#!/usr/bin/env bash
# test.sh: the tests for check.sh, the pre-commit and commit-msg hooks,
# adopt.sh, link.sh and the hooks that run it. It sources test-lib.sh, the helpers, the
# one fake gh, and the fake curl that every case shares, runs its own cases,
# then sources each skills/*/tests/*.sh and shared/tests/*.sh in
# turn and runs that file's cases.
#
#   test.sh
#
# Each case starts in an empty temp folder with set -e on, builds its own git
# repo in a temp folder, copies this scripts/ folder in, and runs the command
# there. Every leak string
# below is joined
# from two halves at runtime, so this file holds nothing check.sh flags.
#
# Prints `ok <case>` or `FAIL <case>: <why>` per case, then
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

t_allows_bot_email() {
  repo; printf '`Cursor Agent <cursoragent@cursor.com>`\n' > notes.md
  run bash scripts/check.sh notes.md
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_hook_stops_private_word() {
  hooked "$word"; printf 'hello\na %s here\n' "$Word" > notes.md; git add notes.md
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "notes.md:2: private word: $Word" "$err"
  eq commits 1 "$(git rev-list --count HEAD)"
}

t_hook_lets_old_word_through() {
  hooked "$word"; printf 'hello\na %s here\n' "$word" > notes.md; git add notes.md
  git commit -q --amend --no-verify -m init
  printf 'bye\n' >> notes.md; git add notes.md
  run git commit -m test
  eq exit 0 "$code"
  eq commits 2 "$(git rev-list --count HEAD)"
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

t_no_verify_skips_hook() {
  hooked "$word"; printf 'hello\na %s here\n' "$Word" > notes.md; git add notes.md
  run git commit --no-verify -m test
  eq exit 0 "$code"
  eq commits 2 "$(git rev-list --count HEAD)"
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

t_adopt_reports_leak() {
  skills_home "see $mac_home/x"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh demo
  eq exit 1 "$code"
  has stderr "skills/demo/SKILL.md:1: home path: $mac_home" "$err"
  [ -f skills/demo/SKILL.md ] || eq "skills/demo/SKILL.md" "a file" "missing"
}

t_adopt_stops_on_missing() {
  skills_home "# demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh nope
  eq exit 1 "$code"
  eq stderr "stop: no skill named nope in $T/home" "$err"
  eq "ls home" demo "$(ls "$T/home")"
  eq "ls skills" "" "$(ls skills)"
}

t_adopt_stops_on_adopted() {
  skills_home "# demo"; mv "$T/home/demo" skills/demo; ln -s "$R/skills/demo" "$T/home/demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh demo
  eq exit 1 "$code"
  eq stderr "stop: $T/home/demo is already a link" "$err"
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

t_stops_on_missing_path() {
  repo; run bash scripts/check.sh nope
  eq exit 1 "$code"
  eq stderr "stop: no such path: nope" "$err"
}

t_check_refuses_unknown_flag() {
  # Given: a repo
  repo
  # When
  run bash scripts/check.sh --bogus
  # Then
  eq exit 64 "$code"
  eq stderr "stop: unknown flag --bogus
usage: check.sh [<path>... | --staged | --commit-msg <file>]" "$err"
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

# full_agent: the frontmatter lines of a skill agent `helper` with every field.
full_agent='name: helper
description: Reviews one "demo" diff.
tools: Read, Grep, Glob, Bash
home:
  claude: devin swe-2-high high
  codex: claude claude-opus-5-5 xhigh
  antigravity: claude claude-opus-5-5 xhigh
backup:
  claude: claude-haiku-5-5 high
  codex: gpt-6-luna xhigh
  antigravity: inherit'

# agent <skill> <name>: a skill agent file skills/<skill>/agents/<name>.md,
# full_agent under that name, with a two-line body.
agent() {
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

t_link_runs_from_outside_repo() {
  linked demo; cd /
  link_sh "$R/scripts/link.sh"
  eq exit 0 "$code"
  eq "agents link" "$R/skills/demo" "$(readlink "$T/agents/demo")"
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
    'name = "helper"' 'description = "Reviews one \"demo\" diff."' 'model = "gpt-6-luna"' \
    'model_reasoning_effort = "xhigh"' 'developer_instructions = """' 'Review the diff.' \
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

t_link_skips_agent_without_claude_backup() {
  # Given: an agent file with no Claude Code backup
  linked demo; agent demo helper
  grep -v '^  claude: claude-haiku-5-5 high$' skills/demo/agents/helper.md > "$T/a"; mv "$T/a" skills/demo/agents/helper.md
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stderr "skip: skills/demo/agents/helper.md: missing backup for claude" "$err"
  [ ! -e "$T/cagents/helper.md" ] || eq "cagents/helper.md" "none" "written"
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

t_agents_lists_every_tool_without_tools_line() {
  # Given: an agent with no tools line
  repo; agent demo helper
  sed -i.bak '/^tools:/d' skills/demo/agents/helper.md
  # When
  run bash scripts/agents.sh tools < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "Read Grep Glob Bash Edit Write WebSearch WebFetch Agent" "$out"
}

t_agents_start_names_first_home() {
  # Given: an agent whose Claude home is devin swe-2-high high and whose
  # Claude backup is claude-haiku-5-5 high
  repo; agent demo helper
  # When
  run bash scripts/agents.sh start claude < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "t3 devin swe-2-high high" "$out"
}

t_agents_start_by_name_when_home_is_backup() {
  # Given: the same agent with its Claude home on the backup's model and effort
  repo; agent demo helper
  sed -i.bak 's/^  claude: devin swe-2-high high$/  claude: claude claude-haiku-5-5 high/' skills/demo/agents/helper.md
  # When
  run bash scripts/agents.sh start claude < skills/demo/agents/helper.md
  # Then
  eq exit 0 "$code"
  eq stdout "name" "$out"
}

t_agents_lists_models_in_order() {
  # Given: an agent with two Claude homes, and a comment and a blank line in
  # its home map
  repo; agent demo helper
  sed -i.bak -e 's/^  claude: devin swe-2-high high$/  claude: devin swe-2-high high, codex gpt-6-luna high\
  # a note\
/' skills/demo/agents/helper.md
  # When
  run bash scripts/agents.sh models < skills/demo/agents/helper.md
  # Then
  eq stdout "$(printf '%s\n' 'home claude devin swe-2-high' 'home2 claude codex gpt-6-luna' 'home codex claude claude-opus-5-5' \
    'home antigravity claude claude-opus-5-5' 'backup claude claude claude-haiku-5-5' 'backup codex codex gpt-6-luna' \
    'backup antigravity antigravity inherit')" "$out"
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
  linked demo; mkdir -p shared/agents
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

t_link_leaves_hook_file_not_json() {
  # Given: a settings file that is not JSON
  linked demo; with_gate; printf '{oops' > "$T/claude-settings.json"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stderr "skip: $T/claude-settings.json is not JSON" "$err"
  eq "own file" '{oops' "$(cat "$T/claude-settings.json")"
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

t_link_removes_old_antigravity_plugin() {
  # Given: the skills plugin an earlier run wrote
  linked demo; agent demo helper; with_gate; old_plugin
  # When
  link_sh
  # Then
  [ ! -e "$T/gplugins/skills" ] || eq "gplugins/skills" "gone" "$(find "$T/gplugins/skills" | tr '\n' ' ')"
}

t_link_old_plugin_cleanup_runs_once() {
  # Given: the old skills plugin, removed by one run
  linked demo; agent demo helper; with_gate; old_plugin; link_sh
  # When
  link_sh
  # Then
  eq "second run" "" "$out$err"
}

t_link_keeps_user_key_in_old_plugin_hooks() {
  # Given: the old skills plugin, its hooks.json with a key of the user's own
  linked demo; agent demo helper; with_gate; old_plugin
  printf '%s' '{"mine":{},"subagent-gate":{"PreToolUse":[]}}' > "$T/gplugins/skills/hooks.json"
  # When
  link_sh
  # Then
  eq hooks '{"mine":{}}' "$(jq -c . "$T/gplugins/skills/hooks.json")"
}

t_link_keeps_user_manifest_in_old_plugin() {
  # Given: the old skills plugin, with a plugin.json of the user's own
  linked demo; agent demo helper; with_gate; old_plugin
  printf 'mine\n' > "$T/gplugins/skills/plugin.json"
  # When
  link_sh
  # Then
  eq files "$T/gplugins/skills/plugin.json" "$(find "$T/gplugins/skills" -type f)"
}

t_link_keeps_user_agent_in_old_plugin() {
  # Given: the old skills plugin, with an agent file of the user's own
  linked demo; agent demo helper; with_gate; old_plugin
  printf 'mine\n' > "$T/gplugins/skills/agents/mine.md"
  # When
  link_sh
  # Then
  eq files "$T/gplugins/skills/agents/mine.md" "$(find "$T/gplugins/skills" -type f)"
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

t_link_skips_t3_when_none() {
  # Given: no T3 Antigravity folder
  linked demo; rm -r "$T/t3"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  eq stderr "skip: no T3 Antigravity folder in $T/t3" "$err"
  eq "ls gskills" demo "$(ls "$T/gskills")"
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
  # Given: everything linked, then a second agent with no Codex backup
  linked demo; agent demo helper; with_gate; link_sh
  agent demo helper2; grep -v '^  codex: gpt-6-luna xhigh$' skills/demo/agents/helper2.md > "$T/a"; mv "$T/a" skills/demo/agents/helper2.md
  # When
  link_sh scripts/link.sh --status
  # Then
  eq "helper2 lines" "$(for l in "claude $T/cagents/helper2.md $T/cagents" "codex $T/codex/helper2.toml $T/codex"; do
      read -r h p f <<<"$l"; printf 'missing\tagent\t%s\thelper2\t%s\t%s\tskills/demo/agents/helper2.md: missing backup for codex\n' "$h" "$p" "$f"; done)" \
    "$(grep helper2 <<<"$out")"
}

t_link_status_names_installed_agent_it_cannot_render() {
  # Given: everything linked, then the agent's Codex backup taken out
  linked demo; agent demo helper; with_gate; link_sh
  grep -v '^  codex: gpt-6-luna xhigh$' skills/demo/agents/helper.md > "$T/a"; mv "$T/a" skills/demo/agents/helper.md
  # When
  link_sh scripts/link.sh --status
  # Then
  eq "helper lines" "$(for l in "claude $T/cagents/helper.md $T/cagents" "codex $T/codex/helper.toml $T/codex"; do
      read -r h p f <<<"$l"; printf 'stale\tagent\t%s\thelper\t%s\t%s\tskills/demo/agents/helper.md: missing backup for codex\n' "$h" "$p" "$f"; done)" \
    "$(awk -F '\t' '$2 == "agent"' <<<"$out")"
}

t_link_status_matches_install_skips() {
  # Given: everything linked, then a target of every kind held by something
  # else, and a second agent with no Codex backup
  linked demo; agent demo helper; with_gate; link_sh
  rm "$T/claude/demo"; mkdir "$T/claude/demo"
  printf 'mine\n' > "$T/codex/helper.toml"
  printf 'not json\n' > "$T/claude-settings.json"
  rm "$T/t3/p1/config/plugins"; mkdir "$T/t3/p1/config/plugins"
  agent demo helper2; grep -v '^  codex: gpt-6-luna xhigh$' skills/demo/agents/helper2.md > "$T/a"; mv "$T/a" skills/demo/agents/helper2.md
  # When: the install, then --status
  link_sh
  local skips whys want
  skips="$(sed -n 's/^skip: //p' <<<"$err" | LC_ALL=C sort -u)"
  link_sh scripts/link.sh --status
  whys="$(awk -F '\t' '$NF ~ / / { print $NF }' <<<"$out" | LC_ALL=C sort -u)"
  # Then
  want="$(printf '%s\n' "$T/claude-settings.json is not JSON" "$T/claude/demo is not this repo's demo" \
    "$T/codex/helper.toml is not this repo's helper.toml" "$T/t3/p1/config/plugins is not this repo's plugins" \
    "skills/demo/agents/helper2.md: missing backup for codex")"
  eq "install skips" "$want" "$skips"
  eq "status whys" "$want" "$whys"
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

t_link_skips_antigravity_relative_dangling_link() {
  # Given: everything linked, then Antigravity's skill link in Claude Code's
  # relative form, pointing to nothing; the install does not remove that form
  # in Antigravity's folder
  linked demo; link_sh
  rm "$T/gskills/demo"; ln -s ../../.agents/skills/demo "$T/gskills/demo"
  # When
  link_sh
  # Then
  has stderr "skip: $T/gskills/demo is a link to nothing, not made here" "$err"
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

t_link_refuses_unknown_argument() {
  # Given: everything linked
  linked demo; agent demo helper; with_gate; link_sh
  # When
  link_sh scripts/link.sh --nope
  # Then
  eq exit 64 "$code"
  eq stderr "usage: link.sh [--status]" "$err"
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

t_passes_skill_and_core_paths() {
  repo; mkdir -p skills/a skills/b shared
  printf 'hi\n' > skills/b/SKILL.md; printf 'hi\n' > shared/x.md
  printf 'read `../b/SKILL.md:3` and ../../shared/x.md.\n' > skills/a/SKILL.md
  run bash scripts/check.sh skills shared
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_missing_skill_path() {
  repo; mkdir -p skills/a; printf 'read `../nope/SKILL.md`\n' > skills/a/SKILL.md
  run bash scripts/check.sh skills
  eq exit 1 "$code"
  eq "stderr line 1" "skills/a/SKILL.md:1: missing path: ../nope/SKILL.md" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_reads_core_path_from_own_folder() {
  repo; mkdir -p shared/handoff; printf 'hi\n' > shared/size.md
  printf '<!-- include ../size.md -->\nsee `../gone.md`\n' > shared/handoff/rules.md
  run bash scripts/check.sh shared
  eq exit 1 "$code"
  eq "stderr line 1" "shared/handoff/rules.md:2: missing path: ../gone.md" "$(printf '%s\n' "$err" | sed -n 1p)"
  eq "last stderr line" "check: 1 problem(s) found" "$(printf '%s\n' "$err" | tail -1)"
}

t_passes_bare_name_of_no_file() {
  # Given: a shared file that names notes.md bare, and no shared/notes.md
  repo; mkdir -p shared; printf 'see notes.md\n' > shared/y.md
  # When
  run bash scripts/check.sh shared
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_skips_placeholders_and_other_folders() {
  repo; mkdir -p skills/demo/references; printf 'hi\n' > skills/demo/references/a.md
  printf 'see `references/types/<type>.md`, `./src/x.md`, and `scripts/sync-repos.sh`\n' > skills/demo/SKILL.md
  run bash scripts/check.sh skills
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_allows_listed_path() {
  repo; mkdir -p skills/embed-source/scripts; printf 'hi\n' > skills/embed-source/scripts/status.sh
  printf 'writes `scripts/sync-repos.sh` in your repo\n' > skills/embed-source/SKILL.md
  run bash scripts/check.sh skills
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_missing_here_path() {
  repo; mkdir -p skills/a/scripts
  printf 'python3 "$here/../../b/scripts/x.py"\n' > skills/a/scripts/run.sh
  run bash scripts/check.sh skills
  eq exit 1 "$code"
  eq "stderr line 1" "skills/a/scripts/run.sh:1: missing path: ../../b/scripts/x.py" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_ignores_paths_elsewhere() {
  repo; mkdir docs; printf 'see `../nope.md`\n' > docs/notes.md
  run bash scripts/check.sh docs
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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
  repo; mkdir shared; printf 'Run it in Claude Code only.\n' > shared/notes.md; git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "shared/notes.md:1: harness branch: in Claude Code" "$err"
}

t_passes_harness_in_description() {
  # Given: a description that names each harness's command form
  repo; skill demo
  printf -- '---\nname: demo\ndescription: Run /demo in Claude Code or $demo in Codex.\n---\n# demo\n' > skills/demo/SKILL.md
  git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_passes_harness_in_readme() {
  # Given: a README, for people, that names a harness's command form
  repo; skill demo; printf 'Type /demo in Claude Code.\n' >> skills/demo/README.md; git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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
  repo; mkdir shared; printf 'hi\n' > shared/x.md
  notices shared/x.md "heavy adaptation"; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "THIRD_PARTY_NOTICES.md:5: missing license: shared/LICENSE-acme" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_passes_copy_with_license() {
  repo; demo_skill; printf 'MIT\n' > skills/demo/LICENSE; notices skills/demo copy
  printf '| `skills/other` | `x/other` | idea only |\n' >> THIRD_PARTY_NOTICES.md
  git add -A; git commit -qm files
  run env PRIVATE_WORDS=/dev/null bash scripts/check.sh
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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

t_passes_readme_with_headings() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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

# agent_md <frontmatter lines>: header's repo with a good SKILL.md, and
# skills/demo/agents/helper.md of `---`, these lines, `---`, committed; then
# run check.sh.
agent_md() {
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
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

t_flags_agent_no_codex_backup() {
  # Given: every field but the Codex backup
  # When
  agent_md "$(printf '%s\n' "$full_agent" | grep -v '^  codex: gpt-6-luna xhigh$')"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: missing backup for codex" "$err"
}

t_passes_agent_with_blank_and_comment_in_map() {
  # Given: a blank line, an indented comment, and a comment at the line start inside home:
  # When
  agent_md "$(printf '%s\n' "$full_agent" | sed 's/^  claude: devin swe-2-high high$/&\
\
  # Codex next\
# then Antigravity/')"
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_agent_no_antigravity_home() {
  # Given: every field but the Antigravity home
  # When
  agent_md "$(printf '%s\n' "$full_agent" | grep -v '^  antigravity: claude claude-opus-5-5 xhigh$')"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: missing home for antigravity" "$err"
}

t_flags_agent_block_description() {
  # Given: every field, with the description as a block
  # When
  agent_md "${full_agent/description: Reviews one \"demo\" diff./description: |
  Reviews one diff.}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: description on more than one line" "$err"
}

t_flags_agent_block_name() {
  # Given: every field, with the name as a block
  # When
  agent_md "${full_agent/name: helper/name: |-
  helper}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: name on more than one line" "$err"
}

t_flags_agent_unknown_harness() {
  # Given: every field, and a backup for a harness that is not one
  # When
  agent_md "$(printf '%s\n  cursor: gpt-6-luna high' "$full_agent")"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: unknown harness: cursor" "$err"
}

t_flags_backup_model_of_other_harness() {
  # Given: every field, with a Claude model as the Codex backup
  # When
  agent_md "${full_agent/  codex: gpt-6-luna xhigh/  codex: claude-haiku-5-5 high}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: backup for codex: claude-haiku-5-5 is not a model codex takes" "$err"
}

t_flags_exact_antigravity_backup() {
  # Given: every field, with an exact model as the Antigravity backup
  # When
  agent_md "${full_agent/  antigravity: inherit/  antigravity: gemini-4-neon low}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: backup for antigravity: gemini-4-neon is not a model antigravity takes" "$err"
}

t_flags_effort_place_cannot_take() {
  # Given: every field, with an effort Devin has not for the Claude home
  # When
  agent_md "${full_agent/  claude: devin swe-2-high high/  claude: devin swe-2-high ultra}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: home for claude: ultra is not an effort devin takes" "$err"
}

t_flags_home_in_unknown_place() {
  # Given: every field, with the Codex home in a place T3 does not start
  # When
  agent_md "${full_agent/  codex: claude claude-opus-5-5 xhigh/  codex: cursor composer-2 high}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: home for codex: unknown place: cursor" "$err"
}

t_passes_agent_with_two_homes() {
  # Given: every field, with Antigravity Neon then Devin Neon as the Claude home
  # When
  agent_md "${full_agent/  claude: devin swe-2-high high/  claude: antigravity gemini-4-neon high, devin gemini-4-neon-high high}"
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_bad_second_home() {
  # Given: two Claude homes, the second with an effort Devin has not
  # When
  agent_md "${full_agent/  claude: devin swe-2-high high/  claude: antigravity gemini-4-neon high, devin gemini-4-neon-high ultra}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: home 2 for claude: ultra is not an effort devin takes" "$err"
}

t_flags_empty_home() {
  # Given: every field, with an empty Claude home
  # When
  agent_md "${full_agent/  claude: devin swe-2-high high/  claude:}"
  # Then
  eq exit 1 "$code"
  has stderr "skills/demo/agents/helper.md: home for claude: unknown place: " "$err"
}

t_flags_shared_agent_no_codex_backup() {
  # Given: a good skill, and the shared explorer with every field but the Codex backup
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: demo\ndescription: A demo skill.\n---\n' > skills/demo/SKILL.md
  mkdir -p shared/agents
  printf -- '---\n%s\n---\n' "$(printf '%s\n' "${full_agent/name: helper/name: explorer}" | grep -v '^  codex: gpt-6-luna xhigh$')" > shared/agents/explorer.md
  git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  has stderr "shared/agents/explorer.md: missing backup for codex" "$err"
}

t_passes_agent_with_all_fields() {
  # Given: a full agent file and a Codex openai.yaml beside it
  agent_md "$full_agent"
  printf 'interface: {}\n' > skills/demo/agents/openai.yaml; git add -A; git commit -qm yaml
  # When
  run bash scripts/check.sh
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_passes_block_after_blank() {
  header "$(printf 'name: demo\ndescription: |\n\n  Explains the skill.')"
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_passes_name_with_comment() {
  header "$(printf 'name: demo # short label\ndescription: A demo skill.')"
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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

t_passes_body_under_limit() {
  # Given: a body of 499 lines. When: check.sh
  body 499
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_long_description() {
  # Given: a quoted description of 1025 characters. When: check.sh
  header "name: demo
description: \"$(times 1025 a)\""
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: description too long: 1025 characters (limit: 1024)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_passes_description_at_limit() {
  # Given: a quoted description of 1024 characters. When: check.sh
  header "name: demo
description: \"$(times 1024 a)\""
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
}

t_flags_long_block_description() {
  # Given: a block description of two lines of 512, joined by one newline. When: check.sh
  header "name: demo
description: |
  $(times 512 a)
  $(times 512 a)"
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

t_counts_folded_block_description() {
  # Given: a folded block description of 1025 characters. When: check.sh
  header "name: demo
description: >-
  $(times 1025 a)"
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: description too long: 1025 characters (limit: 1024)" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_flags_unclosed_frontmatter() {
  # Given: a SKILL.md whose frontmatter has no closing line
  repo; readme "Use it when" "What you get" "Needs" "Fits with"
  printf -- '---\nname: demo\ndescription: A demo skill.\n' > skills/demo/SKILL.md
  git add -A; git commit -qm files
  # When
  run bash scripts/check.sh
  # Then
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md: missing frontmatter" "$(printf '%s\n' "$err" | sed -n 1p)"
}

t_counts_description_characters() {
  # Given: a description of 1024 two-byte characters, 2048 bytes. When: check.sh
  header "name: demo
description: \"$(times 1024 é)\""
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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

t_passes_agents_md_under_limit() {
  # Given: an AGENTS.md of 199 lines. When: check.sh
  agents_md 199
  # Then
  eq exit 0 "$code"
  eq stdout "check: clean" "$out"
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

t_readme_hook_passes_marked_change() {
  hooked; skill demo; git add -A; git commit -qm skill
  printf 'more\n' >> skills/demo/SKILL.md; git add skills
  run git commit -m test -m 'Readme: unchanged'
  eq exit 0 "$code"
  eq commits 3 "$(git rev-list --count HEAD)"
}

t_readme_hook_passes_with_readme() {
  hooked; skill demo; git add -A; git commit -qm skill
  printf 'more\n' >> skills/demo/SKILL.md; printf 'more\n' >> skills/demo/README.md; git add skills
  run git commit -m test
  eq exit 0 "$code"
  eq commits 3 "$(git rev-list --count HEAD)"
}

t_marked_change_runs_leak_check() {
  hooked; skill demo; git add -A; git commit -qm skill
  printf 'see %s/x\n' "$mac_home" >> skills/demo/SKILL.md; git add skills
  run git commit -m test -m 'Readme: unchanged'
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "skills/demo/SKILL.md:6: home path: $mac_home" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_marked_change_runs_header_check() {
  hooked; skill demo; git add -A; git commit -qm skill
  printf -- '---\nname: other\ndescription: A demo skill.\n---\n' > skills/demo/SKILL.md; git add skills
  run git commit -m test -m 'Readme: unchanged'
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "skills/demo/SKILL.md: name does not match folder: other" "$err"
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

t_subject_hook_passes_50() {
  # Given
  hooked; printf 'x\n' > a.md; git add a.md
  # When
  run git commit -m "$(times 50 a)"
  # Then
  eq exit 0 "$code"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_subject_hook_counts_characters() {
  # Given
  hooked; printf 'x\n' > a.md; git add a.md
  # When
  run git commit -m "$(times 49 a)é"
  # Then
  eq exit 0 "$code"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_subject_hook_passes_merge() {
  # Given
  hooked; printf 'x\n' > a.md; git add a.md
  # When
  run git commit -m "Merge branch '$(times 50 a)'"
  # Then
  eq exit 0 "$code"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_subject_hook_passes_revert() {
  # Given
  hooked; printf 'x\n' > a.md; git add a.md
  # When
  run git commit -m "Revert \"$(times 50 a)\""
  # Then
  eq exit 0 "$code"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_subject_hook_passes_git_merge() {
  # Given: a branch with a 50-character name, one commit ahead
  local b; b="$(times 50 a)"
  hooked; git switch -qc "$b"; printf 'x\n' > a.md; git add a.md; git commit -qm a
  git switch -q -; printf 'y\n' > b.md; git add b.md; git commit -qm b
  # When: git writes the subject `Merge branch '<b>'`
  run git merge --no-ff --no-edit "$b"
  # Then
  eq exit 0 "$code"
  eq commits 4 "$(git rev-list --count HEAD)"
}

t_marked_change_runs_subject_check() {
  # Given
  hooked; printf 'x\n' > a.md; git add a.md
  # When
  run git commit -m "$(times 51 a)" -m 'Readme: unchanged'
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

t_readme_hook_asks_named_core() {
  hooked; core; skill demo 'read `../../shared/x.md`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared/x.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_folder() {
  hooked; core; skill demo 'run `../../shared/handoff/render.sh`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared/handoff/rules.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_included_core() {
  hooked; core; skill demo 'run `../../shared/handoff/render.sh`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared/size.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_skips_unread_core() {
  hooked; core; skill demo 'read `../../shared/x.md`'; skill other 'read `../../shared/size.md`'
  git add -A; git commit -qm skills
  printf 'more\n' >> shared/x.md; printf 'more\n' >> skills/demo/README.md; git add -A
  run git commit -m test
  eq exit 0 "$code"
  eq commits 3 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_named_bare() {
  # Given: skill demo reads shared/y.md, which names its sibling x.md bare
  hooked; core; printf 'see x.md\n' > shared/y.md; skill demo 'read `../../shared/y.md`'
  git add -A; git commit -qm skill
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
  hooked; core; printf 'see x.md.\n' > shared/y.md; skill demo 'read `../../shared/y.md`'
  git add -A; git commit -qm skill
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
  hooked; core; printf 'see x.md\n' > shared/y.md; skill demo 'read `../../shared/y.md`'
  git add -A; git commit -qm skill
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
  hooked; core; printf 'see new.md\n' > shared/y.md; skill demo 'read `../../shared/y.md`'
  git add -A; git commit -qm skill
  # When: the commit adds new.md, and its working copy is removed
  printf 'hi\n' > shared/new.md; git add -A; rm shared/new.md
  run git commit -m test
  # Then
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_skips_bare_name_in_other_folder() {
  # Given: skill demo reads shared/kit/a.md, which names size.md bare;
  # there is no shared/kit/size.md, only shared/size.md
  hooked; core; mkdir -p shared/kit; printf 'see size.md\n' > shared/kit/a.md
  skill demo 'read `../../shared/kit/a.md`'; git add -A; git commit -qm skill
  # When
  printf 'more\n' >> shared/size.md; git add -A
  run git commit -m test
  # Then
  eq exit 0 "$code"
  eq commits 3 "$(git rev-list --count HEAD)"
}

# t_runner_keeps_cases_out_of_caller: from a caller repo with an origin,
# run_cases runs two broken cases. One fails, then would write a marker. One
# loses its cd behind `|| true`, then commits and pushes. Both report FAIL; the
# caller and its origin are unchanged and no marker exists.
t_runner_keeps_cases_out_of_caller() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q --bare "$T/origin.git"; git init -q "$T/caller"; cd "$T/caller"
  git config user.email "t""@""example.invalid"; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  git remote add origin "$T/origin.git"
  git commit -q --allow-empty -m init; git push -q origin HEAD:refs/heads/main
  local head; head="$(git rev-parse HEAD)"
  t_stops_at_error() { false; touch "$T/marker"; }
  t_lost_cd() { cd "$T/missing" 2>/dev/null || true; git commit -q --allow-empty -m lost; git push -q origin HEAD:refs/heads/lost; }
  cases=("stops|t_stops_at_error" "lost|t_lost_cd"); pass=0; fail=0; log="$T/log"
  # Called directly: `run` uses `||`, which turns set -e off for all it calls.
  run_cases >"$T/out" 2>&1
  eq failed 2 "$fail"
  eq marker no "$([ -e "$T/marker" ] && echo yes || echo no)"
  eq "caller HEAD" "$head" "$(git -C "$T/caller" rev-parse HEAD)"
  eq "origin branches" refs/heads/main "$(git -C "$T/origin.git" for-each-ref --format='%(refname)' refs/heads)"
}

cases=(
  "flags a home path|t_flags_home_path"
  "flags a linux home path|t_flags_linux_home_path"
  "passes a clean file|t_passes_clean_file"
  "flags an email|t_flags_email"
  "allows the listed bot email|t_allows_bot_email"
  "hook stops a commit that adds a private word|t_hook_stops_private_word"
  "hook lets through a word on a line the commit does not add|t_hook_lets_old_word_through"
  "hook stops a commit that adds a home path|t_hook_stops_home_path"
  "flags a private word in an added path|t_flags_private_word_in_path"
  "no-verify skips the hook|t_no_verify_skips_hook"
  "adopt moves, links, and checks a skill|t_adopt_moves_links_checks"
  "adopt reports a leak in the adopted skill|t_adopt_reports_leak"
  "adopt stops on a missing skill|t_adopt_stops_on_missing"
  "adopt stops on a skill already adopted|t_adopt_stops_on_adopted"
  "tree mode scans every tracked file|t_tree_scans_tracked_files"
  "scans a path given from a subfolder|t_scans_path_from_subfolder"
  "stops on a missing path|t_stops_on_missing_path"
  "adopt stops on a name that is not a skill name|t_adopt_stops_on_bad_name"
  "check.sh refuses an unknown flag with its usage|t_check_refuses_unknown_flag"
  "link links a new skill into every folder|t_link_links_new_skill"
  "link follows a renamed skill|t_link_follows_rename"
  "link leaves a name something else holds|t_link_leaves_other_names"
  "link does nothing in a worktree|t_link_skips_worktree"
  "link.sh runs from outside the repo|t_link_runs_from_outside_repo"
  "link writes a skill agent's Claude Code form|t_link_writes_claude_form"
  "link skips an agent file with no Claude Code backup|t_link_skips_agent_without_claude_backup"
  "link removes the forms of a renamed skill agent|t_link_removes_renamed_agent_forms"
  "link leaves an agent file it did not make|t_link_leaves_other_agent"
  "link adds the gate to claude settings and keeps the rest|t_link_adds_gate_to_claude_settings"
  "link adds the gate to codex hooks once|t_link_adds_gate_to_codex_hooks_once"
  "link keeps a hook that shares the gate's group|t_link_keeps_hook_in_gate_group"
  "link writes through a linked hook file|t_link_writes_through_linked_hook_file"
  "link leaves a hook file that is not JSON|t_link_leaves_hook_file_not_json"
  "link writes a shared agent's two forms|t_link_writes_shared_agent_forms"
  "link writes a skill agent's Codex form|t_link_writes_codex_form"
  "link leaves a Codex agent file it did not make|t_link_leaves_other_codex_agent"
  "agents.sh lists an agent's tools|t_agents_lists_tools"
  "agents.sh lists every tool for an agent with no tools line|t_agents_lists_every_tool_without_tools_line"
  "agents.sh lists each home and backup in file order|t_agents_lists_models_in_order"
  "agents.sh start names the first home off the backup|t_agents_start_names_first_home"
  "agents.sh start says name when the home is the backup|t_agents_start_by_name_when_home_is_backup"
  "link writes no Antigravity plugin|t_link_writes_no_antigravity_plugin"
  "link removes the Antigravity plugin an earlier run wrote|t_link_removes_old_antigravity_plugin"
  "link removes the old Antigravity plugin once|t_link_old_plugin_cleanup_runs_once"
  "link keeps a key of the user's own in the old plugin hooks|t_link_keeps_user_key_in_old_plugin_hooks"
  "link keeps a plugin.json of the user's own|t_link_keeps_user_manifest_in_old_plugin"
  "link keeps an agent file of the user's own in the old plugin|t_link_keeps_user_agent_in_old_plugin"
  "link links the plugins folder into each T3 Antigravity folder|t_link_links_plugins_into_each_t3"
  "link says so when T3 has no Antigravity folder|t_link_skips_t3_when_none"
  "link status names every target ok|t_link_status_names_every_target_ok"
  "link status names missing and held targets|t_link_status_names_missing_and_held"
  "link status writes nothing|t_link_status_writes_nothing"
  "link status names each file of an agent it cannot render|t_link_status_names_agent_it_cannot_render"
  "link status names each installed file of an agent it can no longer render|t_link_status_names_installed_agent_it_cannot_render"
  "link status gives the skip words of the install|t_link_status_matches_install_skips"
  "link status names a held Claude Code link under a held shared link|t_link_status_names_held_link_under_held_shared"
  "link status names no holder for its own dangling link|t_link_status_names_no_holder_for_own_dangling_link"
  "link status names no holder for Claude Code's relative dangling link|t_link_status_names_no_holder_for_relative_dangling_link"
  "link names the holder of Antigravity's relative dangling link|t_link_skips_antigravity_relative_dangling_link"
  "link status names no holder for a T3 link to a missing plugins folder|t_link_status_names_no_holder_for_dangling_t3_plugins_link"
  "link refuses an unknown argument|t_link_refuses_unknown_argument"
  "hooks link a skill on commit, checkout, and merge|t_hooks_link_committed_skill"
  "flags a missing path in a skill|t_flags_missing_own_path"
  "passes paths to another skill and the shared core|t_passes_skill_and_core_paths"
  "flags a missing path to another skill|t_flags_missing_skill_path"
  "reads a shared core path from its own folder|t_reads_core_path_from_own_folder"
  "passes a bare name of no file in the shared core|t_passes_bare_name_of_no_file"
  "skips placeholders and folders a skill does not have|t_skips_placeholders_and_other_folders"
  "allows a listed path in the user's repo|t_allows_listed_path"
  "flags a missing path after \$here in a script|t_flags_missing_here_path"
  "ignores paths outside skills and the shared core|t_ignores_paths_elsewhere"
  "hook stops a commit that adds a missing path|t_hook_stops_missing_path"
  "flags a harness branch in a skill file|t_flags_harness_branch_in_skill"
  "flags a harness branch in a shared core file|t_flags_harness_branch_in_shared"
  "passes a harness command form in a description|t_passes_harness_in_description"
  "passes a harness command form in a README|t_passes_harness_in_readme"
  "hook stops a commit that adds a harness branch|t_hook_stops_harness_branch"
  "flags a Skill tool name in a skill file|t_flags_skill_tool_in_skill"
  "flags a listed copy with no license|t_flags_copy_without_license"
  "flags a shared core row with no owner license|t_flags_core_row_without_license"
  "passes a listed copy with its license|t_passes_copy_with_license"
  "hook stops a notices row with no license|t_hook_stops_row_without_license"
  "flags a skill with no README|t_flags_skill_without_readme"
  "flags a README with a missing heading|t_flags_missing_heading"
  "flags a listed skill with no Credits|t_flags_listed_without_credits"
  "flags a skill with a listed file and no Credits|t_flags_listed_file_without_credits"
  "passes a README with its headings|t_passes_readme_with_headings"
  "flags a SKILL.md with no frontmatter|t_flags_no_frontmatter"
  "flags a SKILL.md name that is not its folder|t_flags_name_not_folder"
  "flags a SKILL.md with an empty description|t_flags_empty_description"
  "readme hook stops a skill change without its README|t_readme_hook_stops_skill_change"
  "readme hook passes a skill change marked Readme: unchanged|t_readme_hook_passes_marked_change"
  "readme hook passes a skill change with its README|t_readme_hook_passes_with_readme"
  "Readme: unchanged still runs the leak check|t_marked_change_runs_leak_check"
  "Readme: unchanged still runs the header check|t_marked_change_runs_header_check"
  "commit hook stops a 51-character subject|t_subject_hook_stops_long_subject"
  "commit hook passes a 50-character subject|t_subject_hook_passes_50"
  "commit hook counts characters, not bytes|t_subject_hook_counts_characters"
  "commit hook lets a long Merge subject through|t_subject_hook_passes_merge"
  "commit hook lets a long Revert subject through|t_subject_hook_passes_revert"
  "commit hook lets the subject of a git merge through|t_subject_hook_passes_git_merge"
  "Readme marker does not skip the subject check|t_marked_change_runs_subject_check"
  "readme hook asks a skill that names a changed core file|t_readme_hook_asks_named_core"
  "readme hook asks a skill that names another file in the changed file's core folder|t_readme_hook_asks_core_folder"
  "readme hook asks a skill whose core file includes the changed file|t_readme_hook_asks_included_core"
  "readme hook passes a skill that reads no changed core file|t_readme_hook_skips_unread_core"
  "readme hook asks a skill whose core file names the changed file bare|t_readme_hook_asks_core_named_bare"
  "readme hook follows a bare core name that ends a sentence|t_readme_hook_asks_core_named_bare_at_end"
  "readme hook asks a skill whose bare-named core file the commit deletes|t_readme_hook_asks_core_named_bare_deleted"
  "readme hook follows a bare core name the work tree lacks but the commit holds|t_readme_hook_asks_core_named_bare_staged_only"
  "readme hook resolves a bare core name in its own folder only|t_readme_hook_skips_bare_name_in_other_folder"
  "passes a block description after a blank line|t_passes_block_after_blank"
  "passes a SKILL.md name with an inline comment|t_passes_name_with_comment"
  "flags a null description|t_flags_null_description"
  "flags a description that is only a comment|t_flags_comment_description"
  "flags a SKILL.md name with an escaped quote|t_flags_escaped_quote_name"
  "flags a SKILL.md body of 500 lines|t_flags_long_body"
  "passes a SKILL.md body of 499 lines|t_passes_body_under_limit"
  "flags a description over 1024 characters|t_flags_long_description"
  "passes a quoted description of 1024 characters|t_passes_description_at_limit"
  "flags a block description over 1024 characters|t_flags_long_block_description"
  "counts a description by characters, not bytes|t_counts_description_characters"
  "counts the nested indent of a block description|t_counts_block_nested_indent"
  "counts a folded block description|t_counts_folded_block_description"
  "flags a frontmatter that never closes|t_flags_unclosed_frontmatter"
  "flags a name over 64 characters|t_flags_long_name"
  "flags an AGENTS.md of 200 lines|t_flags_long_agents_md"
  "passes an AGENTS.md of 199 lines|t_passes_agents_md_under_limit"
  "flags a #! file with no run bit|t_flags_shebang_not_executable"
  "flags an agent file with no frontmatter|t_flags_agent_no_frontmatter"
  "flags an agent name that is not its file name|t_flags_agent_name_not_file"
  "flags an agent file with an empty description|t_flags_agent_empty_description"
  "flags an agent file with no Codex backup|t_flags_agent_no_codex_backup"
  "passes an agent file with a blank line and comments in a map|t_passes_agent_with_blank_and_comment_in_map"
  "flags an agent file with no Antigravity home|t_flags_agent_no_antigravity_home"
  "flags an agent file with a block description|t_flags_agent_block_description"
  "flags an agent file with a block name|t_flags_agent_block_name"
  "flags an agent file with an unknown harness|t_flags_agent_unknown_harness"
  "flags a backup model of another harness|t_flags_backup_model_of_other_harness"
  "flags an exact model as an Antigravity backup|t_flags_exact_antigravity_backup"
  "flags an effort the place cannot take|t_flags_effort_place_cannot_take"
  "flags a home in an unknown place|t_flags_home_in_unknown_place"
  "passes an agent file with two homes|t_passes_agent_with_two_homes"
  "flags a bad second home by its place|t_flags_bad_second_home"
  "flags an empty home|t_flags_empty_home"
  "passes an agent file with every field|t_passes_agent_with_all_fields"
  "flags a shared agent with no Codex backup|t_flags_shared_agent_no_codex_backup"
  "runner keeps a broken case out of the caller repo|t_runner_keeps_cases_out_of_caller"
)

# run_cases: run each case of `cases` in a subshell with set -e on, from a new
# empty temp folder that git finds no repo above, print `ok <name>` or
# `FAIL <name>: <why>`, and add to pass and fail.
run_cases() {
  local c name fn
  for c in "${cases[@]}"; do
    name="${c%%|*}"; fn="${c##*|}"
    rc=0; set +e; ( set -e; cd "$(mktemp -d)"; export GIT_CEILING_DIRECTORIES="$(dirname "$PWD")"; "$fn" ) >"$log" 2>&1; rc=$?; set -e
    if [ "$rc" -eq 0 ]; then
      printf 'ok %s\n' "$name"; pass=$((pass + 1))
    else
      printf 'FAIL %s: %s\n' "$name" "$(tail -1 "$log")"; fail=$((fail + 1))
    fi
  done
}

# Each skill's or shared core test file is sourced and its cases run before
# the next file is sourced, so a helper name in one file never replaces
# another file's.
pass=0; fail=0
log="$(mktemp)"
run_cases
for f in "$here"/../skills/*/tests/*.sh "$here"/../shared/tests/*.sh; do
  cases=(); . "$f"; run_cases
done
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
