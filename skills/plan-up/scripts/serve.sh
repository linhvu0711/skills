#!/bin/sh
# Serve a plan page on 127.0.0.1 and print its URL.
#
#   serve.sh <dir> <file.html>
#
# A port counts only when it serves this exact file from <dir>. A server
# on 8765 that holds some other folder (an old plan folder, a diagram, an
# other session) is left alone, and the next free port gets a new server.
set -eu
dir=$1 file=$2
[ -f "$dir/$file" ] || { echo "$dir/$file: not found" >&2; exit 1; }

serves() { curl -sf "http://127.0.0.1:$1/$file" 2>/dev/null | cmp -s - "$dir/$file"; }

for port in $(seq 8765 8784); do
  if serves "$port"; then
    echo "http://127.0.0.1:$port/$file"; exit 0
  fi
  lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && continue
  (cd "$dir" && nohup python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &)
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    serves "$port" && { echo "http://127.0.0.1:$port/$file"; exit 0; }
    sleep 0.2
  done
  echo "started a server on $port, but it does not serve $file" >&2; exit 1
done
echo "no free port in 8765-8784" >&2; exit 1
