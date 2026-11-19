# base-tree.sh: the cases for the shared core's base-tree.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# bt_lagging: a bare origin and a checkout of it at $T/dev/app, on main. A
# second clone then pushes one more commit to main, so the checkout's main
# lags origin by one; `new` holds that commit's SHA.
bt_lagging() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/dev/app" 2>/dev/null
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m one
  git -C "$T/dev/app" push -q origin HEAD:main
  git clone -q "$T/origin.git" "$T/other" 2>/dev/null
  git -C "$T/other" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m two
  git -C "$T/other" push -q origin HEAD:main
  new="$(git -C "$T/other" rev-parse HEAD)"
}

# tree_of: the BASE_TREE folder of the last add's stdout.
tree_of() { printf '%s\n' "$out" | sed -n 's/^BASE_TREE=\(.*\) BASE_SHA=.*$/\1/p'; }

t_base_tree_takes_origin() {
  # Given
  bt_lagging
  # When
  run bash "$here/../base-tree.sh" "$T/dev/app" main
  # Then
  eq exit 0 "$code"
  local dir; dir="$(tree_of)"
  eq stdout "BASE_TREE=$dir BASE_SHA=$new" "$out"
  eq head "$new" "$(git -C "$dir" rev-parse HEAD)"
}

t_base_tree_no_branch() {
  # Given
  bt_lagging
  # When
  run bash "$here/../base-tree.sh" "$T/dev/app" nope
  # Then
  eq exit 1 "$code"
  eq "last stderr line" "stop: could not fetch nope from origin" "$(printf '%s\n' "$err" | tail -n 1)"
}

t_base_tree_removes() {
  # Given
  bt_lagging
  run bash "$here/../base-tree.sh" "$T/dev/app" main
  local dir; dir="$(tree_of)"
  # When
  run bash "$here/../base-tree.sh" --remove "$dir"
  # Then
  eq exit 0 "$code"
  eq stdout "removed $dir" "$out"
  [ ! -e "$(dirname "$dir")" ] || eq "temp folder" gone "$(dirname "$dir")"
  eq "worktree list" 1 "$(git -C "$T/dev/app" worktree list | wc -l | tr -d ' ')"
}

t_base_tree_refuses_other() {
  # Given
  T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/other/base"
  # When
  run bash "$here/../base-tree.sh" --remove "$T/other/base"
  # Then
  eq exit 1 "$code"
  eq stderr "stop: $T/other/base is not a base tree" "$err"
  [ -d "$T/other/base" ] || eq folder "still there" gone
}

cases=(
  "takes origin's head when the local branch lags|t_base_tree_takes_origin"
  "stops when origin has no such branch|t_base_tree_no_branch"
  "removes the tree it made|t_base_tree_removes"
  "refuses a folder it did not make|t_base_tree_refuses_other"
)
