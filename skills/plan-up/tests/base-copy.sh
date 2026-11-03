# base-copy.sh: the cases for this skill's base-copy.sh. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# origin [<lockfile> [<first line>]]: a bare origin whose main holds
# package.json and, when named, the lockfile; cloned in R, cd into it. Fake
# pnpm, npm, yarn, and bun in $T/bin, first on PATH, each append
# `<cwd> <name> <args>` to $T/tool.log and make node_modules/.fake. With
# FAKE_FAIL set, they print a warn line and an error line and exit 1.
origin() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; R="$T/repo"
  git init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$R" 2>/dev/null; cd "$R"
  git config user.email "t""@""example.invalid"; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  echo '{}' > package.json
  [ -z "${1:-}" ] || printf '%s\n' "${2:-lock}" > "$1"
  git add -A; git commit -qm base; git branch -M main; git push -q origin main
  mkdir -p "$T/bin"
  local tool
  for tool in pnpm npm yarn bun; do
    cat > "$T/bin/$tool" <<EOF
#!/usr/bin/env bash
printf '%s %s %s\n' "\$(pwd -P)" "$tool" "\$*" >> "$T/tool.log"
if [ -n "\${FAKE_FAIL:-}" ]; then
  echo 'npm warn old flag' >&2
  echo ' ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with "frozen-lockfile"'
  exit 1
fi
mkdir -p node_modules && : > node_modules/.fake
EOF
    chmod +x "$T/bin/$tool"
  done
  PATH="$T/bin:$PATH"
}

copy() { run bash "$here/../scripts/base-copy.sh" "$@"; }

# dir_of: the BASE_WT folder of the last copy's stdout.
dir_of() { printf '%s\n' "$out" | sed -n 's/^BASE_WT=\(.*\) BASE_SHA=.*$/\1/p'; }

t_base_copy_installs_pnpm() {
  # Given: main holds pnpm-lock.yaml, and a fake pnpm is on PATH
  origin pnpm-lock.yaml
  # When
  copy main
  # Then
  local dir; dir="$(dir_of)"
  eq exit 0 "$code"
  eq stdout "BASE_WT=$dir BASE_SHA=$(git rev-parse main)" "$out"
  eq stderr "" "$err"
  eq "tool log" "$dir pnpm install --frozen-lockfile --ignore-scripts" "$(cat "$T/tool.log")"
  [ -e "$dir/node_modules/.fake" ]
}

t_base_copy_lockfile_commands() {
  # Given: one origin per lockfile, each with every fake tool on PATH
  local lock first want dir
  while IFS='|' read -r lock first want; do
    origin "$lock" "$first"
    # When
    copy main
    # Then
    dir="$(dir_of)"
    eq "$lock exit" 0 "$code"
    eq "$lock tool log" "$dir $want" "$(cat "$T/tool.log")"
    copy --remove "$dir"
  done <<'EOF'
package-lock.json|{}|npm ci --ignore-scripts
yarn.lock|# yarn lockfile v1|yarn install --frozen-lockfile --ignore-scripts
yarn.lock|__metadata:|yarn install --immutable --mode=skip-build
bun.lock|{}|bun install --frozen-lockfile --ignore-scripts
bun.lockb|bin|bun install --frozen-lockfile --ignore-scripts
EOF
}

t_base_copy_no_lockfile() {
  # Given: main holds no lockfile
  origin
  # When
  copy main
  # Then
  local dir; dir="$(dir_of)"
  eq exit 0 "$code"
  eq stdout "BASE_WT=$dir BASE_SHA=$(git rev-parse main)" "$out"
  eq stderr "" "$err"
  [ ! -e "$T/tool.log" ]
  [ ! -e "$dir/node_modules" ]
}

t_base_copy_install_fails() {
  # Given: main holds pnpm-lock.yaml, and the fake pnpm fails
  origin pnpm-lock.yaml
  # When
  export FAKE_FAIL=1; copy main
  # Then
  local dir; dir="$(dir_of)"
  eq exit 0 "$code"
  eq stderr 'warn: could not install the packages of main: ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with "frozen-lockfile"' "$err"
  eq stdout "BASE_WT=$dir BASE_SHA=$(git rev-parse main)" "$out"
}

t_base_copy_tool_missing() {
  # Given: main holds pnpm-lock.yaml, and PATH holds only the tools the
  # script needs, with no pnpm
  origin pnpm-lock.yaml
  local sha bash_bin tool
  sha="$(git rev-parse main)"; bash_bin="$(command -v bash)"
  mkdir -p "$T/sysbin"
  for tool in git mktemp rm dirname grep awk cat; do ln -s "$(command -v "$tool")" "$T/sysbin/$tool"; done
  # When
  PATH="$T/sysbin" run "$bash_bin" "$here/../scripts/base-copy.sh" main
  # Then
  local dir; dir="$(dir_of)"
  eq exit 0 "$code"
  eq stderr "warn: could not install the packages of main: pnpm not found" "$err"
  eq stdout "BASE_WT=$dir BASE_SHA=$sha" "$out"
}

t_base_copy_remove_with_packages() {
  # Given: a copy whose install made node_modules
  origin pnpm-lock.yaml
  copy main
  local dir; dir="$(dir_of)"
  [ -e "$dir/node_modules/.fake" ]
  # When
  copy --remove "$dir"
  # Then
  eq exit 0 "$code"
  eq stdout "removed $dir" "$out"
  [ ! -e "$(dirname "$dir")" ]
  case "$(git worktree list)" in *"$dir"*) echo "worktree list still names $dir" >&2; exit 1 ;; esac
}

cases=(
  "base-copy installs the packages of a pnpm base|t_base_copy_installs_pnpm"
  "base-copy picks the install command from the lockfile|t_base_copy_lockfile_commands"
  "base-copy installs nothing for a base with no lockfile|t_base_copy_no_lockfile"
  "base-copy warns and goes on when the install fails|t_base_copy_install_fails"
  "base-copy warns and goes on when the package tool is missing|t_base_copy_tool_missing"
  "base-copy removes a copy that has node_modules|t_base_copy_remove_with_packages"
)
