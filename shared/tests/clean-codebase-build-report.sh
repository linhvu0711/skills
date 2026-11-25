# clean-codebase-build-report.sh: a rows file in, the report page's DATA out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

cb_build() { run python3 "$here/../clean-codebase/build_report.py" "$@"; }
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
  eq stdout "" "$out"
  eq stderr 'row R2: advice "delete" is not fix, keep-and-mark, or fine' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_not_checked() {
  # Given: not_checked as one string, not a list of lines
  cb_rows '.not_checked = "Old API use, no web access"'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'rows file: "not_checked" is not a list of lines' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_label() {
  # Given: R1's second place labelled Guess
  cb_rows '(.rows[] | select(.id == "R1") | .places[1].label) = "Guess"'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R1 place 2: label "Guess" is not Seen or Inferred' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_known_no_ticket() {
  # Given: the Known row R5 with no ticket
  cb_rows '(.rows[] | select(.id == "R5") | .ticket) = ""'
  # When
  cb_build "$T/clean-prune-codebase-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R5: known needs a ticket' "$err"
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

# cb_cards <jq filter>: the card fixture, changed by the filter, at $T/clean-improve-architecture-acme-shop.json
cb_cards() {
  T="$(mktemp -d)"
  jq "$1" "$here/clean-codebase-build-report/cards.json" > "$T/clean-improve-architecture-acme-shop.json"
}

t_cb_builds_cards() {
  # Given: the card fixture
  cb_cards .
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/clean-codebase-build-report/cards-data.json")" "$(cb_data "$T/clean-improve-architecture-acme-shop.html")"
}

t_cb_refuses_card_badge() {
  # Given: R1's card with a badge the report does not know
  cb_cards '(.rows[] | select(.id == "R1") | .card.badge) = "Great"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R1: badge "Great" is not Strong, Worth exploring, or Speculative' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_card_no_after() {
  # Given: R2's card with no after diagram
  cb_cards '(.rows[] | select(.id == "R2") | .card) |= del(.after)'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R2: card has no after diagram' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_view() {
  # Given: the card fixture with a view the report does not know
  cb_cards '.view = "grid"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'view "grid" is not rows or cards' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_known_card_choice() {
  # Given: the Known card R3 asks a question
  cb_cards '(.rows[] | select(.id == "R3") | .choice) = true'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R3: a Known row asks nothing, so choice is false' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_dotted_label() {
  # Given: R2's before diagram with a dotted arrow whose label holds dots
  cb_cards '(.rows[] | select(.id == "R2") | .card.before) = "flowchart LR\n  K[Checkout] -. reads .status .-> P[Pricing]"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R2 before line 2: write an arrow label as -.->|"text"|' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_card_line() {
  # Given: R1's after diagram with a plain label that holds brackets
  cb_cards '(.rows[] | select(.id == "R1") | .card.after) = "flowchart LR\n  A[Order intake (v2)] --> C[OrderRepo]"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R1 after line 2: not a card diagram line, see cards.md' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_unclosed_subgraph() {
  # Given: R2's before diagram opens a subgraph and never ends it
  cb_cards '(.rows[] | select(.id == "R2") | .card.before) = "flowchart LR\n  subgraph Deep[Module]\n  K[Checkout] --> P[Pricing]"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'row R2 before line 2: subgraph with no end' "$err"
  eq page "" "$(ls "$T" | grep '\.html' || true)"
}

t_cb_refuses_sequence_blocks() {
  # Given: R3's before diagram with an else outside alt and a loop with no end
  cb_cards '(.rows[] | select(.id == "R3") | .card.before) = "sequenceDiagram\n  S->>Q: send\n  else failed\n  loop retry 3\n  Q-->>S: ok"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "$(printf 'row R3 before line 3: else outside an alt block\nrow R3 before line 4: loop with no end')" "$err"
}

t_cb_builds_nested_sequence() {
  # Given: R3's before diagram with a loop inside an alt, then the alt's else
  cb_cards '(.rows[] | select(.id == "R3") | .card.before) = "sequenceDiagram\n  alt sent\n  loop retry 3\n  S->>Q: send\n  end\n  else failed\n  Q-->>S: error\n  end"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq stdout "page: $T/clean-improve-architecture-acme-shop.html" "$out"
}

t_cb_builds_sequence_card() {
  # Given: R3's before diagram as a sequence
  cb_cards '(.rows[] | select(.id == "R3") | .card.before) = "sequenceDiagram\n  participant S as SMS sender\n  S->>Q: send (retry 3)\n  Q-->>S: ok"'
  # When
  cb_build "$T/clean-improve-architecture-acme-shop.json"
  # Then
  eq exit 0 "$code"
  eq stdout "page: $T/clean-improve-architecture-acme-shop.html" "$out"
}

cases=(
  "builds the report page with its counts|t_cb_builds_report"
  "says nothing found for no rows|t_cb_nothing_found"
  "says nothing to fix for no rows with a change|t_cb_nothing_to_fix"
  "refuses an advice it does not know|t_cb_refuses_advice"
  "refuses a not_checked that is not a list of lines|t_cb_refuses_not_checked"
  "refuses a place label that is not Seen or Inferred|t_cb_refuses_label"
  "refuses a Known row with no ticket|t_cb_refuses_known_no_ticket"
  "builds the same page twice|t_cb_builds_twice"
  "keeps the old page after a bad build|t_cb_keeps_old_page"
  "escapes tags in a place's text|t_cb_escapes_tags_in_text"
  "builds a row with no state|t_cb_row_with_no_state"
  "builds a card report|t_cb_builds_cards"
  "refuses a card badge it does not know|t_cb_refuses_card_badge"
  "refuses a card with no after diagram|t_cb_refuses_card_no_after"
  "refuses a view it does not know|t_cb_refuses_view"
  "refuses a Known card that asks a question|t_cb_refuses_known_card_choice"
  "refuses a dotted arrow label with dots|t_cb_refuses_dotted_label"
  "refuses a card diagram line it does not know|t_cb_refuses_card_line"
  "refuses a subgraph with no end|t_cb_refuses_unclosed_subgraph"
  "refuses an else outside alt and a loop with no end|t_cb_refuses_sequence_blocks"
  "builds a loop inside an alt with its else|t_cb_builds_nested_sequence"
  "builds a sequence card|t_cb_builds_sequence_card"
)
