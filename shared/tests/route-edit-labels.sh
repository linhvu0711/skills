# route-edit-labels.sh: the cases for the shared core's route/edit-labels.sh,
# the label writer run-in-t3 and the orchestrator share. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

EL="$here/../route/edit-labels.sh"

# el_gh: the fake gh, whose issue edit and label create answer with nothing.
el_gh() {
  fake_gh
  : > "$FAKE_GH/issue-edit.json"; : > "$FAKE_GH/label-create.json"
}

t_el_makes_missing() {
  # Given: the repo has no seed label
  el_gh
  echo "could not add label: 'seed' not found" > "$FAKE_GH/issue-edit.1.fail"
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
  eq "issue edit args" "issue edit 16 --repo acme/app --add-label bug --remove-label seed" "$(cat "$FAKE_GH/issue-edit.args")"
}

cases=(
  "a missing label is made|t_el_makes_missing"
  "a swap adds and removes in one edit|t_el_swap"
)
