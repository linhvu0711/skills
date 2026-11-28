# die.sh: the cases for the shared core's die.sh. The repo's test.sh sources
# this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# stopper <line>: a script in $T that sources die.sh, then runs <line>.
stopper() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; cd "$T"
  printf '. "%s/../die.sh"\n%s\n' "$here" "$1" > stop.sh
}

t_die_stops() {
  # Given
  stopper 'die "no repo" "here"'
  # When
  run bash stop.sh
  # Then
  eq exit 1 "$code"; eq stderr "stop: no repo here" "$err"
}

t_die_usage_why() {
  # Given
  stopper 'die_usage "usage: x.sh <n>" "no n"'
  # When
  run bash stop.sh
  # Then
  eq exit 64 "$code"; eq stderr "$(printf 'stop: no n\nusage: x.sh <n>')" "$err"
}

t_die_usage_alone() {
  # Given
  stopper 'die_usage "usage: x.sh <n>"'
  # When
  run bash stop.sh
  # Then
  eq exit 64 "$code"; eq stderr "usage: x.sh <n>" "$err"
}

cases=(
  "die: stops with the why and exit 1|t_die_stops"
  "die: die_usage prints the why, then the usage, exit 64|t_die_usage_why"
  "die: die_usage with no why prints the usage alone|t_die_usage_alone"
)
