#!/usr/bin/env bash
# agents.sh: the one reader of a skill agent's home and backup models.
# check.sh asks it for a file's problems; link.sh asks it for the file each
# harness reads.
#
#   agents.sh check < skills/<name>/agents/<agent>.md
#   agents.sh render <harness> <marker> < skills/<name>/agents/<agent>.md
#   agents.sh models < skills/<name>/agents/<agent>.md
#   agents.sh start <harness> < skills/<name>/agents/<agent>.md
#
# A shared agent, shared/agents/<agent>.md, is read the same way.
#
# After `name`, `description`, and an optional `tools` line, an agent file
# holds two maps, each key two spaces in, one entry per main harness:
#
#   home:
#     claude: <place> <model> <effort>[, <place> <model> <effort>]...
#     codex: <place> <model> <effort>
#     antigravity: <place> <model> <effort>
#   backup:
#     claude: <model> <effort>
#     codex: <model> <effort>
#     antigravity: <model>
#
# A blank line or a `#` comment line is skipped, so it ends no map.
# A home is a model T3 starts the agent on; its place is where T3 starts
# it: claude, codex, antigravity, or devin. A home entry may list more homes
# after the first, joined by `, `, and T3 tries them from left to right.
# check names a problem in the n-th home, from the second, as
# `home <n> for <harness>:`. A backup runs in the harness
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
# exit 0; or the first problem on stderr, exit 1. <harness> is claude, codex,
# or antigravity. tools: the agent's Claude Code tools on one line, every one
# of them for a file with no tools line, exit 0. The subagent gate reads it.
# models: one line per home and backup, <map> <harness> <place> <model>, in
# file order, exit 0. The map is home for the first home, home<n> for the
# n-th, and backup, whose place is its harness. sync-harnesses reads it.
# start: how the main agent of <harness> starts the agent in T3, exit 0:
# `name` when its first home is <harness> on the backup's model and effort,
# else `t3 <place> <model> <effort>`, its first home. The subagent gate reads
# it.
# Any other command line: its usage on stderr, exit 64.
# The Antigravity form maps the Claude Code tools to
# Antigravity's, as agy's own migration skill does: Read, Grep, Glob to
# read_file; Bash to run_command and manage_task; Edit to edit_file; Write
# to write_file; WebSearch and WebFetch to search_web; Agent to
# invoke_subagent. No tools line, which means every tool in Claude Code,
# gives all seven. The Codex form is TOML: in its strings a `\` becomes `\\`, a `"` in
# the description becomes `\"`, and a `"""` in the body becomes `""\"`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }

mode="${1:-}"
case "$mode" in
  check|tools|models) harness=""; marker="" ;;
  render) u='usage: agents.sh render <harness> <marker>'
          [ $# -eq 3 ] || die_usage "$u"
          harness="$2"; marker="$3"
          case "$harness" in claude|codex|antigravity) ;; *) die_usage "$u" "unknown harness: $harness" ;; esac ;;
  start) u='usage: agents.sh start <harness>'
         [ $# -eq 2 ] || die_usage "$u"
         harness="$2"; marker=""
         case "$harness" in claude|codex|antigravity) ;; *) die_usage "$u" "unknown harness: $harness" ;; esac ;;
  *) die_usage "usage: agents.sh check | agents.sh render <harness> <marker> | agents.sh tools | agents.sh models | agents.sh start <harness>" ;;
esac

