#!/usr/bin/env bash
# agents.sh: the one reader of a skill agent's home and backup models.
# check.sh asks it for a file's problems; link.sh asks it for the file each
# harness reads.
#
#   agents.sh check < skills/<name>/agents/<agent>.md
#   agents.sh render <harness> <marker> < skills/<name>/agents/<agent>.md
#   agents.sh models < skills/<name>/agents/<agent>.md
#   agents.sh start <harness> < skills/<name>/agents/<agent>.md
#   agents.sh tries <harness> < skills/<name>/agents/<agent>.md
#
# A shared agent, shared/agents/<agent>.md, is read the same way.
#
# An agent file also names its `tier:`, 1 to 4, and its `checker:`, yes or
# no. shared/model-tiers.md, or the file $MODEL_TIERS names, joins the two
# into a try list for each main harness. Its three fenced `tsv` tables are
# found by the first cell of their header row: `tier` (the model and effort
# each company runs at each tier), `row` (the companies a subagent tries, in
# order, for `<tier> <checker>` and each main harness), and `company`
# (whether each company is in use).
#
# After `name`, `description`, and an optional `tools` line, an agent file
# holds two maps, each key two spaces in: a home entry per main harness, and
# a backup entry for Claude Code and Codex. Antigravity has no backup: it runs
# only inside T3, and link.sh installs no agent file there.
#
#   home:
#     claude: <place> <model> <effort>[, <place> <model> <effort>]...
#     codex: <place> <model> <effort>
#     antigravity: <place> <model> <effort>
#   backup:
#     claude: <model> <effort>
#     codex: <model> <effort>
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
# `name` and `description` are check.sh's to check; the `description:` line
# is copied as written, so it must be one line.
#
# check: one problem per line on stdout, nothing for a good file. Exit 0.
# render: the file of <harness> on stdout, on the model and effort of the
# last try of its try list, <marker> in a comment at its top,
# exit 0; or the first problem on stderr, exit 1. <harness> is claude or
# codex: Antigravity gets no agent file. tools: the agent's Claude Code tools on one line, every one
# of them for a file with no tools line, exit 0. The subagent gate reads it.
# models: one line per home and backup, <map> <harness> <place> <model>, in
# file order, exit 0. The map is home for the first home, home<n> for the
# n-th, and backup, whose place is its harness. sync-harnesses reads it.
# tries: the agent's try list for the main agent of <harness>, claude,
# codex, or antigravity, one `<company> <model> <effort>` line per try, in
# order, exit 0.
# start: how the main agent of <harness>, claude or codex, starts the agent
# in T3, exit 0:
# `name` when its first try is <harness> itself, else
# `t3 <company> <model> <effort>`, its first try. The subagent gate reads it.
# Any other command line: its usage on stderr, exit 64.
# The Codex form is TOML: in its strings a `\` becomes `\\`, a `"` in
# the description becomes `\"`, and a `"""` in the body becomes `""\"`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tiers="${MODEL_TIERS:-$here/../shared/model-tiers.md}"
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }

mode="${1:-}"
case "$mode" in
  check|tools|models) harness=""; marker="" ;;
  render) u='usage: agents.sh render <harness> <marker>'
          [ $# -eq 3 ] || die_usage "$u"
          harness="$2"; marker="$3"
          case "$harness" in claude|codex) ;; *) die_usage "$u" "unknown harness: $harness" ;; esac ;;
  tries) u='usage: agents.sh tries <harness>'
         [ $# -eq 2 ] || die_usage "$u"
         harness="$2"; marker=""
         case "$harness" in claude|codex|antigravity) ;; *) die_usage "$u" "unknown harness: $harness" ;; esac ;;
  start) u='usage: agents.sh start <harness>'
         [ $# -eq 2 ] || die_usage "$u"
         harness="$2"; marker=""
         case "$harness" in claude|codex) ;; *) die_usage "$u" "unknown harness: $harness" ;; esac ;;
  *) die_usage "usage: agents.sh check | agents.sh render <harness> <marker> | agents.sh tools | agents.sh models | agents.sh start <harness> | agents.sh tries <harness>" ;;
esac

