# frontmatter.awk: the one reader of a skill's or an agent's frontmatter.
# check.sh and agents.sh load it with `awk -f` before their own program,
# which holds only functions and an END block that reads these. check.sh also
# reads a skill's agents/openai.yaml through it, with a `---` line put first,
# for its `policy:` map.
#
#   fm_closed     1 when line 1 is `---` and a later `---` line closes it
#   fm[k]         the value of the top-level key k, by val. A block scalar's
#                 value is its indented lines, less the first line's indent,
#                 joined by newlines, as YAML reads it.
#   fm_raw[k]     the line of key k as written
#   fm_nr[k]      the line number of key k
#   fm_block[k]   1 when k's value is a block scalar: `|` or `>`, with an
#                 optional `-` or `+`
#   fm_map[k, s]  the value, by val, of an indented `s: value` line under a
#                 key k with no value of its own
#   fm_keys[n]    each `k SUBSEP s` of fm_map in file order, fm_nkeys of them
#   fm_body[n]    each line under the closing `---`, fm_nbody of them
#   fm_end        the line number of the closing `---`
#
# Outside a block scalar, a blank line or a `#` comment line is skipped and
# ends no map. Any other unindented line ends a block scalar or a map.
#
# val(s): the value of the `key: value` line s. A quoted value is what the
# quotes hold, with `''` read as `'` and a `\`-escaped char kept; an unquoted
# one loses its `#` comment, and `null` or `~` is empty.
function val(s,  c, i, ch, v, q) { q = "\047"; sub(/^[^:]*:[ \t]*/, "", s); c = substr(s, 1, 1)
  if (c == "\"" || c == q) {
    for (i = 2; i <= length(s); i++) { ch = substr(s, i, 1)
      if (c == q && ch == q && substr(s, i + 1, 1) == q) { v = v q; i++; continue }
      if (c == "\"" && ch == "\\") { v = v substr(s, i, 2); i++; continue }
      if (ch == c) return v
      v = v ch }
    return s }
  sub(/(^|[ \t]+)#.*$/, "", s); sub(/[ \t]+$/, "", s)
  return (s == "~" || tolower(s) == "null") ? "" : s }

NR == 1 { if ($0 != "---") exit; next }
fm_closed { fm_body[++fm_nbody] = $0; next }
fm_bk != "" && /^[ \t]*$/ { if (fm[fm_bk] != "") fm_gap = fm_gap "\n"; next }
fm_bk != "" && /^[ \t]/ {
  match($0, /^[ \t]*/); if (fm[fm_bk] == "") fm_ind = RLENGTH
  fm_line = substr($0, (RLENGTH < fm_ind ? RLENGTH : fm_ind) + 1)
  fm[fm_bk] = (fm[fm_bk] == "") ? fm_line : fm[fm_bk] "\n" fm_gap fm_line; fm_gap = ""; next
}
{ fm_bk = "" }
/^[ \t]*(#|$)/ { next }
/^[ \t]/ {
  if (fm_mk == "") next
  fm_line = $0; sub(/^[ \t]+/, "", fm_line)
  fm_sub = fm_line; sub(/:.*$/, "", fm_sub)
  fm_map[fm_mk, fm_sub] = val(fm_line); fm_keys[++fm_nkeys] = fm_mk SUBSEP fm_sub; next
}
{ fm_mk = "" }
$0 == "---" { fm_closed = 1; fm_end = NR; next }
/^[^:]+:/ {
  fm_k = $0; sub(/:.*$/, "", fm_k); fm_raw[fm_k] = $0; fm_nr[fm_k] = NR; fm[fm_k] = val($0); fm_block[fm_k] = 0
  if (fm[fm_k] ~ /^[|>][-+]?$/) { fm[fm_k] = ""; fm_block[fm_k] = 1; fm_bk = fm_k }
  else if (fm[fm_k] == "") fm_mk = fm_k
}
