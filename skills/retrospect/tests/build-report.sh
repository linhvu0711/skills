# build-report.sh: the cases for this skill's build_report.py. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

t_rr_builds_twice() {
  # Given: the smallest cards file the builder takes, one card
  T="$(cd "$(mktemp -d)" && pwd -P)"; cd "$T"
  printf '{"repo":"o/r","scope":"s","window":"w","counts":"1 card","read":"r","items":[],"cards":[{"title":"Keep one copy","badge":"Tip","kind":"skill","home":"o/r","items":[],"quotes":[],"where":["a.sh"],"cost":"c","did_not_hold":"d","fix":"f","open":"o","texts":[],"times":"1"}],"questions":[],"top_why":"w"}\n' > cards.json
  # When: the page is built twice
  run python3 "$here/../scripts/build_report.py" cards.json
  eq exit 0 "$code"; eq stdout "page: report.html" "$out"
  cp report.html first.html
  run python3 "$here/../scripts/build_report.py" cards.json
  # Then
  eq exit 0 "$code"; eq stdout "page: report.html" "$out"
  has page "Keep one copy" "$(cat report.html)"
  [ ! -e report.html.tmp ] || eq "temp file" none report.html.tmp
  cmp -s first.html report.html || eq "second page" "same bytes" "changed"
}

cases=(
  "retro report: builds its page, twice|t_rr_builds_twice"
)
