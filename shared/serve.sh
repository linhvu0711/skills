#!/bin/sh
# Serve a page on 127.0.0.1 and print its URL.
#
#   serve.sh <dir> <file.html>
#
# Exit 64: a wrong command line, its usage on stderr.
#
# A port counts only when it serves this exact file from <dir>. A server
# on 8765 that holds some other folder (an old page folder, a diagram, an
# other session) is left alone, and the next free port gets a new server.
set -eu

# sh has no BASH_SOURCE; serve.sh is run, never sourced, so $0 names it.
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/die.sh"
[ $# -eq 2 ] || die_usage 'usage: serve.sh <dir> <file.html>'
dir=$1 file=$2
[ -f "$dir/$file" ] || die "$dir/$file: not found"

serves() { curl -sf --max-time 2 "http://127.0.0.1:$1/$file" 2>/dev/null | cmp -s - "$dir/$file"; }

for port in $(seq 8765 8784); do
  if serves "$port"; then
    echo "http://127.0.0.1:$port/$file"; exit 0
  fi
  lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && continue
  (cd "$dir" && exec nohup python3 -m http.server "$port" --bind 127.0.0.1 </dev/null >/dev/null 2>&1) &
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    serves "$port" && { echo "http://127.0.0.1:$port/$file"; exit 0; }
    sleep 0.2
  done
  die "started a server on $port, but it does not serve $file"
done
die "no free port in 8765-8784"
