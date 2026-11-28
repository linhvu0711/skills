#!/usr/bin/env bash
# agents.sh: the one reader of a skill agent's tier and of the tier file.
# check.sh asks it for a file's problems; link.sh asks it for the file each
# harness reads.
#
#   agents.sh check < skills/<name>/agents/<agent>.md
#   agents.sh render <harness> <marker> < skills/<name>/agents/<agent>.md
#   agents.sh start <harness> < skills/<name>/agents/<agent>.md
#   agents.sh tries <harness> < skills/<name>/agents/<agent>.md
#   agents.sh orders <harness>
#   agents.sh in-use
#   agents.sh tiers
#
# A shared agent, shared/agents/<agent>.md, is read the same way.
#
# After `name`, `description`, and an optional `tools` line, an agent file
# names its `tier:`, a row of the tier-models table, and its `checker:`, yes
# or no. shared/model-tiers.md, or the file $MODEL_TIERS names, joins the two
# into a try list for each main harness. Its three fenced `tsv` tables are
# found by the first cell of their header row: `tier` (the model and effort
# each company runs at each tier), `row` (the companies a subagent tries, in
# order, for `<tier> <checker>` and each main harness), and `company`
# (whether each company is in use). A tier-models cell is `none` or
# `<model> <effort>`, and each company takes models of one form and a set of
# efforts, as T3 and each harness list them on 2026-11-20:
#
#   claude       claude-<family>-<n>-<n>     low medium high xhigh max
#   codex        gpt-<n>[.<n>]-<name>        low medium high xhigh max ultra
#   antigravity  gemini-<n>[.<n>]-<name>     low medium high xhigh
#   devin        a T3 Devin id, as swe-2-high  none low medium high xhigh max
#
# A try-order cell lists companies joined by `, `, each with a model at the
# row's tier, and a claude or codex cell ends on that harness, since outside
# T3 only the last try runs.
#
# check.sh checks `name` and `description`. This script also rejects either
# one on more than one line, since the `description:` line is copied as written.
#
# check: one `<line>: <problem>` line per problem on stdout, nothing for a
# good file. A missing tier or checker line is named at the closing `---`.
# Exit 0.
# tiers: the same for the tier file, exit 0. It reads no agent file.
# render: the file of <harness> on stdout, on the model and effort of the
# last try of its try list, <marker> in a comment at its top,
# exit 0; or the first problem on stderr, exit 1. <harness> is claude or
# codex: Antigravity gets no agent file. tools: the agent's Claude Code tools on one line, every one
# of them for a file with no tools line, exit 0. The subagent gate reads it.
# orders: every try of every try-order row for the main agent of <harness>,
# in table order, one `<tier> <checker> <company> <model> <effort>` line
# each, exit 0. in-use: each company in use, one per line, exit 0. Neither
# reads an agent file. sync-harnesses reads both.
# tries: the agent's try list for the main agent of <harness>, claude,
# codex, or antigravity, one `<company> <model> <effort>` line per try, in
# order, exit 0.
# start: how the main agent of <harness>, claude or codex, starts the agent
# in T3, exit 0:
# `name` when its first try is <harness> itself, else
# `t3 <company> <model> <effort>`, its first try. The subagent gate reads it.
# tries and start, like render, print the first problem on stderr and exit 1
# for a file check names.
# Any other command line: its usage on stderr, exit 64.
# The Codex form is TOML: in its strings a `\` becomes `\\`, a `"` in
# the description becomes `\"`, and a `"""` in the body becomes `""\"`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tiers="${MODEL_TIERS:-$here/../shared/model-tiers.md}"
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }

mode="${1:-}"
case "$mode" in
  check|tools|in-use|tiers) harness=""; marker="" ;;
  orders) u='usage: agents.sh orders <harness>'
          [ $# -eq 2 ] || die_usage "$u"
          harness="$2"; marker=""
          case "$harness" in claude|codex|antigravity) ;; *) die_usage "$u" "unknown harness: $harness" ;; esac ;;
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
  *) die_usage "usage: agents.sh check | agents.sh render <harness> <marker> | agents.sh tools | agents.sh start <harness> | agents.sh tries <harness> | agents.sh orders <harness> | agents.sh in-use | agents.sh tiers" ;;
esac
# orders, in-use, and tiers read no agent file, so a caller's stdin stays its own.
case "$mode" in orders|in-use|tiers) exec </dev/null ;; esac

