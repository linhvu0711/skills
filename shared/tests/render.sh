# render.sh: the cases for the executor templates, read through render.sh's
# output. The repo's test.sh sources this file after test-lib.sh and runs its
# cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

render() { T="$(cd "$(mktemp -d)" && pwd -P)"; run bash "$here/../handoff/render.sh" "$@"; }

t_render_local_box() {
  render local rules
  eq exit 0 "$code"
  has "box.sh" "box.sh run" "$out"
  has "end line" "BUILT" "$out"
  lacks "pr create" "gh pr create" "$out"
}

t_render_devin_pr() {
  render devin rules
  eq exit 0 "$code"
  has "pr" "One PR per layer" "$out"
  lacks "box.sh" "box.sh" "$out"
}

t_render_media_once() {
  render devin rules
  eq exit 0 "$code"
  eq "pr-shape" 1 "$(grep -c '^ *### Screenshots$' "$here/../pr-shape.md")"
  eq "devin rules" 1 "$(printf '%s\n' "$out" | grep -c '^ *### Screenshots$')"
}

t_render_demo_after_summary() {
  # Given: the PR shape and the devin rules that paste it
  local item
  item="$(sed -n '/^3\. /,/^4\. /p' "$here/../pr-shape.md")"
  # When
  render devin rules
  # Then
  eq exit 0 "$code"
  eq "item 3" '3. **`## Demo`**' "$(printf '%s\n' "$item" | sed -n 1p | cut -c1-16)"
  eq "screenshots then videos" "Screenshots,Videos" "$(printf '%s\n' "$item" | sed -nE 's/^   - (Screenshots|Videos), under .*/\1/p' | paste -sd, -)"
  eq "devin rules" 1 "$(printf '%s\n' "$out" | grep -c '^3\. \*\*`## Demo`\*\*')"
  eq "media only" 1 "$(printf '%s\n' "$item" | grep -c 'Only a PR with screenshots or videos has it')"
}

t_render_proof_seen_in() {
  # Given: the Proof part of the PR shape
  local item
  # When
  item="$(sed -n '/^6\. \*\*`## Proof`\*\*/,/^7\. /p' "$here/../pr-shape.md")"
  # Then
  eq "Seen in header" 1 "$(printf '%s\n' "$item" | grep -c '^ *| # | Behavior | Test | Seen in |$')"
  eq "old media columns" 0 "$(printf '%s\n' "$item" | grep -c '| Screenshot | Video |' || true)"
}

t_render_test_link_file_name() {
  # Given: the Proof part of the PR shape
  local item
  item="$(sed -n '/^6\. \*\*`## Proof`\*\*/,/^7\. /p' "$here/../pr-shape.md")"
  # When: test links whose text holds a folder are counted
  # Then
  eq "links with a folder" 0 "$(printf '%s\n' "$item" | grep -cE '\[`[^`]*/[^`]*` "' || true)"
  eq "rule" 1 "$(printf '%s\n' "$item" | grep -c "\`Test\` is the test file's name and the case name")"
}

t_render_breaking_steps_only() {
  # Given: the Breaking changes part of the PR shape
  local item
  # When
  item="$(sed -n '/^5\. \*\*`## Breaking changes`\*\*/,/^6\. /p' "$here/../pr-shape.md")"
  # Then
  eq "steps only" 1 "$(printf '%s\n' "$item" | grep -c 'the steps alone, since the `Risk` line already says a revert cannot undo it')"
}

t_render_risk_line() {
  local item
  item="$(sed -n '/^4\. \*\*`## Where to look`\*\*/,/^5\. /p' "$here/../pr-shape.md")"
  eq "risk line" 1 "$(printf '%s\n' "$item" | grep -c '^   First line, always: `Risk: <door> door, blast radius: <what>.`$')"
  eq "one place" 1 "$(printf '%s\n' "$item" | grep -c 'keeps only the `Risk`')"
}

t_render_title_result() {
  eq "title rule" 1 "$(grep -c 'not how it works inside' "$here/../pr-shape.md")"
  render devin rules
  eq exit 0 "$code"
  eq "devin rules" 1 "$(printf '%s\n' "$out" | grep -c 'not how it works inside')"
}