LC_ALL=C awk -v mode="$mode" -v harness="$harness" -v marker="$marker" -f "$here/frontmatter.awk" -f <(cat <<'AWK'
  function problem(s) { probs[++np] = s }
  function model_ok(place, sec, m) {
    if (place == "claude") return m ~ /^claude-[a-z]+-[0-9]+-[0-9]+$/
    if (place == "codex") return m ~ /^gpt-[0-9]+(\.[0-9]+)?-[a-z]+$/
    if (place == "antigravity" && sec == "backup") return m ~ /^(inherit|flash|pro|flash_lite)$/
    if (place == "antigravity") return m ~ /^gemini-[0-9]+(\.[0-9]+)?-[a-z]+$/
    return m ~ /^[a-z0-9][a-z0-9.-]*$/ }
  # toml(s, body): s as the inside of a TOML basic string, or of a multi-line
  # one when body is set.
  function toml(s, body,  i, c, o) {
    for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
      if (c == "\\") o = o "\\\\"
      else if (c == "\"" && !body) o = o "\\\""
      else if (c == "\"" && substr(s, i, 3) == "\"\"\"") { o = o "\"\"\\\""; i += 2 }
      else o = o c }
    return o }
  # claude_tools(t): the Claude Code tools of the tools value t, one space
  # between them; an empty t is every tool.
  function claude_tools(t,  n, w, i, out) {
    if (t == "") t = "Read Grep Glob Bash Edit Write WebSearch WebFetch Agent"
    gsub(/,/, " ", t); gsub(/\[/, " ", t); gsub(/\]/, " ", t); n = split(t, w, " ")
    for (i = 1; i <= n; i++) out = out (out == "" ? "" : " ") w[i]
    return out }
  # agy_tools(t): the Antigravity tool list for the Claude Code tools t.
  function agy_tools(t,  n, w, i, has, all, out) {
    n = split(claude_tools(t), w, " ")
    for (i = 1; i <= n; i++) {
      if (w[i] == "Read" || w[i] == "Grep" || w[i] == "Glob") has["read_file"] = 1
      else if (w[i] == "Bash") { has["run_command"] = 1; has["manage_task"] = 1 }
      else if (w[i] == "Edit") has["edit_file"] = 1
      else if (w[i] == "Write") has["write_file"] = 1
      else if (w[i] == "WebSearch" || w[i] == "WebFetch") has["search_web"] = 1
      else if (w[i] == "Agent") has["invoke_subagent"] = 1 }
    split("read_file run_command manage_task edit_file write_file search_web invoke_subagent", all, " ")
    for (i = 1; i <= 7; i++) if (all[i] in has) out = out (out == "" ? "" : ", ") all[i]
    return "[" out "]" }
  function effort_ok(place, e) { return index(" " efforts[place] " ", " " e " ") > 0 }
  # entry_problems(sec, h): the problems of the entry for harness h in map sec.
  # A home entry is a list joined by `,`; its n-th home, from the second, is
  # named `home <n>`.
  function entry_problems(sec, h,  items, k, i) {
    if (sec != "home") { item_problems(sec, h, entry[sec, h], sec " for " h ": "); return }
    k = split(entry[sec, h], items, ",")
    if (k == 0) { items[1] = ""; k = 1 }
    for (i = 1; i <= k; i++) item_problems(sec, h, items[i], (i == 1 ? "home" : "home " i) " for " h ": ")
  }
  # item_problems(sec, h, v, at): the problems of one home or backup v, each
  # line starting with at.
  function item_problems(sec, h, v, at,  w, n, place, m, e, want) {
    n = split(v, w, " ")
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
  END {
    if (!fm_closed) {
      if (mode == "render" || mode == "tools") { print "missing frontmatter" > "/dev/stderr"; exit 1 }
      exit 0
    }
    name = fm["name"]; desc = fm["description"]; tools = fm["tools"]
    rawname = fm_raw["name"]; rawdesc = fm_raw["description"]; rawtools = fm_raw["tools"]
    for (i = 1; i <= fm_nkeys; i++) { split(fm_keys[i], k, SUBSEP)
      if (k[1] != "home" && k[1] != "backup") continue
      entry[k[1], k[2]] = fm_map[k[1], k[2]]; seen[k[1], k[2]] = 1; order[++ne] = fm_keys[i] }
    if (mode == "tools") { print claude_tools(tools); exit 0 }
    split("claude codex antigravity", hs, " ")
    for (i = 1; i <= 3; i++) if (!seen["home", hs[i]]) problem("missing home for " hs[i])
    for (i = 1; i <= 3; i++) if (!seen["backup", hs[i]]) problem("missing backup for " hs[i])
    if (mode == "models") {
      for (i = 1; i <= ne; i++) { split(order[i], k, SUBSEP)
        if (k[1] == "home") { nh = split(entry[k[1], k[2]], items, ",")
          for (j = 1; j <= nh; j++) { split(items[j], w, " "); print (j == 1 ? "home" : "home" j), k[2], w[1], w[2] } }
        else { split(entry[k[1], k[2]], w, " "); print k[1], k[2], k[2], w[1] } }
      exit 0 }
    if (mode == "start") {
      split(entry["home", harness], items, ","); split(items[1], w, " ")
      split(entry["backup", harness], b, " ")
      if (w[1] == harness && w[2] == b[1] && w[3] == b[2]) print "name"
      else print "t3", w[1], w[2], w[3]
      exit 0 }
    if (fm_block["name"]) problem("name on more than one line")
    if (fm_block["description"]) problem("description on more than one line")
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
    if (harness == "antigravity") {
      print "---"; print "# " marker; print rawname; print rawdesc
      print "subagent: true"; print "mainAgent: false"
      print "model: " b[1]; print "tools: " agy_tools(tools); print "---"
    }
    if (harness == "codex") {
      print "# " marker
      print "name = \"" toml(name) "\""
      print "description = \"" toml(desc) "\""
      print "model = \"" b[1] "\""
      print "model_reasoning_effort = \"" b[2] "\""
      print "developer_instructions = \"\"\""
      for (i = 1; i <= fm_nbody; i++) print toml(fm_body[i], 1)
      print "\"\"\""
      exit 0
    }
    for (i = 1; i <= fm_nbody; i++) print fm_body[i]
  }
AWK
)