LC_ALL=C awk -v mode="$mode" -v harness="$harness" -v marker="$marker" -v tiers="$tiers" -f "$here/frontmatter.awk" -f <(cat <<'AWK'
  function problem(n, s) { probs[++np] = n ": " s }
  # read_tiers: the three tables of the tier file. getline keeps stdin for
  # frontmatter.awk. tt_rows[t] counts the rows of table t, whose header is
  # tt_head[t, i], at line tt_hnr[t], and whose row r is tt_cell[t, r, i], of
  # tt_n[t, r] cells at line tt_nr[t, r].
  function read_tiers(  line, ln, n, c, k, t, in_t, r) {
    while ((getline line < tiers) > 0) { ln++
      if (line ~ /^```tsv[ \t]*$/) { in_t = 1; t = ""; continue }
      if (in_t && line ~ /^```[ \t]*$/) { in_t = 0; continue }
      if (!in_t) continue
      k = split(line, c, "\t")
      if (t == "") { t = c[1]; tt_cols[t] = k; tt_hnr[t] = ln; for (n = 1; n <= k; n++) tt_head[t, n] = c[n]; continue }
      r = ++tt_rows[t]; tt_n[t, r] = k; tt_nr[t, r] = ln
      for (n = 1; n <= k; n++) tt_cell[t, r, n] = c[n]
    }
    close(tiers)
    for (r = 1; r <= tt_rows["tier"]; r++) { known_tier[tt_cell["tier", r, 1]] = 1
      for (n = 2; n <= tt_cols["tier"]; n++) tier_model[tt_cell["tier", r, 1], tt_head["tier", n]] = tt_cell["tier", r, n] }
    for (n = 2; n <= tt_cols["tier"]; n++) company[tt_head["tier", n]] = 1
    for (r = 1; r <= tt_rows["row"]; r++) for (n = 2; n <= tt_cols["row"]; n++)
      try_order[tt_cell["row", r, 1], tt_head["row", n]] = tt_cell["row", r, n]
  }
  # tries(h, t, c): fills tries_out[1..n] with the try list of tier t and
  # checker c under main harness h, `<company> <model> <effort>` each; returns n.
  function tries(h, t, c,  cs, n, i) {
    n = split(try_order[t " " c, h], cs, /, */)
    for (i = 1; i <= n; i++) tries_out[i] = cs[i] " " tier_model[t, cs[i]]
    return n }
  function model_ok(place, m) {
    if (place == "claude") return m ~ /^claude-[a-z]+-[0-9]+-[0-9]+$/
    if (place == "codex") return m ~ /^gpt-[0-9]+(\.[0-9]+)?-[a-z]+$/
    if (place == "antigravity") return m ~ /^gemini-[0-9]+(\.[0-9]+)?-[a-z]+$/
    return m ~ /^[a-z0-9][a-z0-9.-]*$/ }
  function effort_ok(place, e) { return index(" " efforts[place] " ", " " e " ") > 0 }
  # tier_problems: the problems of the tier file, each at its row's line.
  # A row with the wrong cell count gets no other check.
  function tier_problems(  t, r, i, n, at, w, k, cs, last, row, rw) {
    split("tier row company", ts, " "); split("tier models|try order|in use", tn, "|")
    for (i = 1; i <= 3; i++) if (!(ts[i] in tt_cols)) problem(1, "no " tn[i] " table")
    for (i = 1; i <= 3; i++) { t = ts[i]
      for (r = 1; r <= tt_rows[t]; r++) if (tt_n[t, r] != tt_cols[t]) { bad[t, r] = 1
        problem(tt_nr[t, r], "row has " tt_n[t, r] " cells, its header has " tt_cols[t]) } }
    for (r = 1; r <= tt_rows["tier"]; r++) { if (bad["tier", r]) continue
      for (i = 2; i <= tt_cols["tier"]; i++) {
        k = tt_head["tier", i]; v = tt_cell["tier", r, i]; at = "tier " tt_cell["tier", r, 1] " for " k ": "
        if (v == "none") continue
        n = split(v, w, " ")
        if (!model_ok(k, w[1])) problem(tt_nr["tier", r], at w[1] " is not a model " k " takes")
        else if (n < 2) problem(tt_nr["tier", r], at "no effort")
        else if (!effort_ok(k, w[2])) problem(tt_nr["tier", r], at w[2] " is not an effort " k " takes")
        else if (n > 2) problem(tt_nr["tier", r], at "one effort, then nothing") } }
    # tries looks a row up by its exact key, so a key in another form, or a
    # row twice or not at all, would give an agent no try.
    for (r = 1; r <= tt_rows["row"]; r++) { if (bad["row", r]) continue
      row = tt_cell["row", r, 1]; split(row, rw, " ")
      if (row !~ /^[^ ]+ (yes|no)$/ || !(rw[1] in known_tier)) { problem(tt_nr["row", r], "row " row " is not <tier> <yes|no>"); continue }
      if (row in row_seen) { problem(tt_nr["row", r], "row " row " twice"); continue }
      row_seen[row] = 1
      for (i = 2; i <= tt_cols["row"]; i++) {
        h = tt_head["row", i]; at = row " for " h ": "
        n = split(tt_cell["row", r, i], cs, /, */)
        if (n == 0) { problem(tt_nr["row", r], at "no try"); continue }
        for (k = 1; k <= n; k++)
          if (!(cs[k] in company)) problem(tt_nr["row", r], at "unknown company: " cs[k])
          else if (tier_model[rw[1], cs[k]] == "none" || tier_model[rw[1], cs[k]] == "") problem(tt_nr["row", r], at cs[k] " has no model at tier " rw[1])
        last = cs[n]
        if ((h == "claude" || h == "codex") && last != h) problem(tt_nr["row", r], at "the last try is " last ", not " h) } }
    if ("row" in tt_cols) for (t in known_tier) for (i = 1; i <= 2; i++) {
      row = t " " (i == 1 ? "no" : "yes")
      if (!(row in row_seen)) problem(tt_hnr["row"], "no try order row " row) }
    for (r = 1; r <= tt_rows["company"]; r++) { if (bad["company", r]) continue
      v = tt_cell["company", r, 2]
      if (v != "yes" && v != "no") problem(tt_nr["company", r], "in use for " tt_cell["company", r, 1] " is yes or no, not " v) }
  }
  # agent_problems: the problems of the agent file, each at its line.
  function agent_problems() {
    if (fm_block["name"]) problem(fm_nr["name"], "name on more than one line")
    if (fm_block["description"]) problem(fm_nr["description"], "description on more than one line")
    if (!("tier" in fm_nr)) problem(fm_end, "no tier line")
    else if (!(fm["tier"] in known_tier)) problem(fm_nr["tier"], "unknown tier: " fm["tier"])
    if (!("checker" in fm_nr)) problem(fm_end, "no checker line")
    else if (fm["checker"] != "yes" && fm["checker"] != "no") problem(fm_nr["checker"], "checker is yes or no, not " fm["checker"])
  }
  # try_problems(h): the problems of the agent's try list under main harness
  # h, at its tier line: no try, or a try with no model its company takes.
  # check.sh checks the whole tier file; this keeps render, tries, and start
  # from passing on a file it has not checked yet.
  function try_problems(h,  n, i, w) {
    n = tries(h, fm["tier"], fm["checker"])
    if (n == 0) problem(fm_nr["tier"], "no try for " h " at " fm["tier"] " " fm["checker"])
    for (i = 1; i <= n; i++) { split(tries_out[i], w, " ")
      if (!model_ok(w[1], w[2]) || !effort_ok(w[1], w[3])) problem(fm_nr["tier"], "tier " fm["tier"] " for " w[1] ": " (w[2] == "" ? "no model" : tier_model[fm["tier"], w[1]]) " is no model it can run") } }
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
  BEGIN { efforts["claude"] = "low medium high xhigh max"
          efforts["codex"] = "low medium high xhigh max ultra"
          efforts["antigravity"] = "low medium high xhigh"
          efforts["devin"] = "none low medium high xhigh max" }
  END {
    if (mode == "orders" || mode == "in-use" || mode == "tiers") { read_tiers()
      if (mode == "tiers") { tier_problems(); for (i = 1; i <= np; i++) print probs[i]; exit 0 }
      if (mode == "in-use") { for (r = 1; r <= tt_rows["company"]; r++) if (tt_cell["company", r, 2] == "yes") print tt_cell["company", r, 1]; exit 0 }
      for (r = 1; r <= tt_rows["row"]; r++) { row = tt_cell["row", r, 1]; split(row, rw, " ")
        n = tries(harness, rw[1], rw[2]); for (i = 1; i <= n; i++) print row, tries_out[i] }
      exit 0 }
    if (!fm_closed) {
      if (mode != "check") { print "1: missing frontmatter" > "/dev/stderr"; exit 1 }
      exit 0
    }
    name = fm["name"]; desc = fm["description"]; tools = fm["tools"]
    rawname = fm_raw["name"]; rawdesc = fm_raw["description"]; rawtools = fm_raw["tools"]
    if (mode == "tools") { print claude_tools(tools); exit 0 }
    read_tiers(); agent_problems()
    if (mode == "check") { for (i = 1; i <= np; i++) print probs[i]; exit 0 }
    if (!np) try_problems(harness)
    if (np) { print probs[1] > "/dev/stderr"; exit 1 }
    n = tries(harness, fm["tier"], fm["checker"])
    if (mode == "tries") { for (i = 1; i <= n; i++) print tries_out[i]; exit 0 }
    if (mode == "start") { split(tries_out[1], w, " ")
      if (w[1] == harness) print "name"
      else print "t3", w[1], w[2], w[3]
      exit 0 }
    split(tries_out[n], w, " "); b[1] = w[2]; b[2] = w[3]
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
