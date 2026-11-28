# route-labels.sh: the cases for the shared core's route/labels.sh, the
# label rule the Router, run-in-t3's kickoff.sh, and the orchestrator's check read. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

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

t_kl_numbered_no_size() {
  # Given: labels.sh sourced
  # When
  local l got="" sep=""
  for l in S1 S-1; do
    kl_size "$l"
    got="$got$sep$out"; sep=,
  done
  # Then
  eq sizes "," "$got"
}

t_kl_size_with_range() {
  # Given: labels.sh sourced
  # When
  kl_size "Size: S (10-29)"
  # Then
  eq stdout S "$out"
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

# kl_repo <labels>: a fresh T and the fake gh, whose label list of acme/app
# is the JSON array <labels>.
kl_repo() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '%s\n' "$1" > "$FAKE_GH/label-list.json"
}

# kl_save: the size map of acme/app saved at $T/conv.json, S as `Size: Small`.
kl_save() {
  GH_ISSUE_STORE="$T/conv.json" python3 "$here/../issue_conventions.py" set acme/app --style bracket \
    --xs XS --s 'Size: Small' --m M --l L --xl XL --xxl XXL >/dev/null
}

t_kl_answer_labels() {
  # Given: labels.sh sourced, no conventions saved, no repo label names a size
  kl_repo '[{"name":"bug"},{"name":"p1"}]'
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

t_kl_repo_size_label() {
  # Given: no conventions saved, the repo has a Size: Small label
  kl_repo '[{"name":"bug"},{"name":"Size: Small"}]'
  # When
  kl_answer ship S
  # Then
  eq exit 0 "$code"
  eq stdout "Size: Small" "$out"
}

t_kl_broken_store() {
  # Given: the saved map cut off mid-file, the repo has a Size: Small label
  kl_repo '[{"name":"bug"},{"name":"Size: Small"}]'
  kl_save
  printf '{"acme/app": ' > "$T/conv.json"
  # When
  kl_answer ship S
  # Then
  eq stdout "Size: Small" "$out"
}

t_kl_first_size_label() {
  # Given: no conventions saved, two repo labels name S
  kl_repo '[{"name":"Size: Small"},{"name":"size/S"}]'
  # When
  kl_answer ship S
  # Then
  eq stdout "Size: Small" "$out"
}

t_kl_label_list_fails() {
  # Given: no conventions saved, the repo's label list cannot be read
  kl_repo '[{"name":"bug"},{"name":"Size: Small"}]'
  echo 'HTTP 404: Not Found' > "$FAKE_GH/label-list.fail"
  # When
  kl_answer ship S
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  has stderr "could not read the labels of acme/app: HTTP 404: Not Found" "$err"
}

t_kl_saved_map_no_gh() {
  # Given: the size map saved, and a label list that would fail if read
  kl_repo '[]'
  echo 'HTTP 404: Not Found' > "$FAKE_GH/label-list.fail"
  kl_save
  # When
  kl_answer ship S
  # Then
  eq stdout "Size: Small" "$out"
  eq "label list calls" no "$([ -e "$FAKE_GH/label-list.calls" ] && echo yes || echo no)"
}

t_kl_label_spec() {
  # Given: labels.sh sourced
  T="$(cd "$(mktemp -d)" && pwd -P)"
  local l got="" sep=""
  for l in manual seed bug "Size: Medium"; do
    # When
    run bash -c '. "$1"; label_spec "$2"' _ "$L" "$l"
    got="$got$sep$(head -1 <<<"$out")"; sep=,
  done
  # Then
  eq colors "6E7781,C5DEF5,8250DF,3FA9B0" "$got"
}

cases=(
  "size/M reads as M|t_kl_size_slash"
  "Size: Medium reads as M|t_kl_size_words"
  "p1 is no size|t_kl_no_size"
  "a numbered label such as S1 is no size|t_kl_numbered_no_size"
  "a size label with a line range reads as its size|t_kl_size_with_range"
  "an XXL label is XXL|t_kl_size_xxl"
  "answer_label names the label of each answer|t_kl_answer_labels"
  "answer_label reads a broken store as none saved|t_kl_broken_store"
  "answer_label uses the repo's size label when none is saved|t_kl_repo_size_label"
  "answer_label takes the first label of the size|t_kl_first_size_label"
  "answer_label stops when the label list fails|t_kl_label_list_fails"
  "answer_label takes a saved map with no GitHub call|t_kl_saved_map_no_gh"
  "label_spec gives each answer label its color|t_kl_label_spec"
)
