#!/usr/bin/env bash
# test.sh: the tests for check.sh, the pre-commit and commit-msg hooks,
# adopt.sh, the handoff render.sh, the plan-up claims.py, and
# prune-worktrees.sh. It sources test-lib.sh, the helpers and the one fake gh
# that every case shares, runs its own cases, then sources each
# skills/*/tests/*.sh in turn and runs that file's cases.
#
#   test.sh
#
# Each case builds its own git repo in a temp folder, copies this scripts/
# folder in, and runs the command there; the render case runs in this
# checkout. Every leak string below is joined
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

# The prune-worktrees script, and the repos and fake gh its cases use.
P="$here/../skills/prune-worktrees/scripts/prune-worktrees.sh"

# wt_repo: repo, on a branch named main.
wt_repo() { repo; git branch -M main; }

# gh_remote: an origin on GitHub that is never contacted, with origin/main
# and origin/HEAD set from the local main.
gh_remote() {
  git remote add origin https://github.com/acme/app.git
  git update-ref refs/remotes/origin/main main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

# prune_gh: $T/bin/gh, which logs its arguments to $T/gh-calls. With
# GH_FAKE_FAIL set it fails as gh does offline. Else it prints the PR of the
# --head branch from $T/gh-prs, lines of `<branch> <number> <STATE> <sha>`.
prune_gh() {
  mkdir -p "$T/bin"; : > "$T/gh-prs"
  cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/gh-calls"
[ -z "\${GH_FAKE_FAIL:-}" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
b=""; while [ \$# -gt 0 ]; do [ "\$1" = --head ] && b="\$2"; shift; done
awk -v b="\$b" '\$1 == b { print \$2, \$3, \$4 }' "$T/gh-prs"
EOF
  chmod +x "$T/bin/gh"
}

# wt <dir> <branch> [n]: a worktree of the repo on a new branch from main,
# with n empty commits (1 when not given).
wt() {
  git worktree add -q -b "$2" "$1" main
  local i; for i in $(seq "${3:-1}"); do git -C "$1" commit -q --allow-empty -m "c$i"; done
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

t_flags_missing_own_path() {
  repo; mkdir -p skills/demo/scripts; printf 'hi\n' > skills/demo/scripts/ok.sh
  printf 'run `scripts/ok.sh`\nrun `scripts/nope.sh`\n' > skills/demo/SKILL.md
  run bash scripts/check.sh skills
  eq exit 1 "$code"
  eq "stderr line 1" "skills/demo/SKILL.md:2: missing path: scripts/nope.sh" "$(printf '%s\n' "$err" | sed -n 1p)"
  eq "last stderr line" "check: 1 problem(s) found" "$(printf '%s\n' "$err" | tail -1)"
}

t_passes_skill_and_core_paths() {
  repo; mkdir -p skills/a skills/b shared-skill-core
  printf 'hi\n' > skills/b/SKILL.md; printf 'hi\n' > shared-skill-core/x.md
  printf 'read `../b/SKILL.md:3` and ../../shared-skill-core/x.md.\n' > skills/a/SKILL.md
  run bash scripts/check.sh skills shared-skill-core
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
  repo; mkdir -p shared-skill-core/handoff; printf 'hi\n' > shared-skill-core/size.md
  printf '<!-- include ../size.md -->\nsee `../gone.md`\n' > shared-skill-core/handoff/rules.md
  run bash scripts/check.sh shared-skill-core
  eq exit 1 "$code"
  eq "stderr line 1" "shared-skill-core/handoff/rules.md:2: missing path: ../gone.md" "$(printf '%s\n' "$err" | sed -n 1p)"
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
  repo; mkdir shared-skill-core; printf 'hi\n' > shared-skill-core/x.md
  notices shared-skill-core/x.md "heavy adaptation"; git add -A; git commit -qm files
  run bash scripts/check.sh
  eq exit 1 "$code"
  eq "stderr line 1" "THIRD_PARTY_NOTICES.md:5: missing license: shared-skill-core/LICENSE-acme" "$(printf '%s\n' "$err" | sed -n 1p)"
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

# fake_gh_graphql: a temp folder T with a stub `gh` first on PATH. The stub reads
# the `number=<n>` argument, prints $T/gh/<n>.err to stderr and exits 1 when
# that file exists, else prints $T/gh/<n>.json, or $T/gh/<n>.<p>.<e>.json
# when it is asked for the closing PRs after cursor <p> or the events after
# cursor <e> (a cursor not asked for drops out of the name).
fake_gh_graphql() {
  T="$(mktemp -d)"; mkdir -p "$T/bin" "$T/gh"
  cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
p=""; e=""
for a in "$@"; do
  case "$a" in number=*) n="${a#number=}" ;; prAfter=*) p=".${a#prAfter=}" ;; eventAfter=*) e=".${a#eventAfter=}" ;; esac
done
d="$(dirname "$0")/../gh"
if [ -e "$d/$n.err" ]; then cat "$d/$n.err" >&2; exit 1; fi
cat "$d/$n$p$e.json"
EOF
  chmod +x "$T/bin/gh"
}

# issue_json <n> <assignees> <closing PRs> <timeline nodes> [<next> [<page>]]:
# write the `gh api graphql` answer for issue <n>, each list as JSON array
# items. <next>: the events go on after cursor <next>. <page>: this is the
# page after cursor <page>.
issue_json() {
  local more=false cursor=null
  [ -n "${5:-}" ] && { more=true; cursor="\"$5\""; }
  printf '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"assignees":{"nodes":[%s]},"closedByPullRequestsReferences":{"nodes":[%s],"pageInfo":{"hasNextPage":false,"endCursor":null}},"timelineItems":{"nodes":[%s],"pageInfo":{"hasNextPage":%s,"endCursor":%s}}}}}}\n' \
    "$2" "$3" "$4" "$more" "$cursor" > "$T/gh/$1${6:+.$6}.json"
}

claims() { run env PATH="$T/bin:$PATH" python3 "$here/../skills/plan-up/scripts/claims.py" o/r "$@"; }

pr70='{"number":70,"title":"Add the claim check","url":"https://github.com/o/r/pull/70","state":"OPEN","author":{"login":"bob"}}'
line70='#65 pr #70 "Add the claim check" @bob https://github.com/o/r/pull/70'

t_claims_closing_pr() {
  fake_gh_graphql; issue_json 65 '' "$pr70" ''
  claims 65
  eq exit 0 "$code"
  eq stdout "$line70" "$out"
}

t_claims_mentioning_pr() {
  fake_gh_graphql
  issue_json 65 '' '' '{"source":{"number":71,"title":"Refactor step 2","url":"https://github.com/o/r/pull/71","state":"OPEN","author":{"login":"carol"}}}'
  claims 65
  eq exit 0 "$code"
  eq stdout '#65 pr #71 "Refactor step 2" @carol https://github.com/o/r/pull/71' "$out"
}

t_claims_pr_once_open_only() {
  fake_gh_graphql
  issue_json 65 '' "$pr70" "{\"source\":$pr70},"'{"source":{"number":68,"title":"Old try","url":"https://github.com/o/r/pull/68","state":"MERGED","author":{"login":"bob"}}},{"source":{"number":69,"title":"Dropped","url":"https://github.com/o/r/pull/69","state":"CLOSED","author":{"login":"bob"}}},{"source":{}}'
  claims 65
  eq exit 0 "$code"
  eq stdout "$line70" "$out"
}

t_claims_next_page() {
  fake_gh_graphql
  issue_json 65 '' '' '' c1
  issue_json 65 '' '' '{"source":{"number":72,"title":"Late fix","url":"https://github.com/o/r/pull/72","state":"OPEN","author":{"login":"erin"}}}' '' c1
  claims 65
  eq exit 0 "$code"
  eq stdout '#65 pr #72 "Late fix" @erin https://github.com/o/r/pull/72' "$out"
}

t_claims_each_list_pages_on_its_own() {
  fake_gh_graphql
  pr71='{"number":71,"title":"Refactor step 2","url":"https://github.com/o/r/pull/71","state":"OPEN","author":{"login":"carol"}}'
  pr73='{"number":73,"title":"Second try","url":"https://github.com/o/r/pull/73","state":"OPEN","author":{"login":"dave"}}'
  printf '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"assignees":{"nodes":[]},"closedByPullRequestsReferences":{"nodes":[%s],"pageInfo":{"hasNextPage":true,"endCursor":"p1"}},"timelineItems":{"nodes":[{"source":%s}],"pageInfo":{"hasNextPage":false,"endCursor":"e1"}}}}}}\n' \
    "$pr70" "$pr71" > "$T/gh/65.json"
  printf '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"assignees":{"nodes":[]},"closedByPullRequestsReferences":{"nodes":[%s],"pageInfo":{"hasNextPage":false,"endCursor":"p2"}},"timelineItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n' \
    "$pr73" > "$T/gh/65.p1.e1.json"
  claims 65
  eq exit 0 "$code"
  eq stdout "$line70
#65 pr #71 \"Refactor step 2\" @carol https://github.com/o/r/pull/71
#65 pr #73 \"Second try\" @dave https://github.com/o/r/pull/73" "$out"
}

t_claims_other_assignee() {
  fake_gh_graphql; issue_json 65 '{"login":"me"},{"login":"dave"}' '' ''
  claims 65
  eq exit 0 "$code"
  eq stdout '#65 assignee @dave' "$out"
}

t_claims_none() {
  fake_gh_graphql; issue_json 65 '{"login":"me"}' '' ''
  claims 65
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_claims_each_issue() {
  fake_gh_graphql; issue_json 65 '' '' ''; issue_json 66 '{"login":"dave"}' '' ''
  claims 65 66
  eq exit 0 "$code"
  eq stdout '#66 assignee @dave' "$out"
}

t_claims_gh_fails() {
  fake_gh_graphql; printf 'gh: Could not resolve to an Issue with the number of 65.\n' > "$T/gh/65.err"
  claims 65
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'claims: #65: gh: Could not resolve to an Issue with the number of 65.' "$err"
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
  mkdir -p shared-skill-core/handoff
  printf 'hi\n' > shared-skill-core/x.md; printf 'hi\n' > shared-skill-core/size.md
  printf 'hi\n' > shared-skill-core/handoff/render.sh
  printf '<!-- include ../size.md -->\n' > shared-skill-core/handoff/rules.md
}

t_readme_hook_asks_named_core() {
  hooked; core; skill demo 'read `../../shared-skill-core/x.md`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared-skill-core/x.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_core_folder() {
  hooked; core; skill demo 'run `../../shared-skill-core/handoff/render.sh`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared-skill-core/handoff/rules.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_asks_included_core() {
  hooked; core; skill demo 'run `../../shared-skill-core/handoff/render.sh`'; git add -A; git commit -qm skill
  printf 'more\n' >> shared-skill-core/size.md; git add -A
  run git commit -m test
  [ "$code" -ne 0 ] || eq exit "not 0" "$code"
  has stderr "$(readme_msg skills/demo)" "$err"
  eq commits 2 "$(git rev-list --count HEAD)"
}

t_readme_hook_skips_unread_core() {
  hooked; core; skill demo 'read `../../shared-skill-core/x.md`'; skill other 'read `../../shared-skill-core/size.md`'
  git add -A; git commit -qm skills
  printf 'more\n' >> shared-skill-core/x.md; printf 'more\n' >> skills/demo/README.md; git add -A
  run git commit -m test
  eq exit 0 "$code"
  eq commits 3 "$(git rev-list --count HEAD)"
}

t_render_names_ready_pr() {
  T="$(mktemp -d)"
  run bash "$here/../shared-skill-core/handoff/render.sh" local rules
  eq exit 0 "$code"
  eq "lines with ~/.agents or {{skills}}" 0 "$(printf '%s\n' "$out" | grep -cE '~/\.agents|\{\{skills\}\}' || true)"
  eq "lines with the ready-pr path" 1 "$(printf '%s\n' "$out" | grep -c '/ready-pr/SKILL.md' || true)"
  f="$(printf '%s\n' "$out" | grep -o '`[^`]*/ready-pr/SKILL.md`' | tr -d '`')"
  [ -f "$f" ] || eq "ready-pr path" "a file" "$f"
}

t_prune_removes_merged() {
  wt_repo; gh_remote; prune_gh; wt "$T/elsewhere/feat-1-a" feat/1-a
  printf 'feat/1-a 43 MERGED %s\n' "$(git rev-parse feat/1-a)" > "$T/gh-prs"
  run env PATH="$T/bin:$PATH" bash "$P"
  eq exit 0 "$code"
  eq stdout "removed $T/elsewhere/feat-1-a, branch feat/1-a deleted (-D)" "$out"
  [ ! -e "$T/elsewhere/feat-1-a" ] || eq "$T/elsewhere/feat-1-a" "gone" "still there"
  eq "branch list" "" "$(git branch --list feat/1-a)"
}

t_prune_keeps_no_pr() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a
  git update-ref refs/remotes/origin/feat/1-a feat/1-a
  run env PATH="$T/bin:$PATH" bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s: no PR\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_dirty() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'a\n' > "$T/w/feat-1-a/a.txt"; printf 'b\n' > "$T/w/feat-1-a/b.txt"
  printf 'feat/1-a 43 MERGED %s\n' "$(git rev-parse feat/1-a)" > "$T/gh-prs"
  run env PATH="$T/bin:$PATH" bash "$P"
  eq stdout "$(printf 'kept %s: 2 uncommitted files\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_unpushed() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a 2
  run env PATH="$T/bin:$PATH" bash "$P"
  eq stdout "$(printf 'kept %s: 2 commits not on GitHub\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_open_pr() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'feat/1-a 159 OPEN %s\n' "$(git rev-parse feat/1-a)" > "$T/gh-prs"
  run env PATH="$T/bin:$PATH" bash "$P"
  eq stdout "$(printf 'kept %s: PR #159 open\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_moved_tip() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'feat/1-a 43 MERGED 0000000000000000000000000000000000000000\n' > "$T/gh-prs"
  run env PATH="$T/bin:$PATH" bash "$P"
  eq stdout "$(printf 'kept %s: PR #43 merged, tip is not its last commit\nnothing to prune' "$T/w/feat-1-a")" "$out"
  eq "branch list" "+ feat/1-a" "$(git branch --list feat/1-a)"
}

t_prune_git_only() {
  wt_repo; prune_gh; wt "$T/w/feat-2-b" feat/2-b
  git merge -q --ff-only feat/2-b
  run env PATH="$T/bin:$PATH" bash "$P"
  eq exit 0 "$code"
  eq stdout "removed $T/w/feat-2-b, branch feat/2-b deleted (-d)" "$out"
  [ ! -e "$T/gh-calls" ] || eq "gh calls" "none" "$(cat "$T/gh-calls")"
}

t_prune_gh_fails() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'feat/1-a 43 MERGED %s\n' "$(git rev-parse feat/1-a)" > "$T/gh-prs"
  run env PATH="$T/bin:$PATH" GH_FAKE_FAIL=1 bash "$P"
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "stop: gh failed: error connecting to api.github.com" "$err"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_skips_session() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'feat/1-a 43 MERGED %s\n' "$(git rev-parse feat/1-a)" > "$T/gh-prs"
  cd "$T/w/feat-1-a"; run env PATH="$T/bin:$PATH" bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s: this session is in it\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_clears_stale() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/gone" feat/9-x; rm -rf "$T/w/gone"
  run env PATH="$T/bin:$PATH" bash "$P"
  eq exit 0 "$code"
  eq stdout "cleared 1 stale entry" "$out"
  eq "worktree list lines" 1 "$(git worktree list | wc -l | tr -d ' ')"
}

t_prune_all() {
  wt_repo; gh_remote; prune_gh
  mkdir "$T/b"; git -C "$T/b" init -q -b main
  git -C "$T/b" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/b" worktree add -q -b feat/2-b "$T/root/b/feat-2-b" main
  git -C "$T/b" merge -q --ff-only feat/2-b
  run env PATH="$T/bin:$PATH" WORKTREES_ROOT="$T/root" bash "$P" all
  eq exit 0 "$code"
  eq stdout "removed $T/root/b/feat-2-b, branch feat/2-b deleted (-d)" "$out"
  [ ! -e "$T/root/b/feat-2-b" ] || eq "$T/root/b/feat-2-b" "gone" "still there"
}

t_prune_removes_named() {
  wt_repo; gh_remote; prune_gh; wt "$T/w/feat-3-c" feat/3-c; printf 'a\n' > "$T/w/feat-3-c/a.txt"
  run env PATH="$T/bin:$PATH" bash "$P" --remove "$T/w/feat-3-c"
  eq exit 0 "$code"
  eq stdout "removed $T/w/feat-3-c, branch feat/3-c kept: git branch -d refused" "$out"
  [ ! -e "$T/w/feat-3-c" ] || eq "$T/w/feat-3-c" "gone" "still there"
  eq "branch list" "  feat/3-c" "$(git branch --list feat/3-c)"
}

t_prune_nothing() {
  wt_repo; gh_remote; prune_gh
  run env PATH="$T/bin:$PATH" bash "$P"
  eq exit 0 "$code"
  eq stdout "nothing to prune" "$out"
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
  "flags a missing path in a skill|t_flags_missing_own_path"
  "passes paths to another skill and the shared core|t_passes_skill_and_core_paths"
  "flags a missing path to another skill|t_flags_missing_skill_path"
  "reads a shared core path from its own folder|t_reads_core_path_from_own_folder"
  "skips placeholders and folders a skill does not have|t_skips_placeholders_and_other_folders"
  "allows a listed path in the user's repo|t_allows_listed_path"
  "flags a missing path after \$here in a script|t_flags_missing_here_path"
  "ignores paths outside skills and the shared core|t_ignores_paths_elsewhere"
  "hook stops a commit that adds a missing path|t_hook_stops_missing_path"
  "render puts the ready-pr path in local rules|t_render_names_ready_pr"
  "claims names an open PR that closes the issue|t_claims_closing_pr"
  "claims names an open PR that only mentions the issue|t_claims_mentioning_pr"
  "claims lists a PR once and skips closed and merged PRs|t_claims_pr_once_open_only"
  "claims reads a PR on the next page of links|t_claims_next_page"
  "claims reads each list of links to its own end|t_claims_each_list_pages_on_its_own"
  "claims names an assignee other than the user|t_claims_other_assignee"
  "claims prints nothing when no one is on the issue|t_claims_none"
  "claims checks each issue of a run|t_claims_each_issue"
  "claims fails when gh fails|t_claims_gh_fails"
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
  "prune removes a merged worktree outside the root|t_prune_removes_merged"
  "prune keeps a branch with no PR|t_prune_keeps_no_pr"
  "prune says when there is nothing to prune|t_prune_nothing"
  "prune keeps a dirty worktree|t_prune_keeps_dirty"
  "prune keeps unpushed commits|t_prune_keeps_unpushed"
  "prune keeps an open PR|t_prune_keeps_open_pr"
  "prune keeps a merged PR whose tip moved|t_prune_keeps_moved_tip"
  "prune uses only git with no GitHub remote|t_prune_git_only"
  "prune stops and removes nothing when gh fails|t_prune_gh_fails"
  "prune skips the session's worktree|t_prune_skips_session"
  "prune clears a stale entry|t_prune_clears_stale"
  "prune all goes through every repo under the root|t_prune_all"
  "prune removes a named worktree and keeps an unmerged branch|t_prune_removes_named"
)

# run_cases: run each case of `cases` in a subshell, print `ok <name>` or
# `FAIL <name>: <why>`, and add to pass and fail.
run_cases() {
  local c name fn
  for c in "${cases[@]}"; do
    name="${c%%|*}"; fn="${c##*|}"
    if ( "$fn" ) >"$log" 2>&1; then
      printf 'ok %s\n' "$name"; pass=$((pass + 1))
    else
      printf 'FAIL %s: %s\n' "$name" "$(tail -1 "$log")"; fail=$((fail + 1))
    fi
  done
}

# Each skill's file is sourced and its cases run before the next file is
# sourced, so a helper name in one file never replaces another file's.
pass=0; fail=0
log="$(mktemp)"
run_cases
for f in "$here"/../skills/*/tests/*.sh; do
  cases=(); . "$f"; run_cases
done
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
