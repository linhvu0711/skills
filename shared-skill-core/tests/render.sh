# render.sh: the cases for the executor templates, read through render.sh's
# output. The repo's test.sh sources this file after test-lib.sh and runs its
# cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

render() { T="$(cd "$(mktemp -d)" && pwd -P)"; run bash "$here/../handoff/render.sh" "$@"; }

# lacks <name> <needle> <haystack>: fail when the needle is in the haystack.
lacks() { case "$3" in *"$2"*) printf '%s: [%s] found\n' "$1" "$2" >&2; exit 1 ;; esac; }

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

t_render_risk_line() {
  local item
  item="$(sed -n '/^3\. \*\*`## Where to look`\*\*/,/^4\. /p' "$here/../pr-shape.md")"
  eq "risk line" 1 "$(printf '%s\n' "$item" | grep -c '^   First line, always: `Risk: <door> door, blast radius: <what>.`$')"
  eq "one place" 1 "$(printf '%s\n' "$item" | grep -c 'keeps only the `Risk`')"
}

t_render_title_result() {
  eq "title rule" 1 "$(grep -c 'not how it works inside' "$here/../pr-shape.md")"
  render devin rules
  eq exit 0 "$code"
  eq "devin rules" 1 "$(printf '%s\n' "$out" | grep -c 'not how it works inside')"
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
  has "gates" "runs the Gates in the run's proofbox Sandbox" "$out"
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

t_render_same_kind_rule() {
  every_rules_hold "means the design may be wrong: **stop and ask**, rather than pick the nearest pattern again"
}

t_render_same_kind_before_fallback() {
  local ex same any
  for ex in local devin cursor; do
    render "$ex" rules
    eq "$ex exit" 0 "$code"
    same="$(printf '%s\n' "$out" | grep -n '^- A second surprise of the same kind' | cut -d: -f1)"
    any="$(printf '%s\n' "$out" | grep -n '^- Anything else: \*\*pick the nearest existing pattern' | cut -d: -f1)"
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

cases=(
  "local rules run every command through box.sh|t_render_local_box"
  "devin rules still open the PR|t_render_devin_pr"
  "pr-shape holds the media rules and devin rules carry them once|t_render_media_once"
  "pr-shape opens Where to look with the Risk line|t_render_risk_line"
  "cloud rules carry the Risk line once|t_render_cloud_risk_once"
  "pr-shape titles name the result, and cloud rules carry it|t_render_title_result"
  "local rules run each slice's checks here|t_render_local_split"
  "local rules leave the Gates to the Sandbox|t_render_local_gates"
  "local rules start the Sandbox on a missing tool|t_render_local_missing_tool"
  "cloud rules still run the full suite|t_render_cloud_full_suite"
  "local rules hold the red rule for a Red test|t_render_local_red_rule"
  "every executor's rules test a belief before a third fix|t_render_belief_rule"
  "every executor's rules stop on a second surprise of one kind|t_render_same_kind_rule"
  "every executor's rules sort the same-kind stop before the nearest-pattern fallback|t_render_same_kind_before_fallback"
  "every executor's rules keep a comment only when it says why|t_render_comment_rule"
  "every executor's rules check data at the edge|t_render_edge_rule"
  "cloud rules carry the perf row|t_render_cloud_perf_row"
  "cloud rules show a drifted base next to the issue's Baseline|t_render_cloud_perf_drift"
  "cloud rules measure a perf PR again after a review fix|t_render_cloud_perf_refix"
  "cloud rules carry the perf part and its checklist once|t_render_cloud_perf"
  "local rules leave the perf part out|t_render_local_no_perf"
  "cloud prompt has a Perf heading and local has none|t_render_prompt_perf"
)
