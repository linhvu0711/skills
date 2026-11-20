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
# it. A backup runs in the harness itself, so its place is its harness.
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