LC_ALL=C awk -v mode="$mode" -v harness="$harness" -v marker="$marker" -v tiers="$tiers" -f "$here/frontmatter.awk" -f <(cat <<'AWK'
  function problem(s) { probs[++np] = s }
  # read_tiers: the three tables of the tier file. getline keeps stdin for
  # frontmatter.awk. tt_rows[t] counts the rows of table t, whose header is
  # tt_head[t, i] and whose row r is tt_cell[t, r, i].
  function read_tiers(  line, n, c, k, t, in_t, r) {
    while ((getline line < tiers) > 0) {
      if (line ~ /^```tsv[ \t]*$/) { in_t = 1; t = ""; continue }
      if (in_t && line ~ /^```[ \t]*$/) { in_t = 0; continue }
      if (!in_t) continue
      k = split(line, c, "\t")
      if (t == "") { t = c[1]; tt_cols[t] = k; for (n = 1; n <= k; n++) tt_head[t, n] = c[n]; continue }
      r = ++tt_rows[t]
      for (n = 1; n <= k; n++) tt_cell[t, r, n] = c[n]
    }
    close(tiers)
    for (r = 1; r <= tt_rows["tier"]; r++) for (n = 2; n <= tt_cols["tier"]; n++)
      tier_model[tt_cell["tier", r, 1], tt_head["tier", n]] = tt_cell["tier", r, n]
    for (r = 1; r <= tt_rows["row"]; r++) for (n = 2; n <= tt_cols["row"]; n++)
      try_order[tt_cell["row", r, 1], tt_head["row", n]] = tt_cell["row", r, n]
  }
  # tries(h, t, c): fills tries_out[1..n] with the try list of tier t and
  # checker c under main harness h, `<company> <model> <effort>` each; returns n.
  function tries(h, t, c,  cs, n, i) {
    n = split(try_order[t " " c, h], cs, /, */)
    for (i = 1; i <= n; i++) tries_out[i] = cs[i] " " tier_model[t, cs[i]]
    return n }
  function model_ok(place, sec, m) {
    if (place == "claude") return m ~ /^claude-[a-z]+-[0-9]+-[0-9]+$/
    if (place == "codex") return m ~ /^gpt-[0-9]+(\.[0-9]+)?-[a-z]+$/
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
    else { place = h; m = w[1]; e = w[2]; want = 2 }
    if (!model_ok(place, sec, m)) { problem(at m " is not a model " place " takes"); return }
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
    read_tiers()
    if (mode == "tries") { n = tries(harness, fm["tier"], fm["checker"]); for (i = 1; i <= n; i++) print tries_out[i]; exit 0 }
    split("claude codex antigravity", hs, " ")
    for (i = 1; i <= 3; i++) if (!seen["home", hs[i]]) problem("missing home for " hs[i])
    for (i = 1; i <= 2; i++) if (!seen["backup", hs[i]]) problem("missing backup for " hs[i])
    if (mode == "models") {
      for (i = 1; i <= ne; i++) { split(order[i], k, SUBSEP)
        if (k[1] == "home") { nh = split(entry[k[1], k[2]], items, ",")
          for (j = 1; j <= nh; j++) { split(items[j], w, " "); print (j == 1 ? "home" : "home" j), k[2], w[1], w[2] } }
        else { split(entry[k[1], k[2]], w, " "); print k[1], k[2], k[2], w[1] } }
      exit 0 }
    if (mode == "start") {
      tries(harness, fm["tier"], fm["checker"]); split(tries_out[1], w, " ")
      if (w[1] == harness) print "name"
      else print "t3", w[1], w[2], w[3]
      exit 0 }
    if (fm_block["name"]) problem("name on more than one line")
    if (fm_block["description"]) problem("description on more than one line")
    for (i = 1; i <= ne; i++) { split(order[i], k, SUBSEP)
      if (k[2] != "claude" && k[2] != "codex" && k[2] != "antigravity") problem("unknown harness: " k[2])
      else if (k[1] == "backup" && k[2] == "antigravity") problem("backup for antigravity: Antigravity takes no backup")
      else entry_problems(k[1], k[2]) }
    if (mode == "check") { for (i = 1; i <= np; i++) print probs[i]; exit 0 }
    if (np) { print probs[1] > "/dev/stderr"; exit 1 }
    n = tries(harness, fm["tier"], fm["checker"]); split(tries_out[n], w, " "); b[1] = w[2]; b[2] = w[3]
    if (harness == "claude") {
      print "---"; print "# " marker; print rawname; print rawdesc
      if (rawtools != "") print rawtools
      print "model: " b[1]; print "effort: " b[2]; print "---"
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
