# check.sh: the cases for scripts/check.sh and the pre-commit and commit-msg
# hooks that run it. tests/run.sh sources this file after lib.sh and runs its
# cases. Every leak string below is joined from two halves at runtime, so this
# file holds nothing check.sh flags.

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

cases=(
  "flags a home path|t_flags_home_path"
  "flags a linux home path|t_flags_linux_home_path"
  "passes a clean file|t_passes_clean_file"
  "flags an email|t_flags_email"
  "hook stops a commit that adds a private word|t_hook_stops_private_word"
  "hook stops a commit that adds a home path|t_hook_stops_home_path"
  "flags a private word in an added path|t_flags_private_word_in_path"
  "tree mode scans every tracked file|t_tree_scans_tracked_files"
  "scans a path given from a subfolder|t_scans_path_from_subfolder"
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
)
