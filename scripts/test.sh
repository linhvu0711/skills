#!/usr/bin/env bash
# test.sh: the tests for check.sh, the pre-commit and commit-msg hooks,
# adopt.sh, link.sh and the hooks that run it, and the handoff render.sh. It sources test-lib.sh, the helpers, the
# one fake gh, and the fake curl that every case shares, runs its own cases,
# then sources each skills/*/tests/*.sh and shared/tests/*.sh in
# turn and runs that file's cases.
#
#   test.sh
#
# Each case starts in an empty temp folder with set -e on, builds its own git
# repo in a temp folder, copies this scripts/ folder in, and runs the command
# there; the render case reads render.sh from this checkout. Every leak string
# below is joined
# from two halves at runtime, so this file holds nothing check.sh flags.
#
# Prints `ok <case>` or `FAIL <case>: <why>` per case, then
# `<p> passed, <f> failed`. Exit 1 when any case failed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
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

t_adopt_stops_on_bad_name() {
  skills_home "# demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh ..
  eq exit 1 "$code"
  eq stderr "stop: not a skill name: .." "$err"
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
  ANTIGRAVITY_SKILLS_HOME="$T/gskills" ANTIGRAVITY_PLUGINS_HOME="$T/gplugins" T3_ANTIGRAVITY_HOME="$T/t3" bash scripts/link.sh; }

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

t_link_replaces_old_agent_link() {
  # Given: the link an earlier link.sh made for the agent
  linked demo; agent demo helper; ln -s "$R/skills/demo/agents/helper.md" "$T/cagents/helper.md"
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/cagents/helper.md" "$out"
  [ ! -L "$T/cagents/helper.md" ] || eq "cagents/helper.md" "a file" "a link"
  eq "line 6" "model: claude-haiku-5-5" "$(sed -n 6p "$T/cagents/helper.md")"
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

t_link_writes_antigravity_form() {
  # Given: a skill with one agent file
  linked demo; agent demo helper
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/gplugins/skills/agents/helper.md" "$out"
  eq "antigravity form" "$(printf '%s\n' '---' \
    '# Made by scripts/link.sh from skills/demo/agents/helper.md. Edit that file, not this one.' \
    'name: helper' 'description: Reviews one "demo" diff.' 'subagent: true' 'mainAgent: false' \
    'model: inherit' 'tools: [read_file, run_command, manage_task]' '---' 'Review the diff.' \
    'Match \d+ in "x".')" "$(cat "$T/gplugins/skills/agents/helper.md")"
  link_sh
  eq "second run" "" "$out$err"
}

t_link_writes_plugin_manifest() {
  # Given: a skill with one agent file
  linked demo; agent demo helper
  # When
  link_sh
  # Then
  eq exit 0 "$code"
  has stdout "wrote $T/gplugins/skills/plugin.json" "$out"
  eq "manifest" "$(printf '%s\n' '{' '  "name": "skills",' \
    '  "description": "The skill agents of the skills repo, written by its scripts/link.sh."' '}')" \
    "$(cat "$T/gplugins/skills/plugin.json")"
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
  has stdout "removed $T/gplugins/skills/agents/helper.md" "$out"
  eq "ls cagents" aide.md "$(ls "$T/cagents")"
  eq "ls codex" aide.toml "$(ls "$T/codex")"
  eq "ls plugin agents" aide.md "$(ls "$T/gplugins/skills/agents")"
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

t_render_names_box() {
  T="$(mktemp -d)"
  run bash "$here/../shared/handoff/render.sh" local rules
  eq exit 0 "$code"
  eq "lines with ~/.agents or {{skills}}" 0 "$(printf '%s\n' "$out" | grep -cE '~/\.agents|\{\{skills\}\}' || true)"
  eq "lines with the box.sh path" 2 "$(printf '%s\n' "$out" | grep -c '/build-and-prove/scripts/box.sh' || true)"
  f="$(printf '%s\n' "$out" | grep -o 'bash [^ ]*/build-and-prove/scripts/box.sh' | sed 's/^bash //' | sort -u)"
  [ -f "$f" ] || eq "box.sh path" "a file" "$f"
}

t_render_names_handoff() {
  T="$(mktemp -d)"
  local ex
  for ex in devin cursor; do
    run bash "$here/../shared/handoff/render.sh" "$ex" prompt
    eq "$ex exit" 0 "$code"
    eq "$ex lines naming /handoff as caller" 1 "$(printf '%s\n' "$out" | grep -cF 'as `/handoff` resolved and created them' || true)"
    eq "$ex lines naming an old skill" 0 "$(printf '%s\n' "$out" | grep -cE 'handoff-(devin|cursor)' || true)"
  done
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
  "link links a new skill into every folder|t_link_links_new_skill"
  "link follows a renamed skill|t_link_follows_rename"
  "link leaves a name something else holds|t_link_leaves_other_names"
  "link does nothing in a worktree|t_link_skips_worktree"
  "link writes a skill agent's Claude Code form|t_link_writes_claude_form"
  "link replaces its old agent link with the file|t_link_replaces_old_agent_link"
  "link skips an agent file with no Claude Code backup|t_link_skips_agent_without_claude_backup"
  "link removes the forms of a renamed skill agent|t_link_removes_renamed_agent_forms"
  "link leaves an agent file it did not make|t_link_leaves_other_agent"
  "link writes a skill agent's Codex form|t_link_writes_codex_form"
  "link leaves a Codex agent file it did not make|t_link_leaves_other_codex_agent"
  "link writes a skill agent's Antigravity form|t_link_writes_antigravity_form"
  "link writes the skills plugin's manifest|t_link_writes_plugin_manifest"
  "link links the plugins folder into each T3 Antigravity folder|t_link_links_plugins_into_each_t3"
  "link says so when T3 has no Antigravity folder|t_link_skips_t3_when_none"
  "hooks link a skill on commit, checkout, and merge|t_hooks_link_committed_skill"
  "flags a missing path in a skill|t_flags_missing_own_path"
  "passes paths to another skill and the shared core|t_passes_skill_and_core_paths"
  "flags a missing path to another skill|t_flags_missing_skill_path"
  "reads a shared core path from its own folder|t_reads_core_path_from_own_folder"
  "skips placeholders and folders a skill does not have|t_skips_placeholders_and_other_folders"
  "allows a listed path in the user's repo|t_allows_listed_path"
  "flags a missing path after \$here in a script|t_flags_missing_here_path"
  "ignores paths outside skills and the shared core|t_ignores_paths_elsewhere"
  "hook stops a commit that adds a missing path|t_hook_stops_missing_path"
  "render puts the box.sh path in local rules|t_render_names_box"
  "render names /handoff as the caller for devin and cursor|t_render_names_handoff"
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
  "readme hook asks a skill that names a changed core file|t_readme_hook_asks_named_core"
  "readme hook asks a skill that names another file in the changed file's core folder|t_readme_hook_asks_core_folder"
  "readme hook asks a skill whose core file includes the changed file|t_readme_hook_asks_included_core"
  "readme hook passes a skill that reads no changed core file|t_readme_hook_skips_unread_core"
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
  "flags an agent file with an unknown harness|t_flags_agent_unknown_harness"
  "flags a backup model of another harness|t_flags_backup_model_of_other_harness"
  "flags an exact model as an Antigravity backup|t_flags_exact_antigravity_backup"
  "flags an effort the place cannot take|t_flags_effort_place_cannot_take"
  "flags a home in an unknown place|t_flags_home_in_unknown_place"
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