t_render_summary_problem() {
  local item
  item="$(sed -n '/^2\. \*\*`## Summary`\*\*/,/^3\. /p' "$here/../pr-shape.md")"
  eq "summary" 1 "$(printf '%s\n' "$item" | grep -c '^2\. \*\*`## Summary`\*\*: first the problem')"
}

t_render_cloud_risk_once() {
  render devin rules
  eq exit 0 "$code"
  eq "devin rules" 1 "$(printf '%s\n' "$out" | grep -c 'Risk: <door> door, blast radius: <what>.')"
  render cursor rules
  eq exit 0 "$code"
  eq "cursor rules" 1 "$(printf '%s\n' "$out" | grep -c 'Risk: <door> door, blast radius: <what>.')"
}

t_render_local_split() {
  render local rules
  eq exit 0 "$code"
  has "slice checks" "Each slice's tests, the typecheck, and lint run here" "$out"
  lacks "old rule" "Never run one of those commands here" "$out"
}

t_render_local_gates() {
  render local rules
  eq exit 0 "$code"
  has "gates" "runs in the run's proofbox Sandbox the Gates the PR's CI does not run" "$out"
  lacks "full suite" "Run the full test suite" "$out"
}

t_render_local_missing_tool() {
  render local rules
  eq exit 0 "$code"
  has "missing tool" "command not found" "$out"
  has "box.sh up" "box.sh up <Proof folder> <Worktree> <os> <Repo>" "$out"
}

t_render_cloud_full_suite() {
  render devin rules
  eq exit 0 "$code"
  has "full suite" "Run the full test suite, typecheck, lint, and build" "$out"
}

t_render_local_red_rule() {
  render local rules
  eq exit 0 "$code"
  # The rule wraps, so its lines are joined first.
  has "red rule" "A missing symbol, an import error, or a crash before the assertion is not red" "$(printf '%s' "$out" | tr -s ' \n' '  ')"
}

# every_rules_hold <needle>: each executor's rules, their lines joined since a
# rule wraps, hold the needle.
every_rules_hold() {
  local ex
  for ex in local devin cursor; do
    render "$ex" rules
    eq "$ex exit" 0 "$code"
    has "$ex rules" "$1" "$(printf '%s' "$out" | tr -s ' \n' '  ')"
  done
}

t_render_belief_rule() {
  every_rules_hold "before a third fix, write down the cause you believe, and one check that shows whether it is the cause"
}

t_render_mutate_copy_rule() {
  local ex
  every_rules_hold "Copy the file back from the temp folder, so \`cmp <file> <copy>\` exits 0"
  for ex in local devin cursor; do
    render "$ex" rules
    lacks "$ex rules" 'git diff --quiet -- <file>' "$(printf '%s' "$out" | tr -s ' \n' '  ')"
  done
}

t_render_mutate_no_git_rule() {
  every_rules_hold "Never undo the edit with \`git checkout\`, \`git restore\`, or \`git stash\`"
}

t_render_same_kind_rule() {
  every_rules_hold "means the design may be wrong: **stop and ask**, rather than pick the nearest pattern again"
}

t_render_standard_first_rule() {
  every_rules_hold "take the way the repo's Standard names for it, else the nearest existing pattern"
}

t_render_same_kind_before_fallback() {
  local ex same any
  for ex in local devin cursor; do
    render "$ex" rules
    eq "$ex exit" 0 "$code"
    same="$(printf '%s\n' "$out" | grep -n '^- A second surprise of the same kind' | cut -d: -f1)"
    any="$(printf '%s\n' "$out" | grep -n '^- Anything else: \*\*take the way the repo.s Standard names' | cut -d: -f1)"
    eq "$ex same-kind rule before the fallback" yes "$([ -n "$same" ] && [ -n "$any" ] && [ "$same" -lt "$any" ] && echo yes || echo no)"
  done
}

t_render_comment_rule() {
  every_rules_hold "Keep a comment in the code you write only when it says why"
}

