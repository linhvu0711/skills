#!/usr/bin/env bash
# Render a shared handoff template for one executor.
#
#   render.sh <devin|cursor|local> <rules|prompt>
#
# The templates in this directory are shared by /handoff-devin,
# /handoff-cursor, and /ship. A block between `<!-- devin -->` and
# `<!-- /devin -->` (or `cursor`, or `local`) is kept only for that
# executor; a block between `<!-- cloud -->` and `<!-- /cloud -->` is kept
# for devin and cursor and dropped for local. Blocks nest. The marker
# lines go. A line that starts with `<!-- template` is a note for editors
# and goes. A line `<!-- include <path> -->` is replaced by that file,
# path relative to this directory; its `<!-- template` lines go too.
# `{{app}}`, `{{me}}`, `{{session}}`, `{{here}}`, and `{{caller}}` are
# words that differ per executor; see the case below. `{{skills}}` is the
# absolute path of the skills folder, for a rendered prompt that is read
# outside any skill folder.
set -euo pipefail

ex=${1:-}; f=${2:-}
dir=$(cd "$(dirname "$0")" && pwd)
skills=$(cd "$dir/../../skills" && pwd -P)
usage="usage: render.sh <devin|cursor|local> <rules|prompt>"
case "$ex" in devin|cursor|local) ;; *) echo "$usage" >&2; exit 64 ;; esac
case "$f" in rules|prompt) ;; *) echo "$usage" >&2; exit 64 ;; esac

case "$ex" in
  devin)  app=Devin;       session=session; here="in the session";      caller=/handoff-devin ;;
  cursor) app=Cursor;      session=run;     here="in your reply";       caller=/handoff-cursor ;;
  local)  app="Devin CLI"; session=session; here="in your last message"; caller=/ship ;;
esac

awk -v ex="$ex" -v dir="$dir" '
  function keep(m) { return (m == ex) || (m == "cloud" && ex != "local") }
  function anyskip(  i) { for (i = 1; i <= n; i++) if (s[i]) return 1; return 0 }
  /^<!-- (devin|cursor|local|cloud) -->$/  { n++; s[n] = !keep($2); skip = anyskip(); next }
  /^<!-- \/(devin|cursor|local|cloud) -->$/ { if (n > 0) n--; skip = anyskip(); next }
  /^<!-- template/             { next }
  /^<!-- include .* -->$/      { if (!skip) { f = dir "/" $3; while ((getline l < f) > 0) if (l !~ /^<!-- template/) print l; close(f) } next }
  !skip                         { print }
' "$dir/$f.md" \
| sed -e "s/{{app}}/$app/g" -e "s/{{me}}/$ex/g" -e "s/{{session}}/$session/g" -e "s/{{here}}/$here/g" -e "s#{{caller}}#$caller#g" -e "s#{{skills}}#$skills#g"
