# t3-cli.sh: the cases for the shared core's t3-cli.sh, the T3 lookup that
# orchestrate.sh and run-in-t3 both run. The repo's test.sh sources this file
# after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

C="$here/../t3-cli.sh"

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

t_t3_unset() {
  # Given: an executable t3
  t3_setup
  # When
  run env -u T3CODE_CLI_PATH bash "$C"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside T3 Code" "$err"
}

t_t3_not_executable() {
  # Given: a t3 that cannot run
  t3_setup; chmod -x "$T/t3"
  # When
  run env T3CODE_CLI_PATH="$T/t3" bash "$C"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside T3 Code" "$err"
}

cases=(
  "it prints the t3 that T3CODE_CLI_PATH names|t_t3_path"
  "outside T3 it stops|t_t3_unset"
  "a t3 that cannot run stops|t_t3_not_executable"
)