t_render_edge_rule() {
  every_rules_hold "Check data at the edge where it comes in"
}

t_render_cloud_perf_row() {
  render devin rules
  eq exit 0 "$code"
  has "perf row" "1200 → 280" "$out"
}

t_render_cloud_perf() {
  render devin rules
  eq exit 0 "$code"
  has "perf part" "## A perf plan" "$out"
  eq "checklist" 1 "$(printf '%s\n' "$out" | grep -c '^### Alternate$')"
}

t_render_local_no_perf() {
  render local rules
  eq exit 0 "$code"
  lacks "perf part" "## A perf plan" "$out"
}

t_render_prompt_perf() {
  render devin prompt
  eq exit 0 "$code"
  has "cloud prompt" "# Perf" "$out"
  render local prompt
  eq exit 0 "$code"
  lacks "local prompt" "# Perf" "$out"
}

t_render_cloud_perf_drift() {
  render devin rules
  eq exit 0 "$code"
  has "drift note" "(issue Baseline: 1200 ms, spread 1150 to 1260 ms)" "$out"
}

t_render_cloud_perf_refix() {
  render devin rules
  eq exit 0 "$code"
  has "measure again" "measure again, steps 1 to 5, before its push" "$(printf '%s' "$out" | tr -s ' \n' '  ')"
}

t_render_local_writing() {
  render local rules
  eq exit 0 "$code"
  has "agent files" "write-for-agents/SKILL.md" "$out"
  has "prose" "unslop/SKILL.md" "$out"
  lacks "skills word" "{{skills}}" "$out"
}

t_render_cloud_no_writing() {
  local ex
  for ex in devin cursor; do
    render "$ex" rules
    eq "$ex exit" 0 "$code"
    lacks "$ex prose" "unslop/SKILL.md" "$out"
    lacks "$ex agent files" "write-for-agents/SKILL.md" "$out"
  done
}

t_render_local_look_change() {
  render local rules
  eq exit 0 "$code"
  has "look change" "It changes the look of a screen the issue does not name" "$out"
}

t_render_local_e2e() {
  render local rules
  eq exit 0 "$code"
  has "e2e" "run the e2e spec files the slice changes" "$out"
}

t_render_cloud_no_e2e() {
  local ex
  for ex in devin cursor; do
    render "$ex" rules
    eq "$ex exit" 0 "$code"
    lacks "$ex e2e" "run the e2e spec files the slice changes" "$out"
  done
}

t_render_cloud_no_look_change() {
  local ex
  for ex in devin cursor; do
    render "$ex" rules
    eq "$ex exit" 0 "$code"
    lacks "$ex look change" "It changes the look of a screen the issue does not name" "$out"
  done
}

t_render_local_no_ui() {
  render local rules
  eq exit 0 "$code"
  has "no sandbox" "With \`UI: none\` under \`Facts\`, there is no Sandbox" "$out"
}

t_render_local_no_pane() {
  # Given: the local templates on this branch
  # When
  render local rules
  rules_code="$code"; rules="$out"
  render local prompt
  # Then
  eq "rules exit" 0 "$rules_code"
  eq "prompt exit" 0 "$code"
  for needle in pane QUESTION; do
    lacks "rules" "$needle" "$rules"
    lacks "prompt" "$needle" "$out"
  done
}

t_render_names_box() {
  # Given: the local rules template
  # When
  render local rules
  # Then
  eq exit 0 "$code"
  eq "lines with ~/.agents or {{skills}}" 0 "$(printf '%s\n' "$out" | grep -cE '~/\.agents|\{\{skills\}\}' || true)"
  eq "lines with the box.sh path" 2 "$(printf '%s\n' "$out" | grep -c '/build-and-prove/scripts/box.sh' || true)"
  local f
  f="$(printf '%s\n' "$out" | grep -o 'bash [^ ]*/build-and-prove/scripts/box.sh' | sed 's/^bash //' | sort -u)"
  [ -f "$f" ] || eq "box.sh path" "a file" "$f"
}

