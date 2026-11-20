#!/usr/bin/env bash
# agents.sh: the one reader of a skill agent's home and backup models.
# check.sh asks it for a file's problems; link.sh asks it for the file each
# harness reads.
#
#   agents.sh check < skills/<name>/agents/<agent>.md
#   agents.sh render <harness> <marker> < skills/<name>/agents/<agent>.md
#
# After `name`, `description`, and an optional `tools` line, an agent file
# holds two maps, each key two spaces in, one entry per main harness:
#
#   home:
#     claude: <place> <model> <effort>
#     codex: <place> <model> <effort>
#     antigravity: <place> <model> <effort>
#   backup:
#     claude: <model> <effort>
#     codex: <model> <effort>
#     antigravity: <model>
#
# A home is the model T3 starts the agent on; its place is where T3 starts
# it: claude, codex, antigravity, or devin. A backup runs in the harness
# itself, so its place is its harness. Each place takes models of one form
# and a set of efforts, as T3 and each harness list them on 2026-11-20:
#
#   claude       claude-<family>-<n>-<n>     low medium high xhigh max
#   codex        gpt-<n>[.<n>]-<name>        low medium high xhigh max ultra
#   antigravity  gemini-<n>[.<n>]-<name>     low medium high xhigh
#   devin        a T3 Devin id, as swe-2-high  none low medium high xhigh max
#
# An Antigravity agent file takes no exact model and no effort, so an
# Antigravity backup is one of inherit, flash, pro, flash_lite, alone.
# `name` and `description` are check.sh's to check; the `description:` line
# is copied as written, so it must be one line.
#
# check: one problem per line on stdout, nothing for a good file. Exit 0.
# render: the file of <harness> on stdout, <marker> in a comment at its top,
# exit 0; or the first problem on stderr, exit 1. <harness> is claude.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mode="${1:-}"
case "$mode" in
  check) harness=""; marker="" ;;
  render) [ $# -eq 3 ] || { echo "usage: agents.sh render <harness> <marker>" >&2; exit 2; }
          harness="$2"; marker="$3"
          case "$harness" in claude) ;; *) echo "unknown harness: $harness" >&2; exit 2 ;; esac ;;
  *) echo "usage: agents.sh check | agents.sh render <harness> <marker>" >&2; exit 2 ;;
esac

LC_ALL=C awk -v mode="$mode" -v harness="$harness" -v marker="$marker" -f "$here/frontmatter.awk" -f <(cat <<'AWK'
  function problem(s) { probs[++np] = s }
  function model_ok(place, sec, m) {
    if (place == "claude") return m ~ /^claude-[a-z]+-[0-9]+-[0-9]+$/
    if (place == "codex") return m ~ /^gpt-[0-9]+(\.[0-9]+)?-[a-z]+$/
    if (place == "antigravity" && sec == "backup") return m ~ /^(inherit|flash|pro|flash_lite)$/
    if (place == "antigravity") return m ~ /^gemini-[0-9]+(\.[0-9]+)?-[a-z]+$/
    return m ~ /^[a-z0-9][a-z0-9.-]*$/ }
  function effort_ok(place, e) { return index(" " efforts[place] " ", " " e " ") > 0 }
  # entry_problems(sec, h): the problems of the entry for harness h in map sec.
  function entry_problems(sec, h,  w, n, place, m, e, want, at) {
    at = sec " for " h ": "
    n = split(entry[sec, h], w, " ")
    if (sec == "home") { place = w[1]; m = w[2]; e = w[3]; want = 3
      if (!(place in efforts)) { problem(at "unknown place: " place); return } }
    else { place = h; m = w[1]; e = w[2]; want = (h == "antigravity") ? 1 : 2 }
    if (!model_ok(place, sec, m)) { problem(at m " is not a model " place " takes"); return }
    if (want == 1) { if (n > 1) problem(at "takes a model and no effort"); return }
    if (n < want) { problem(at "no effort"); return }
    if (!effort_ok(place, e)) { problem(at e " is not an effort " place " takes"); return }
    if (n > want) problem(at "one effort, then nothing")
  }
  BEGIN { efforts["claude"] = "low medium high xhigh max"
          efforts["codex"] = "low medium high xhigh max ultra"
          efforts["antigravity"] = "low medium high xhigh"
          efforts["devin"] = "none low medium high xhigh max" }
  NR == 1 { if ($0 != "---") { bare = 1; exit } next }
  closed { body[++nb] = $0; next }
  $0 == "---" { closed = 1; next }
  /^[ \t]/ {
    if (sec == "") next
    line = $0; sub(/^[ \t]+/, "", line)
    key = line; sub(/:.*$/, "", key)
    v = val(line)
    entry[sec, key] = v
    seen[sec, key] = 1
    order[++ne] = sec SUBSEP key
    next
  }
  { sec = "" }
  /^home:[ \t]*$/ { sec = "home"; next }
  /^backup:[ \t]*$/ { sec = "backup"; next }
  /^name:/ { rawname = $0; name = val($0) }
  /^description:/ { rawdesc = $0; desc = val($0); if (desc ~ /^[|>][-+]?$/) blockdesc = 1 }
  /^tools:/ { rawtools = $0; tools = val($0) }
  END {
    if (bare || !closed) {
      if (mode == "render") { print "missing frontmatter" > "/dev/stderr"; exit 1 }
      exit 0
    }
    split("claude codex antigravity", hs, " ")
    for (i = 1; i <= 3; i++) if (!seen["home", hs[i]]) problem("missing home for " hs[i])
    for (i = 1; i <= 3; i++) if (!seen["backup", hs[i]]) problem("missing backup for " hs[i])
    if (blockdesc) problem("description on more than one line")
    for (i = 1; i <= ne; i++) { split(order[i], k, SUBSEP)
      if (k[2] != "claude" && k[2] != "codex" && k[2] != "antigravity") problem("unknown harness: " k[2])
      else entry_problems(k[1], k[2]) }
    if (mode == "check") { for (i = 1; i <= np; i++) print probs[i]; exit 0 }
    if (np) { print probs[1] > "/dev/stderr"; exit 1 }
    split(entry["backup", harness], b, " ")
    if (harness == "claude") {
      print "---"; print "# " marker; print rawname; print rawdesc
      if (rawtools != "") print rawtools
      print "model: " b[1]; print "effort: " b[2]; print "---"
    }
    for (i = 1; i <= nb; i++) print body[i]
  }
AWK
)
