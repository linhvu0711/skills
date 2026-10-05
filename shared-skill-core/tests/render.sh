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

cases=(
  "local rules run every command through box.sh|t_render_local_box"
  "devin rules still open the PR|t_render_devin_pr"
)
