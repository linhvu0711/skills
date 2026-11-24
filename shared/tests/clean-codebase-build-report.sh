# clean-codebase-build-report.sh: a rows file in, the report page's DATA out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

cb_build() { run python3 "$here/../clean-codebase/build-report.py" "$@"; }
cb_data() { sed -n 's/^const DATA = \(.*\);$/\1/p' "$1" | jq -S .; }

# cb_rows <jq filter>: the fixture rows file, changed by the filter, at $T/clean-prune-codebase-acme-shop.json
cb_rows() {
  T="$(mktemp -d)"
  jq "$1" "$here/clean-codebase-build-report/report.json" > "$T/clean-prune-codebase-acme-shop.json"
}

t_cb_builds_report() {
  # Given: the fixture rows file
  cb_rows .
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq stdout "page: $T/clean-prune-codebase-acme-shop.html" "$out"
  eq DATA "$(jq -S . "$here/clean-codebase-build-report/report-data.json")" "$(cb_data "$T/clean-prune-codebase-acme-shop.html")"
}

t_cb_nothing_found() {
  # Given: no rows and no changes
  cb_rows '.rows = [] | .changes = []'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq DATA '"I found nothing to change." []' "$(cb_data "$T/clean-prune-codebase-acme-shop.html" | jq -c '.summary, .rows' | tr '\n' ' ' | sed 's/ $//')"
}

t_cb_nothing_to_fix() {
  # Given: no rows, with the fixture's three changes kept
  cb_rows '.rows = []'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq summary "I found nothing to fix." "$(cb_data "$T/clean-prune-codebase-acme-shop.html" | jq -r .summary)"
}

t_cb_refuses_advice() {
  # Given: R2 with an advice the report does not know
  cb_rows '(.rows[] | select(.id == "R2") | .advice) = "delete"'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout 'row R2: advice "delete" is not fix, keep-and-mark, or fine' "$out"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_label() {
  # Given: R1's second place labelled Guess
  cb_rows '(.rows[] | select(.id == "R1") | .places[1].label) = "Guess"'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout 'row R1 place 2: label "Guess" is not Seen or Inferred' "$out"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_known_no_ticket() {
  # Given: the Known row R5 with no ticket
  cb_rows '(.rows[] | select(.id == "R5") | .ticket) = ""'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout 'row R5: known needs a ticket' "$out"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_builds_twice() {
  # Given: the fixture rows file, built once
  cb_rows .
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  cp "$T/clean-prune-codebase-acme-shop.html" "$T/first"
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq same "same" "$(cmp -s "$T/first" "$T/clean-prune-codebase-acme-shop.html" && echo same || echo differs)"
}

t_cb_keeps_old_page() {
  # Given: the fixture built once, then R2 given an advice the report does not know
  cb_rows .
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  cp "$T/clean-prune-codebase-acme-shop.html" "$T/first"
  jq '(.rows[] | select(.id == "R2") | .advice) = "delete"' "$T/clean-prune-codebase-acme-shop.json" > "$T/bad.json"
  mv "$T/bad.json" "$T/clean-prune-codebase-acme-shop.json"
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq same "same" "$(cmp -s "$T/first" "$T/clean-prune-codebase-acme-shop.html" && echo same || echo differs)"
}

t_cb_escapes_tags_in_text() {
  # Given: R1's first place is the first line of a commented-out script
  cb_rows '(.rows[] | select(.id == "R1") | .places[0].text) = "<!-- <script src=\"old.js\">"'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq scripts 2 "$(grep -o '<script' "$T/clean-prune-codebase-acme-shop.html" | wc -l | tr -d ' ')"
  eq text '<!-- <script src="old.js">' "$(cb_data "$T/clean-prune-codebase-acme-shop.html" | jq -r '.rows[] | select(.id == "R1") | .places[0].text')"
}

t_cb_row_with_no_state() {
  # Given: the rows with an empty state have no state key at all
  cb_rows '(.rows[] | select(.state == "")) |= del(.state)'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq summary "$(jq -r .summary "$here/clean-codebase-build-report/report-data.json")" "$(cb_data "$T/clean-prune-codebase-acme-shop.html" | jq -r .summary)"
}

cases=(
  "builds the report page with its counts|t_cb_builds_report"
  "says nothing found for no rows|t_cb_nothing_found"
  "says nothing to fix for no rows with a change|t_cb_nothing_to_fix"
  "refuses an advice it does not know|t_cb_refuses_advice"
  "refuses a place label that is not Seen or Inferred|t_cb_refuses_label"
  "refuses a Known row with no ticket|t_cb_refuses_known_no_ticket"
  "builds the same page twice|t_cb_builds_twice"
  "keeps the old page after a bad build|t_cb_keeps_old_page"
  "escapes tags in a place's text|t_cb_escapes_tags_in_text"
  "builds a row with no state|t_cb_row_with_no_state"
)
