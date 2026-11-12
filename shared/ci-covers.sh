#!/usr/bin/env bash
# ci-covers.sh: say, per Gate, whether the PR's GitHub CI runs it.
#
#   ci-covers.sh <worktree> -- <command>...
#
# It reads each <worktree>/.github/workflows/*.yml and *.yaml file, the top of
# that folder only as GitHub does, as plain text lines. A workflow covers a
# Gate only when both hold:
#   - its top-level `on:` names `pull_request`: `on: pull_request`, a list
#     such as `on: [push, pull_request]`, or a `pull_request:` key or
#     `- pull_request` item under `on:`. Filters under it are not read.
#   - the Gate is exactly a run command: the value of a one-line `run:`, or
#     one line, trimmed, of a `run: |` block. A longer command, a comment, a
#     line of a folded `run: >` block, or a run line with more on it is not
#     the Gate.
# When it is not sure, the Gate runs here: no workflows folder, a file it
# cannot read, another CI, a wrapped script.
#
# Prints one line per command, in the order given:
#   ci <workflow file> · <command>     the first such workflow, by file name
#   here · <command>
#
# Exit 0 with those lines. Exit 1: `stop: <why>` on stderr.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

usage='usage: ci-covers.sh <worktree> -- <command>...'
[ $# -ge 3 ] && [ -d "$1" ] && [ "$2" = -- ] || die "$usage"
wt="$1"; shift 2

# The awk program prints PR or NOPR first, then each run command, one a line.
# It keeps to POSIX awk, so BSD awk on macOS and mawk on CI read it the same.
prog='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function nocomment(s) { sub(/[ \t]+#.*$/, "", s); return s }
function indent(s) { match(s, /^ */); return RLENGTH }
BEGIN { pr = 0; n = 0; in_on = 0; child = -1; blk = -1 }
{
  sub(/\r$/, "")
  line = $0
  if (blk >= 0) {
    if (line ~ /^[ \t]*$/) next
    if (indent(line) > blk) { runs[++n] = trim(line); next }
    blk = -1
  }
  if (in_on) {
    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
    ind = indent(line)
    if (ind > 0) {
      if (child < 0) child = ind
      if (ind == child) {
        k = trim(line); sub(/^-[ \t]*/, "", k); k = nocomment(k); sub(/:.*$/, "", k)
        if (trim(k) == "pull_request") pr = 1
      }
      next
    }
    in_on = 0
  }
  if (line ~ /^on:/) {
    v = line; sub(/^on:/, "", v); v = trim(nocomment(v))
    if (v == "") { in_on = 1; child = -1 }
    else if (v ~ /^\[.*\]$/) {
      m = split(substr(v, 2, length(v) - 2), items, ",")
      for (i = 1; i <= m; i++) if (trim(items[i]) == "pull_request") pr = 1
    } else if (v == "pull_request") pr = 1
    next
  }
  if (line ~ /^[ \t]*#/) next
  match(line, /^ *(- +)?/); col = RLENGTH
  t = substr(line, col + 1)
  if (t !~ /^run:([ \t]|$)/) next
  v = trim(substr(t, 5))
  if (v ~ /^\|[-+]?$/) blk = col
  else if (v != "" && v !~ /^>/) runs[++n] = v
}
END {
  print (pr ? "PR" : "NOPR")
  for (i = 1; i <= n; i++) print runs[i]
}'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# names[i] is a workflow that runs on pull requests; $tmp/<i> holds its run
# commands.
names=(); i=0
dir="$wt/.github/workflows"
if [ -d "$dir" ]; then
  while IFS= read -r f; do
    awk "$prog" "$f" > "$tmp/all" 2>/dev/null || continue
    [ "$(head -n 1 "$tmp/all")" = PR ] || continue
    i=$((i + 1)); tail -n +2 "$tmp/all" > "$tmp/$i"
    names+=("$(basename "$f")")
  done < <(find "$dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
fi

for cmd in "$@"; do
  file=""; j=0
  for name in ${names[@]+"${names[@]}"}; do
    j=$((j + 1))
    if grep -Fxq -- "$cmd" "$tmp/$j"; then file="$name"; break; fi
  done
  if [ -n "$file" ]; then printf 'ci %s · %s\n' "$file" "$cmd"
  else printf 'here · %s\n' "$cmd"; fi
done
