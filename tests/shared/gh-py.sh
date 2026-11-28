# gh-py.sh: the cases for the shared core's gh.py, the one way a Python script
# runs gh. tests/run.sh sources this file after lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# gp_run <code>: run <code> with the module gh.py loaded by path as `gh`, as a
# caller loads it. A case that sets gp_path runs python3 with that PATH.
gp_run() {
  run env ${gp_path:+PATH="$gp_path"} python3 -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gh", sys.argv[1])
gh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gh)
'"$1" "$here/../../shared/gh.py"
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

t_gp_error_status() {
  # Given: an api call that fails with a 404 error body on stdout
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf 'gh: Not Found (HTTP 404)\n' > "$FAKE_GH/repo.fail"
  printf '{"message":"Not Found","status":"404"}\n' > "$FAKE_GH/repo.body"
  # When
  gp_run '
try:
    gh.run("api", "repos/acme/app/contents/x")
except gh.GhError as e:
    print(e.status, end="")'
  # Then
  eq status 404 "$out"
}

cases=(
  "run keeps a hint out of the answer|t_gp_run_hint_kept_out"
  "a failed api call carries its status|t_gp_error_status"
)
