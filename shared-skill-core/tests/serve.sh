# serve.sh: the cases for the shared core's serve.sh, driven through fake
# lsof, curl, and python3. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# sv_setup: a fresh temp folder T with an empty $T/bin first on PATH, and the
# fakes in it. A port is busy when $T/busy.<port> exists, and serves the
# folder that $T/root.<port> links to.
sv_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; mkdir "$T/bin"
  export PATH="$T/bin:$PATH"
  # lsof -iTCP:<port> -sTCP:LISTEN: exit 0 when the port is busy.
  printf '#!/bin/sh\nport=${1#-iTCP:}\n[ -e "%s/busy.$port" ]\n' "$T" > "$T/bin/lsof"
  # curl … http://127.0.0.1:<port>/<path>: print the file the port serves, or
  # fail as curl does when nothing answers.
  printf '#!/bin/sh\nfor a; do url=$a; done\nrest=${url#http://127.0.0.1:}\nport=${rest%%%%/*}\nf="%s/root.$port/${rest#*/}"\n[ -f "$f" ] || exit 7\ncat "$f"\n' "$T" > "$T/bin/curl"
  # python3 -m http.server <port> --bind 127.0.0.1: log the port and folder,
  # and serve the folder from then on.
  printf '#!/bin/sh\necho "$3 $(pwd -P)" >> "%s/python3.calls"\nln -s "$(pwd -P)" "%s/root.$3"\n' "$T" "$T" > "$T/bin/python3"
  chmod 755 "$T/bin/lsof" "$T/bin/curl" "$T/bin/python3"
  mkdir "$T/d"
}

# no_server: serve.sh started no server.
no_server() { eq python3.calls "" "$(cat "$T/python3.calls" 2>/dev/null || true)"; }

t_sv_reuses_server() {
  sv_setup; printf a > "$T/d/report.html"
  ln -s "$T/d" "$T/root.8765"; touch "$T/busy.8765"
  run sh "$here/../serve.sh" "$T/d" report.html
  eq exit 0 "$code"
  eq stdout "http://127.0.0.1:8765/report.html" "$out"
  no_server
}

t_sv_skips_other_folder() {
  sv_setup; printf a > "$T/d/report.html"
  mkdir "$T/o"; printf b > "$T/o/report.html"
  ln -s "$T/o" "$T/root.8765"; touch "$T/busy.8765"
  run sh "$here/../serve.sh" "$T/d" report.html
  eq exit 0 "$code"
  eq stdout "http://127.0.0.1:8766/report.html" "$out"
  eq python3.calls "8766 $T/d" "$(cat "$T/python3.calls")"
}

t_sv_missing_file() {
  sv_setup
  run sh "$here/../serve.sh" "$T/d" nope.html
  eq exit 1 "$code"
  eq stderr "$T/d/nope.html: not found" "$err"
  eq stdout "" "$out"
  no_server
}

cases=(
  "serve reuses a server that gives back the file|t_sv_reuses_server"
  "serve skips a port that holds another folder|t_sv_skips_other_folder"
  "serve stops on a missing file|t_sv_missing_file"
)
