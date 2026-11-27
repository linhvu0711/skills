# size.sh: the cases for the shared core's size.py. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

size() { run python3 "$here/../size.py" "$@"; }

# lines <file> <n> <word>: write n lines, `<word> 1` to `<word> n`, making
# the file's folder first.
lines() {
  mkdir -p "$(dirname "$1")"
  seq 1 "$2" | sed "s/^/$3 /" > "$1"
}

# commit_all <message>: commit every change in the repo.
commit_all() { git add -A; git commit -qm "$1"; }

# base_repo: a repo with branch `base` at its first commit.
base_repo() { repo; git branch base; }

t_size_240_lines() {
  # Given
  base_repo; lines app.py 240 line; commit_all "add app"
  # When
  size base
  # Then
  eq exit 0 "$code"
  eq stdout L "$out"
}

t_size_only_tests() {
  # Given
  base_repo; lines tests/test_app.py 40 check; commit_all "add tests"
  # When
  size base
  # Then
  eq stdout M "$out"
}

t_size_test_kinds() {
  # Given
  base_repo; lines app.py 240 line
  lines test/a.py 60 t; lines tests/b.py 60 t; lines web/__tests__/c.js 60 t
  lines web/d.test.js 60 t; lines web/e.spec.ts 60 t
  commit_all "add app and tests"
  # When
  size base
  # Then
  eq stdout L "$out"
}

t_size_whitespace() {
  # Given
  repo; lines app.py 20 x; commit_all "add app"; git branch base
  {
    for i in $(seq 1 20); do
      if [ "$i" -le 12 ]; then printf '    y %s\n' "$i"; else printf '    x %s\n' "$i"; fi
      [ "$i" -gt 15 ] || printf '\n'
    done
  } > app.py
  commit_all "indent, space out, and change 12 lines"
  # When
  size base
  # Then
  eq stdout S "$out"
}

t_size_lock_and_generated() {
  # Given
  repo; printf 'gen.js linguist-generated\ngen2.js linguist-generated=true\n' > .gitattributes
  commit_all "mark generated files"; git branch base
  lines pnpm-lock.yaml 300 l; lines Cargo.lock 300 l; lines web/packages.lock.json 300 l
  lines gradle.lockfile 300 l; lines pylock.toml 300 l
  lines gen.js 300 g; lines gen2.js 300 g; lines app.py 20 line
  commit_all "add lockfiles, generated files, and app"
  # When
  size base
  # Then
  eq stdout S "$out"
}

t_size_odd_names() {
  # Given
  repo; printf '"gen/API Client.ts" linguist-generated\n' > .gitattributes
  commit_all "mark generated file"; git branch base
  lines "gen/API Client.ts" 300 g; lines "$(printf 'tab\there.py')" 40 t; lines 'quote"d.py' 40 q
  commit_all "add files with odd names"
  # When
  size base
  # Then
  eq stdout M "$out"
}

t_size_not_utf8() {
  # Given
  base_repo
  for i in $(seq 1 20); do printf 'caf\351 %s\n' "$i"; done > app.c
  commit_all "add a Latin-1 file"
  # When
  size base
  # Then
  eq exit 0 "$code"
  eq stdout S "$out"
}

t_size_empty() {
  # Given
  base_repo
  # When
  size base
  # Then
  eq exit 0 "$code"
  eq stdout XS "$out"
}

t_size_edges() {
  # Given
  local n got=""
  for n in 9 10 29 30 99 100 499 500 600 999 1000; do
    base_repo; lines app.py "$n" line; commit_all "add app"
    # When
    size base
    got="$got $out"
  done
  # Then
  eq sizes "XS S S M M L L XL XL XL XXL" "${got# }"
}

t_size_outside_checkout() {
  # Given
  T="$(cd "$(mktemp -d)" && pwd -P)"; cd "$T"
  # When
  size base
  # Then
  eq exit 1 "$code"
  eq stderr "stop: not inside a git checkout; run it from the PR's checkout" "$err"
  eq stdout "" "$out"
}

t_size_base_not_found() {
  # Given
  base_repo; lines app.py 240 line; commit_all "add app"
  # When
  size nosuch
  # Then
  eq exit 1 "$code"
  eq stderr "stop: base nosuch not found; fetch it first, as git fetch origin <branch>" "$err"
  eq stdout "" "$out"
}

cases=(
  "size: 240 non-test lines print L|t_size_240_lines"
  "size: only tests count their test lines|t_size_only_tests"
  "size: test files are the four kinds|t_size_test_kinds"
  "size: whitespace and blank lines add nothing|t_size_whitespace"
  "size: lockfiles and generated files add nothing|t_size_lock_and_generated"
  "size: names with a space, a tab, or a quote are read whole|t_size_odd_names"
  "size: bytes that are not UTF-8 still count|t_size_not_utf8"
  "size: an empty diff prints XS|t_size_empty"
  "size: the scale edges|t_size_edges"
  "size: outside a checkout it stops|t_size_outside_checkout"
  "size: a base it cannot find stops|t_size_base_not_found"
)
