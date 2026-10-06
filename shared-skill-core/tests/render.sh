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
  eq "risk line" 1 "$(grep -c '^   First line, always: `Risk: <door> door, blast radius: <what>.`$' "$here/../pr-shape.md")"
  eq "one place" 1 "$(grep -c 'keeps only the `Risk`' "$here/../pr-shape.md")"
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

cases=(
  "local rules run every command through box.sh|t_render_local_box"
  "devin rules still open the PR|t_render_devin_pr"
  "pr-shape holds the media rules and devin rules carry them once|t_render_media_once"
  "pr-shape opens Where to look with the Risk line|t_render_risk_line"
  "cloud rules carry the Risk line once|t_render_cloud_risk_once"
  "local rules run each slice's checks here|t_render_local_split"
  "local rules leave the Gates to the Sandbox|t_render_local_gates"
  "local rules start the Sandbox on a missing tool|t_render_local_missing_tool"
  "cloud rules still run the full suite|t_render_cloud_full_suite"
)
