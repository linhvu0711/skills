# gh-py.sh: the cases for the shared core's gh.py, the one way a Python
# script runs gh. The repo's test.sh sources this file after test-lib.sh and
# runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# gp_run <code>: run <code> with the module gh.py loaded by path as `gh`, as a
# caller loads it. A case that sets gp_path runs python3 with that PATH.
gp_run() {
  run env ${gp_path:+PATH="$gp_path"} python3 -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gh", sys.argv[1])
gh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gh)
'"$1" "$here/../gh.py"
}

t_gp_stop_last_line() {
  # Given: run list fails with a hint first, then the error
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf 'A new release of gh is available\nHTTP 401: Bad credentials\n' > "$FAKE_GH/run-list.fail"
  # When
  gp_run 'gh.stop("list runs", "run", "list")'
  # Then
  eq stop "1|stop: gh could not list runs: HTTP 401: Bad credentials" "$code|$err"
}

t_gp_run_hint_kept_out() {
  # Given: run list answers, and prints a hint on stderr beside it
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '[]\n' > "$FAKE_GH/run-list.json"
  printf 'A new release of gh is available\n' > "$FAKE_GH/run-list.stderr"
  # When
  gp_run 'print(gh.run("run", "list"), end="")'
  # Then
  eq answer "0|[]" "$code|$out"
}

t_gp_stop_gh_cannot_start() {
  # Given: a PATH that holds python3 and a gh that cannot be run, and no
  # system folder, where a real gh would be found next
  T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/bin"; printf '#!/bin/sh\n' > "$T/bin/gh"; chmod -x "$T/bin/gh"
  # The interpreter itself: a shim such as pyenv's needs bash from PATH.
  ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$T/bin/python3"
  local gp_path="$T/bin"
  # When
  gp_run 'gh.stop("list runs", "run", "list")'
  # Then
  eq stop "1|stop: gh could not list runs: gh: could not start: Permission denied" "$code|$err"
}

cases=(
  "stop shows a gh that cannot start as a stop line|t_gp_stop_gh_cannot_start"
  "stop shows gh's last error line|t_gp_stop_last_line"
  "run keeps a hint out of the answer|t_gp_run_hint_kept_out"
)
