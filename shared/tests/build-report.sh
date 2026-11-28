# build-report.sh: the cases for the shared core's clean-codebase
# build_report.py. The repo's test.sh sources this file after test-lib.sh and
# runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

t_cr_builds_twice() {
  # Given: the smallest rows file the builder takes
  T="$(cd "$(mktemp -d)" && pwd -P)"; cd "$T"
  printf '{"skill":"prune-codebase","repo":"o/r","commit":"abc1234","date":"2026-11-28","scope":"whole repo","new":0,"kinds":[],"changes":[],"rows":[]}\n' > rows.json
  # When: the page is built twice
  run python3 "$here/../clean-codebase/build_report.py" rows.json
  eq exit 0 "$code"; eq stdout "page: rows.html" "$out"
  cp rows.html first.html
  run python3 "$here/../clean-codebase/build_report.py" rows.json
  # Then
  eq exit 0 "$code"; eq stdout "page: rows.html" "$out"
  eq "theme lines" 1 "$(grep -c -- '--bg: #f6f7f9;' rows.html)"
  eq "DATA repo" o/r "$(sed -n 's/^ *const DATA = \(.*\);$/\1/p' rows.html | jq -r .repo)"
  [ ! -e rows.html.tmp ] || eq "temp file" none rows.html.tmp
  cmp -s first.html rows.html || eq "second page" "same bytes" "changed"
}

cases=(
  "clean report: builds its page with data and theme, twice|t_cr_builds_twice"
)
