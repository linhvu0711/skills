# copies.sh: the cases for this skill's copies.py. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

copies() { run python3 "$here/../scripts/copies.py" < list; }

# two_files: a.py and b.py share the six lines of total(), b.py with
# other indents, and a list file that names both.
two_files() {
  T="$(mktemp -d)"
  printf 'x = 0\ndef total(items):\n    s = 0\n    for i in items:\n        s += i\n    print(s)\n    return s\ny = 1\n' > a.py
  printf 'import os\nz = 2\ndef total(items):\n  s = 0\n  for i in items:\n      s += i\n  print(s)\n  return s\n' > b.py
  printf 'a.py\nb.py\n' > list
}

t_copies_six_lines() {
  # Given: two files that share six lines
  two_files
  # When
  copies
  # Then
  eq exit 0 "$code"
  eq stdout "6 lines: a.py:2-7 b.py:3-8" "$out"
}

t_copies_five_lines() {
  # Given: the same files, with b.py line 7 changed
  two_files
  printf 'import os\nz = 2\ndef total(items):\n  s = 0\n  for i in items:\n      s += i\n  print(s, 1)\n  return s\n' > b.py
  # When
  copies
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_copies_longer_copy() {
  # Given: two files with the same nine lines
  T="$(mktemp -d)"
  for i in 1 2 3 4 5 6 7 8 9; do echo "v$i = $i"; done > a.py
  cp a.py b.py
  printf 'a.py\nb.py\n' > list
  # When
  copies
  # Then
  eq exit 0 "$code"
  eq stdout "9 lines: a.py:1-9 b.py:1-9" "$out"
}

t_copies_skips_binary() {
  # Given: the two files, and a file that is not text listed after them
  two_files
  printf '\xff\xfe\x00\x01' > img.bin
  echo img.bin >> list
  # When
  copies
  # Then
  eq exit 0 "$code"
  eq stdout "6 lines: a.py:2-7 b.py:3-8" "$out"
}

t_copies_no_overlap_in_one_file() {
  # Given: a six-line block, then the same block, then its first five lines, in one file
  T="$(mktemp -d)"
  for i in 1 2 3 4 5 6 1 2 3 4 5 6 1 2 3 4 5; do echo "v$i = $i"; done > a.py
  echo a.py > list
  # When
  copies
  # Then
  eq exit 0 "$code"
  eq stdout "6 lines: a.py:1-6 a.py:7-12" "$out"
}

cases=(
  "copies: two files share six lines: one group|t_copies_six_lines"
  "copies: five shared lines are no copy|t_copies_five_lines"
  "copies: a longer copy is one group|t_copies_longer_copy"
  "copies: a file that is not text is skipped|t_copies_skips_binary"
  "copies: a block repeated in one file does not overlap itself|t_copies_no_overlap_in_one_file"
)
