# gh.sh: the cases for the shared core's gh.sh, the one way a shell script
# runs gh. The repo's test.sh sources this file after test-lib.sh and runs its
# cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The shell helper.
G="$here/../gh.sh"

# gh_fails: the fake gh, whose `repo view` fails with a hint first, the error
# next, and a blank line last.
gh_fails() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf 'A new release of gh is available\nHTTP 502: Bad Gateway\n\n' > "$FAKE_GH/repo-view.fail"
}

t_gh_out_last_line() {
  # Given: repo view fails with a hint, then the error
  gh_fails
  # When
  run bash -c '. "$1"; gh_out repo view || printf "%s" "$err"' _ "$G"
  # Then
  eq stdout "HTTP 502: Bad Gateway" "$out"
}

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

t_gh_or_stop_last_line() {
  # Given: repo view fails with a hint, then the error
  gh_fails
  # When
  run bash -c '. "$1"; gh_or_stop repo view; echo after' _ "$G"
  # Then
  eq stop "1||stop: gh failed: HTTP 502: Bad Gateway" "$code|$out|$err"
}

cases=(
  "gh_out keeps gh's last error line|t_gh_out_last_line"
  "gh_out keeps a hint out of the answer|t_gh_out_hint_kept_out"
  "gh_or_stop stops with gh's last error line|t_gh_or_stop_last_line"
)
