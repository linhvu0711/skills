# kickoff-labels.sh: the cases for the shared core's kickoff/labels.sh, the
# size rule that decide.sh and the orchestrator's check both read. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The size rule.
L="$here/../kickoff/labels.sh"

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

cases=(
  "size/M reads as M|t_kl_size_slash"
  "Size: Medium reads as M|t_kl_size_words"
  "p1 is no size|t_kl_no_size"
)
