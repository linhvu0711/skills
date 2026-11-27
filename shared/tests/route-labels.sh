# route-labels.sh: the cases for the shared core's route/labels.sh, the
# label rule the Router, decide.sh, and the orchestrator's check read. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The size rule.
L="$here/../route/labels.sh"

# kl_size <label>: size_of on the label, in a fresh shell that sourced L.
kl_size() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  run bash -c '. "$1"; size_of "$2"' _ "$L" "$1"
}

t_kl_size_slash() {
  # Given: labels.sh sourced
  # When
  kl_size size/M
  # Then
  eq stdout M "$out"
}

t_kl_size_words() {
  # Given: labels.sh sourced
  # When
  kl_size "Size: Medium"
  # Then
  eq stdout M "$out"
}

t_kl_no_size() {
  # Given: labels.sh sourced
  # When
  kl_size p1
  # Then
  eq stdout "" "$out"
}

t_kl_size_xxl() {
  # Given: labels.sh sourced
  # When
  kl_size size/XXL
  # Then
  eq stdout XXL "$out"
}

# kl_answer <answer> [size]: answer_label for acme/app, in a fresh shell
# that sourced L, with the conventions store at $T/conv.json.
kl_answer() {
  run env GH_ISSUE_STORE="$T/conv.json" bash -c '. "$1"; shift; answer_label acme/app "$@"' _ "$L" "$@"
}

t_kl_answer_labels() {
  # Given: labels.sh sourced, no conventions saved
  T="$(cd "$(mktemp -d)" && pwd -P)"
  local a got="" sep=""
  for a in triage grill task "ship M" close; do
    # When
    # shellcheck disable=SC2086 # the answer and its size, as two words
    kl_answer $a
    got="$got$sep$out"; sep=,
  done
  # Then
  eq labels "bug,seed,manual,size/M," "$got"
}

t_kl_answer_repo_size() {
  # Given: acme/app's conventions name its M label "Size: Medium"
  T="$(cd "$(mktemp -d)" && pwd -P)"
  GH_ISSUE_STORE="$T/conv.json" python3 "$here/../issue_conventions.py" set acme/app --style bracket \
    --xs XS --s Small --m "Size: Medium" --l L --xl XL --xxl XXL >/dev/null
  # When
  kl_answer ship M
  # Then
  eq stdout "Size: Medium" "$out"
}

cases=(
  "size/M reads as M|t_kl_size_slash"
  "Size: Medium reads as M|t_kl_size_words"
  "p1 is no size|t_kl_no_size"
  "an XXL label is XXL|t_kl_size_xxl"
  "answer_label names the label of each answer|t_kl_answer_labels"
  "answer_label uses the repo's size label|t_kl_answer_repo_size"
)
