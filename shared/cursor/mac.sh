#!/usr/bin/env bash
# A Namespace Mac that runs a Cursor My Machines worker, for a Cursor agent
# that needs macOS (Xcode, the iOS Simulator). The shared Cursor client,
# cursor.sh next to this file, calls it; nothing else does.
#
#   mac.sh up <worker> <repo-url> <base> [<worker id>]
#                                          -> "<instance id>\t<worker id>" once the worker runs
#   mac.sh alive <instance>                -> exit 0 when the Mac and its worker run
#   mac.sh down <instance>                 -> deletes the keys and destroys the Mac
#
# up rents a Mac (macOS 26, Xcode 26) for at most CURSOR_MAC_HOURS hours
# (default 4), so a Mac no one destroys still ends. It sends the Cursor key and
# the user's GitHub login (`gh auth token`) through stdin into a file only the
# Mac's user reads, never on a command line, installs the Cursor CLI, clones
# the repo at <base>, and starts `agent worker start --name <worker>` in it.
# Cursor sends an agent's runs to the worker ID it first ran on, not to the
# name, and the CLI keeps that ID per name in ~/.cursor/agent-cli-state.json.
# So up prints the worker's ID, and an up given that ID writes it there
# before the worker starts: the new Mac takes the old worker's place.
# Cursor's dashboard secrets never reach a worker, so the worker's own
# environment carries GH_TOKEN, and git pushes with it. A Mac that fails to
# come up is destroyed before up exits.
# Proven 2026-11-02: a create call to a machine agent blocks until its run
# ends; a run sent while no worker runs ends as ERROR in about 20 s, not
# queued; a worker on a new Mac with the same name gets a new ID, and the
# agent's runs fail, unless it starts with the old ID; the same worker ID
# continues the agent, memory kept.
set -euo pipefail

HOURS="${CURSOR_MAC_HOURS:-4}"

die() { echo "mac.sh: $*" >&2; exit 1; }

# remote INSTANCE SCRIPT -> runs SCRIPT on the Mac, with no stdin
remote() { nsc ssh "$1" -T -- "$2" </dev/null; }

# remote_in INSTANCE SCRIPT -> the same, stdin passed through
remote_in() { nsc ssh "$1" -T -- "$2"; }

cmd_up() {
  local worker="${1:-}" repo="${2:-}" base="${3:-}" wid="${4:-}"
  [[ -n "$worker" && -n "$repo" && -n "$base" ]] || die "usage: mac.sh up <worker> <repo-url> <base> [<worker id>]"
  [[ "$worker" =~ ^[A-Za-z0-9-]+$ ]] || die "worker name: letters, digits, and - only"
  [[ -z "$wid" || "$wid" =~ ^[0-9a-f-]{36}$ ]] || die "worker id: a UUID"
  local dir cid id key token name state=""
  key="${CURSOR_API_KEY:-}"
  [[ -n "$key" ]] || die "CURSOR_API_KEY is not set"
  token=$(gh auth token 2>/dev/null) || die "gh is not signed in: run gh auth login"
  dir=$(mktemp -d); cid="$dir/cid"
  nsc create </dev/null --machine_type mac/silicon:6x14 \
    --selectors macos.version=26.x,image.with=xcode-26 \
    --duration "${HOURS}h" --purpose "handoff $worker" \
    --cidfile "$cid" --wait_timeout 5m >"$dir/create.log" 2>&1 \
    || { tail -3 "$dir/create.log" >&2; rm -rf "$dir"; die "nsc create failed"; }
  id=$(cat "$cid"); rm -rf "$dir"
  [[ -n "$id" ]] || die "nsc create printed no instance id"
  # From here on, a failure must not leave a rented Mac behind.
  name="${repo##*/}"
  { printf 'export CURSOR_API_KEY=%q\n' "$key"; printf 'export GH_TOKEN=%q\n' "$token"; } \
    | remote_in "$id" 'umask 077; cat > ~/.ho-env' >/dev/null \
    || { cmd_down "$id" >/dev/null 2>&1 || true; die "could not send the keys to $id"; }
  [[ -n "$wid" ]] && state="mkdir -p ~/.cursor && printf '{\"version\":1,\"workerIdsByDisplayName\":{\"%s\":\"%s\"}}\n' $worker $wid > ~/.cursor/agent-cli-state.json"
  # git asks the helper for the token each time, so the token never sits in
  # .git/config; the image's keychain helper is dropped, as SSH cannot write
  # to the keychain.
  wid=$(remote "$id" "set -e
    curl -fsS https://cursor.com/install | bash >/dev/null 2>&1
    $state
    git config --global credential.helper ''
    git config --global --add credential.helper '!f() { . ~/.ho-env; echo username=x-access-token; echo \"password=\$GH_TOKEN\"; }; f'
    mkdir -p ~/work && cd ~/work && rm -rf $(printf %q "$name")
    git clone -q --branch $(printf %q "$base") $(printf %q "$repo.git") $(printf %q "$name")
    cd $(printf %q "$name")
    (. ~/.ho-env; ~/.local/bin/agent worker start --name $(printf %q "$worker") </dev/null >~/worker.log 2>&1 &)
    for i in \$(seq 1 45); do
      if grep -q 'Worker is now running' ~/worker.log 2>/dev/null; then
        w=\$(grep -o '\"$worker\": *\"[0-9a-f-]*\"' ~/.cursor/agent-cli-state.json 2>/dev/null | grep -o '[0-9a-f-]\{36\}' || true)
        if [ -n \"\$w\" ]; then echo \"\$w\"; exit 0; fi
      fi
      sleep 2
    done
    grep -v -i keychain ~/worker.log | tail -5 >&2; exit 1") \
    || { cmd_down "$id" >/dev/null 2>&1 || true; die "the worker did not start on $id"; }
  wid=$(tail -1 <<<"$wid")
  [[ "$wid" =~ ^[0-9a-f-]{36}$ ]] \
    || { cmd_down "$id" >/dev/null 2>&1 || true; die "the worker on $id has no ID in agent-cli-state.json"; }
  printf '%s\t%s\n' "$id" "$wid"
}

cmd_alive() {
  local id="${1:-}"
  [[ -n "$id" && "$id" != "-" ]] || return 1
  remote "$id" 'pgrep -f "worker start" >/dev/null' >/dev/null 2>&1 || return 1
}

cmd_down() {
  local id="${1:-}"
  [[ -n "$id" && "$id" != "-" ]] || die "instance id required"
  remote "$id" 'pkill -f "worker start"; rm -f ~/.ho-env' >/dev/null 2>&1 || true
  nsc destroy "$id" --force </dev/null >/dev/null 2>&1 || true
  echo "destroyed $id"
}

for c in nsc gh; do command -v "$c" >/dev/null || die "$c is required"; done
case "${1:-}" in
  up)    shift; cmd_up "$@" ;;
  alive) shift; cmd_alive "$@" ;;
  down)  shift; cmd_down "$@" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 1 ;;
esac
