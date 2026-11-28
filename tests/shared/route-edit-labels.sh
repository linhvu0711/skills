# route-edit-labels.sh: the cases for the shared core's route/edit-labels.sh,
# the label writer run-in-t3 and the orchestrator share. tests/run.sh sources
# this file after lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

EL="$here/../../shared/route/edit-labels.sh"

# el_gh: the fake gh, whose issue edit and label create answer with nothing.
el_gh() {
  fake_gh
  : > "$FAKE_GH/issue-edit.json"; : > "$FAKE_GH/label-create.json"
}

t_el_makes_missing() {
  # Given: the repo has no seed label
  el_gh
  echo "could not add the labels" > "$FAKE_GH/issue-edit.1.fail"
  printf 'gh: Not Found (HTTP 404)\n' > "$FAKE_GH/label.1.fail"
  printf '{"message":"Not Found","status":"404"}\n' > "$FAKE_GH/label.1.body"
  # When
  run bash "$EL" acme/app 16 --add seed
  # Then
  eq exit 0 "$code"
  eq stdout made "$out"
  eq "label create args" "label create seed --repo acme/app --color C5DEF5 --description Captured idea. Not triaged. May be dropped." "$(cat "$FAKE_GH/label-create.args")"
  eq "issue edit calls" 2 "$(cat "$FAKE_GH/issue-edit.calls")"
}

t_el_swap() {
  # Given: an issue with the seed label
  el_gh
  # When
  run bash "$EL" acme/app 16 --add bug --remove seed
  # Then
  eq exit 0 "$code"
  eq stdout edited "$out"
  eq "issue edit args" "issue edit 16 --repo acme/app --add-label \"bug\" --remove-label \"seed\"" "$(cat "$FAKE_GH/issue-edit.args")"
}

t_el_comma_name() {
  # Given: an issue the fake gh edits with no answer
  el_gh
  # When
  run bash "$EL" acme/app 16 --add 'Size, Small' --remove 'Size, Large'
  # Then
  eq exit 0 "$code"
  eq stdout edited "$out"
  eq "issue edit calls" 1 "$(cat "$FAKE_GH/issue-edit.calls")"
  eq "issue edit args" 'issue edit 16 --repo acme/app --add-label "Size, Small" --remove-label "Size, Large"' "$(cat "$FAKE_GH/issue-edit.args")"
}

t_el_doubles_quote() {
  # Given: an issue the fake gh edits with no answer
  el_gh
  # When
  run bash "$EL" acme/app 16 --add 'a"b'
  # Then
  eq exit 0 "$code"
  eq "issue edit args" 'issue edit 16 --repo acme/app --add-label "a""b"' "$(cat "$FAKE_GH/issue-edit.args")"
}

t_el_makes_missing_comma() {
  # Given: the repo has no label named Size, Small
  el_gh
  echo "failed to update https://github.com/acme/app/issues/16: 'Size, Small' not found" > "$FAKE_GH/issue-edit.1.fail"
  printf 'gh: Not Found (HTTP 404)\n' > "$FAKE_GH/label.1.fail"
  printf '{"message":"Not Found","status":"404"}\n' > "$FAKE_GH/label.1.body"
  # When
  run bash "$EL" acme/app 16 --add 'Size, Small'
  # Then
  eq exit 0 "$code"
  eq stdout made "$out"
  eq "label lookup args" "api repos/acme/app/labels/Size%2C%20Small" "$(cat "$FAKE_GH/label.args")"
  eq "label create args" "label create Size, Small --repo acme/app --color 7FC8CC --description 10-29 changed lines" "$(cat "$FAKE_GH/label-create.args")"
}

cases=(
  "a missing label is made|t_el_makes_missing"
  "a swap adds and removes in one edit|t_el_swap"
  "a name with a comma goes in as one quoted field|t_el_comma_name"
  "a quote inside a name is doubled|t_el_doubles_quote"
  "a missing name with a comma is made by its raw name|t_el_makes_missing_comma"
)
