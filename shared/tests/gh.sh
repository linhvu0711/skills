# gh.sh: the cases for the shared core's gh.sh, the one way a shell script
# runs gh. The repo's test.sh sources this file after test-lib.sh and runs its
# cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

G="$here/../gh.sh"

t_gh_out_hint_kept_out() {
  # Given: repo view answers, and prints a hint on stderr beside it
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"name":"app"}\n' > "$FAKE_GH/repo-view.json"
  printf 'A new release of gh is available\n' > "$FAKE_GH/repo-view.stderr"
  # When
  run bash -c '. "$1"; gh_out repo view && printf "%s" "$out"' _ "$G"
  # Then
  eq answer "0 {\"name\":\"app\"}" "$code $out"
}

cases=(
  "gh_out keeps a hint out of the answer|t_gh_out_hint_kept_out"
)