t_render_names_handoff() {
  # Given: the devin and cursor prompt templates
  local ex
  for ex in devin cursor; do
    # When
    render "$ex" prompt
    # Then
    eq "$ex exit" 0 "$code"
    eq "$ex lines naming /dispatch as caller" 1 "$(printf '%s\n' "$out" | grep -cF 'as `/dispatch` resolved and created them' || true)"
    eq "$ex lines naming an old skill" 0 "$(printf '%s\n' "$out" | grep -cE 'handoff-(devin|cursor)' || true)"
  done
}

t_render_cloud_count_script() {
  # Given: the shared count script
  # When
  render devin rules
  # Then
  eq exit 0 "$code"
  has script "$(cat "$here/../size.py")" "$out"
}

t_render_cloud_six_size_labels() {
  # Given: the prompt template
  # When
  render devin prompt
  # Then
  has labels 'XL size/XL · XXL size/XXL' "$out"
}

cases=(
  "local templates name no pane and no QUESTION line|t_render_local_no_pane"
  "local rules start no Sandbox for a plan with no UI|t_render_local_no_ui"
  "local rules run every command through box.sh|t_render_local_box"
  "devin rules still open the PR|t_render_devin_pr"
  "pr-shape holds the media rules and devin rules carry them once|t_render_media_once"
  "pr-shape puts Demo right after Summary|t_render_demo_after_summary"
  "pr-shape Proof has one Seen in column|t_render_proof_seen_in"
  "pr-shape test links show the file name|t_render_test_link_file_name"
  "pr-shape Breaking changes gives steps only|t_render_breaking_steps_only"
  "pr-shape opens Where to look with the Risk line|t_render_risk_line"
  "cloud rules carry the Risk line once|t_render_cloud_risk_once"
  "pr-shape titles name the result, and cloud rules carry it|t_render_title_result"
  "pr-shape Summary opens with the problem|t_render_summary_problem"
  "local rules run each slice's checks here|t_render_local_split"
  "local rules leave the Gates to the Sandbox|t_render_local_gates"
  "local rules start the Sandbox on a missing tool|t_render_local_missing_tool"
  "cloud rules still run the full suite|t_render_cloud_full_suite"
  "local rules hold the red rule for a Red test|t_render_local_red_rule"
  "every executor's rules test a belief before a third fix|t_render_belief_rule"
  "every executor's rules put a Mutate break back from a copy|t_render_mutate_copy_rule"
  "every executor's rules never undo a Mutate break with git|t_render_mutate_no_git_rule"
  "every executor's rules stop on a second surprise of one kind|t_render_same_kind_rule"
  "every executor's rules sort the same-kind stop before the nearest-pattern fallback|t_render_same_kind_before_fallback"
  "every executor's rules take the Standard's way before the nearest pattern|t_render_standard_first_rule"
  "every executor's rules keep a comment only when it says why|t_render_comment_rule"
  "every executor's rules check data at the edge|t_render_edge_rule"
  "cloud rules carry the perf row|t_render_cloud_perf_row"
  "cloud rules show a drifted base next to the issue's Baseline|t_render_cloud_perf_drift"
  "cloud rules measure a perf PR again after a review fix|t_render_cloud_perf_refix"
  "cloud rules carry the perf part and its checklist once|t_render_cloud_perf"
  "local rules leave the perf part out|t_render_local_no_perf"
  "cloud prompt has a Perf heading and local has none|t_render_prompt_perf"
  "local rules name the writing skills|t_render_local_writing"
  "cloud rules leave the writing skills out|t_render_cloud_no_writing"
  "local rules stop on a look change the issue does not name|t_render_local_look_change"
  "cloud rules leave the look-change stop out|t_render_cloud_no_look_change"
  "local rules run a slice's e2e specs in the Sandbox|t_render_local_e2e"
  "cloud rules leave the per-slice e2e rule out|t_render_cloud_no_e2e"
  "render puts the box.sh path in local rules|t_render_names_box"
  "render names /dispatch as the caller for devin and cursor|t_render_names_handoff"
  "cloud rules carry the count script|t_render_cloud_count_script"
  "cloud prompt lists six size labels|t_render_cloud_six_size_labels"
)
