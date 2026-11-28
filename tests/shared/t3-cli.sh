# t3-cli.sh: the cases for the shared core's t3-cli.sh, the T3 lookup that
# orchestrate.sh and run-in-t3 both run. tests/run.sh sources this file after
# lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

C="$here/../../shared/t3-cli.sh"

# t3_setup: a temp folder T with an executable file $T/t3.
t3_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  printf '#!/bin/sh\n' > "$T/t3"; chmod +x "$T/t3"
}

t_t3_path() {
  # Given: an executable t3
  t3_setup
  # When
  run env T3CODE_CLI_PATH="$T/t3" bash "$C"
  # Then
  eq exit 0 "$code"
  eq stdout "$T/t3" "$out"
}

cases=(
  "it prints the t3 that T3CODE_CLI_PATH names|t_t3_path"
)
