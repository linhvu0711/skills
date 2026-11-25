#!/usr/bin/env bash
# ci-covers.sh: say, per Gate, whether the PR's GitHub CI runs it.
#
#   ci-covers.sh <worktree> -- <command>...
#
# It reads each <worktree>/.github/workflows/*.yml and *.yaml file, the top of
# that folder only as GitHub does, as plain text lines. A workflow covers a
# Gate only when all three hold:
#   - its top-level `on:` names `pull_request`: `on: pull_request`, a list
#     such as `on: [push, pull_request]`, or a `pull_request:` key or
#     `- pull_request` item under `on:`. A filter under that key, such as
#     `branches:` or `paths:`, or a value on the key's own line, such as
#     `pull_request: {branches: [main]}`, can skip the PR, so the Gate runs
#     here.
#   - the Gate is exactly a run command: the value of a one-line `run:`, or
#     one line, trimmed, of a `run: |` block. A longer command, a comment, a
#     line of a folded `run: >` block, or a run line with more on it is not
#     the Gate.
#   - neither the job nor the step of that run line has an `if:` line, and
#     no job the run's job waits on through `needs:`, at any depth, has one.
#     A quoted key, as `"if":` or `'if':`, counts like a bare one, for
#     `jobs:`, `steps:`, `needs:`, and `if:`.
#     Any `if:` counts, `if: always()` too: the script does not read what a
#     condition means, and an `if:` can skip the run on the PR. A `needs:`
#     name with no job in the file counts as one that can skip.
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
# unq(s): s with the quotes taken off a leading key, as "if": or \047if\047:,
# since YAML reads a quoted key the same as a bare one.
function unq(s) {
  if (s ~ /^"[a-z-]+"[ \t]*:/) { sub(/^"/, "", s); sub(/"[ \t]*:/, ":", s) }
  else if (s ~ /^\047[a-z-]+\047[ \t]*:/) { sub(/^\047/, "", s); sub(/\047[ \t]*:/, ":", s) }
  return s
}
function nocomment(s) { sub(/[ \t]+#.*$/, "", s); return s }
function indent(s) { match(s, /^ */); return RLENGTH }
function need(j, name) { nd[j, ++nn[j]] = trim(name) }
# needs(j, v): v is one job name or a flow list, as `[a, b]`.
function needs(j, v,   m, i, items) {
  v = trim(v)
  if (v !~ /^\[.*\]$/) { need(j, v); return }
  m = split(substr(v, 2, length(v) - 2), items, ",")
  for (i = 1; i <= m; i++) need(j, items[i])
}
BEGIN { pr = 0; filt = 0; prk = 0; n = 0; in_on = 0; child = -1; blk = -1; injobs = 0; jind = -1; jk = -1; job = 0
  insteps = 0; sind = -1; step = 0; cur = 0; scol = -1 }
{
  sub(/\r$/, "")
  line = $0
  if (blk >= 0) {
    if (line ~ /^[ \t]*$/) next
    if (indent(line) > blk) { runs[++n] = trim(line); rj[n] = job; rs[n] = cur; next }
    blk = -1
  }
  if (in_on) {
    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
    ind = indent(line)
    if (ind > 0) {
      if (child < 0) child = ind
      if (ind == child) {
        k = trim(line); sub(/^-[ \t]*/, "", k); k = nocomment(k)
        rest = ""; c = index(k, ":"); if (c) { rest = trim(substr(k, c + 1)); k = substr(k, 1, c - 1) }
        prk = (trim(k) == "pull_request")
        if (prk) pr = 1
        if (prk && rest != "") filt = 1
      } else if (prk) filt = 1
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
  if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) next
  match(line, /^ *(- +)?/); col = RLENGTH
  t = substr(line, col + 1)
  ind = indent(line); dash = (col > ind); bare = (line ~ /^ *-[ \t]*$/)
  if (ind == 0) { injobs = (line ~ /^jobs:/); jind = -1; cur = 0; next }
  if (injobs) {
    if (jind < 0) jind = ind
    if (ind <= jind) {
      job++; jk = -1; insteps = 0; inneeds = 0; cur = 0
      jn = trim(t); sub(/:.*$/, "", jn); idx[jn] = job
    }
    else {
      if (jk < 0) jk = ind
      if (ind == jk && !dash && !bare) {
        cur = 0; insteps = (t ~ /^steps:/); sind = -1; inneeds = 0
        kt = unq(t)
        if (kt ~ /^if:([ \t]|$)/) jif[job] = 1
        if (kt ~ /^needs:([ \t]|$)/) {
          v = trim(nocomment(substr(kt, 7)))
          if (v == "") inneeds = 1
          else needs(job, v)
        }
      } else if (inneeds) {
        # A name or a list can sit after a dash, on its own line under the key,
        # or on the line under a bare dash.
        if (!bare) needs(job, nocomment(t))
      } else if (insteps) {
        # The keys of a step sit at the column right after its dash; a
        # deeper `if:`, as under `with:`, belongs to something else. A bare
        # dash puts the first key on the next line, so that line sets it.
        if ((dash || bare) && sind < 0) sind = ind
        if ((dash || bare) && ind == sind) { cur = ++step; scol = (bare ? -1 : col) }
        else if (cur && scol < 0) scol = col
        if (cur && col == scol && unq(t) ~ /^if:([ \t]|$)/) sif[cur] = 1
      }
    }
  }
  if (t !~ /^run:([ \t]|$)/) next
  v = trim(substr(t, 5))
  if (v ~ /^\|[-+]?$/) blk = col
  else if (v != "" && v !~ /^>/) { runs[++n] = v; rj[n] = job; rs[n] = cur }
}
END {
  print (pr && !filt ? "PR" : "NOPR")
  # A job can name a job further down the file, so the chain is closed here,
  # pass after pass, until no job changes.
  for (j = 1; j <= job; j++) skip[j] = jif[j]
  do {
    changed = 0
    for (j = 1; j <= job; j++) {
      if (skip[j]) continue
      for (i = 1; i <= nn[j]; i++) {
        m = nd[j, i]
        if (!(m in idx) || skip[idx[m]]) { skip[j] = 1; changed = 1; break }
      }
    }
  } while (changed)
  for (i = 1; i <= n; i++) if (!skip[rj[i]] && !sif[rs[i]]) print runs[i]
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
