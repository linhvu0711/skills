# plan_reader.sh: a plan .md in, the reader's parts and problem lines out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# problems <md>: each problem line plan_reader.problems names, one per line.
problems() {
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import plan_reader
for line in plan_reader.problems(plan_reader.read(sys.argv[2])):
    print(line)' "$here/../scripts" "$1"
}

# parts <md> <expr>: the value of <expr> over `plan`, the read plan, as sorted JSON.
parts() {
  run python3 -c 'import json, sys; sys.path.insert(0, sys.argv[1]); import plan_reader
print(json.dumps(eval(sys.argv[3], {"plan": plan_reader.read(sys.argv[2])}), ensure_ascii=False, sort_keys=True))' \
    "$here/../scripts" "$1" "$2"
}

# ticket <sed script>: ticket.md changed by <sed script>, at $T/plan.md.
ticket() {
  T="$(mktemp -d)"
  sed "$1" "$here/build-page/ticket.md" > "$T/plan.md"
}

# bad_line <sed script> <problem line>: the changed ticket gives that one problem line.
bad_line() {
  ticket "$1"
  problems "$T/plan.md"
  eq exit 0 "$code"
  eq stderr "" "$err"
  eq problems "$2" "$out"
}

t_reader_good_ticket() {
  # Given: ticket.md as it is
  ticket ''
  # When
  problems "$T/plan.md"
  # Then
  eq exit 0 "$code"
  eq problems "" "$out"
}

t_reader_risk_no_proved() {
  bad_line 's/ Proved: P1$//' \
    'review: a risk needs `If wrong:` and `Proved:`: notes may contain newlines. If wrong: rows split.'
}

t_reader_odd_choice() {
  bad_line 's/  - D2: delimiter/  - Note: delimiter/' \
    'review: each `Choices` line starts `Fork:` or `D<n>:`, not: Note: delimiter is `,`. Risk: a different delimiter breaks i'
}

t_reader_works_order() {
  bad_line 's/  - #2 an empty/  - #3 an empty/' 'review: `Works when` line 2 must start `#2 `'
}

t_reader_proof_cells() {
  bad_line 's/| none | none | test |$/| none | none |/' 'proof: layer 1 row 2 has 5 cells, needs 6'
}

# good_part <expr> <JSON>: ticket.md as it is gives <JSON> for <expr>.
good_part() {
  ticket ''
  parts "$T/plan.md" "$1"
  eq exit 0 "$code"
  eq parts "$2" "$out"
}

t_reader_risk_parts() {
  good_part 'plan["reviews"][0]["parts"]["Risks"]' \
    '[{"belief": "notes may contain newlines.", "ifWrong": "rows split", "line": "notes may contain newlines. If wrong: rows split. Proved: P1", "proved": "P1"}]'
}

t_reader_fork_parts() {
  good_part 'plan["reviews"][0]["parts"]["Choices"][0]' \
    '{"fork": {"pick": "stream", "question": "stream or buffer"}, "line": "Fork: stream or buffer → stream (user)", "ref": null, "text": "stream or buffer → stream (user)"}'
}

t_reader_works_parts() {
  good_part 'plan["reviews"][0]["parts"]["Works when"][1]' \
    '{"line": "#2 an empty export has a header", "n": 2, "text": "an empty export has a header"}'
}

t_reader_touches_parts() {
  good_part 'plan["reviews"][0]["parts"]["Blast radius"]["Touches"]' '["Web", "API"]'
}

cases=(
  "plan_reader reads a risk into belief, if wrong, and proved|t_reader_risk_parts"
  "plan_reader reads a fork choice into its question and pick|t_reader_fork_parts"
  "plan_reader reads a Works when line into its number and text|t_reader_works_parts"
  "plan_reader reads the touched parts as a list|t_reader_touches_parts"
  "plan_reader finds no problem in a good ticket plan|t_reader_good_ticket"
  "plan_reader names a risk with no Proved part|t_reader_risk_no_proved"
  "plan_reader names a Choices line that is neither a fork nor a decision|t_reader_odd_choice"
  "plan_reader names a Works when line out of order|t_reader_works_order"
  "plan_reader names a Proof row short of a cell|t_reader_proof_cells"
)
