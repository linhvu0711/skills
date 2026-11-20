# frontmatter.awk: val, the one reader of a frontmatter value. check.sh and
# agents.sh load it with `awk -f`, beside their own program.
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
