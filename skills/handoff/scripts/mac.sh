#!/usr/bin/env bash
# A Namespace Mac that runs a Cursor My Machines worker, for a Cursor agent
# that needs macOS (Xcode, the iOS Simulator). The Cursor adapter calls it;
# nothing else does. It owns the whole rental: the rows and the order in
# which a Mac is rented, named in a row, and given back.
#
#   mac.sh rent <worker> <repo-url> <base> -- <command>
#                                          -> rents a Mac, runs the command that
#                                             starts the agent on its worker and
#                                             prints "<agent>\t...", writes the
#                                             agent's row, prints the command's
#                                             output; a failed command gives the
#                                             Mac back and writes no row
#   mac.sh renew <agent> -- <command>      -> the agent's Mac runs, or it has none:
#                                             runs the command (the send). Else gives
#                                             the old Mac back, rents a new one under
#                                             the same worker name and ID, runs the
#                                             command with MAC_NEW_BASE=<base>, and
#                                             names the new Mac in the row only after
#                                             it works; when it fails, gives the new
#                                             Mac back and leaves the row
#   mac.sh return <agent> -- <command>     -> reads the row, then runs the command
#                                             (the run check); it passes: gives the
#                                             Mac back, "<agent>: destroyed <id>";
#                                             it exits 1: "<agent>: <id> kept, its run
#                                             has not ended"; no Mac: "<agent>: no Mac";
#                                             any other exit: exit 1, the Mac kept
#
# Giving a Mac back deletes the keys and destroys it: "destroyed <id>", or
# "already gone <id>"; when the Mac still runs, exit 1 with the hand command
# on stderr.
# rent and renew rent a Mac (macOS 26, Xcode 26) for at most
# HANDOFF_MAC_HOURS hours (default 4), so a Mac no one destroys still ends. It sends the Cursor key and
# the user's GitHub login (`gh auth token`) through stdin into a file only the
# Mac's user reads, never on a command line, installs the Cursor CLI, clones
# the repo at <base>, and starts `agent worker start --name <worker>` in it.
# Cursor sends an agent's runs to the worker ID it first ran on, not to the
# name, and the CLI keeps that ID per name in ~/.cursor/agent-cli-state.json.
# So rent keeps the worker's ID in the row, and renew writes it there
# before the new worker starts: the new Mac takes the old worker's place.
# Cursor's dashboard secrets never reach a worker, so the worker's own
# environment carries GH_TOKEN, and git pushes with it. A Mac that fails to
# come up is destroyed before mac.sh exits.
# Proven 2026-11-02: a create call to a machine agent blocks until its run
# ends; a run sent while no worker runs ends as ERROR in about 20 s, not
# queued; a worker on a new Mac with the same name gets a new ID, and the
# agent's runs fail, unless it starts with the old ID; the same worker ID
# continues the agent, memory kept.
# The rows, agent, worker, worker ID, repo, base, and Mac (`-` when none),
# sit in ~/.config/dispatch/cursor-macs.tsv; only mac.sh writes them. A row
# names a new Mac only after the send works, and return reads the row before
# it checks the run: so a return that sees an ended run never gives back a Mac
# that a renew rented for the next run.
set -euo pipefail

HOURS="${HANDOFF_MAC_HOURS:-4}"
MACS="$HOME/.config/dispatch/cursor-macs.tsv"

die() { echo "mac.sh: $*" >&2; exit 1; }

# need_tools -> dies when a tool a Mac step needs is missing. Only a step that
# touches a Mac runs it, so an agent with no Mac needs no nsc.
need_tools() {
  local c
  for c in nsc gh; do command -v "$c" >/dev/null || die "$c is required"; done
}

# key_check -> dies when CURSOR_API_KEY cannot run a worker
key_check() {
  local key="${CURSOR_API_KEY:-}"
  [[ -n "$key" ]] || die "CURSOR_API_KEY is not set"
  [[ "$key" == grok_* ]] && die "a Mac worker refuses grok_ keys: put a personal crsr_ key in CURSOR_API_KEY"
  return 0
}

# row_get AGENT -> "worker<TAB>worker id<TAB>repo<TAB>base<TAB>mac", or nothing
row_get() {
  [[ -f "$MACS" ]] || return 0
  awk -F'\t' -v a="$1" '$1 == a { r = $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 } END { if (r != "") print r }' "$MACS"
}

# row_set AGENT WORKER WID REPO BASE MAC -> writes the agent's row, replacing an older one
row_set() {
  local tmp
  mkdir -p "$(dirname "$MACS")"; touch "$MACS"
  tmp=$(mktemp "$MACS.XXXXXX")
  awk -F'\t' -v a="$1" '$1 != a' "$MACS" >"$tmp"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$tmp"
  mv "$tmp" "$MACS"
}

# row_clear AGENT MAC -> marks the agent as having no Mac, only while its row
# still names MAC: a renew that named a newer Mac meanwhile keeps its row.
row_clear() {
  local row w wid r b mac
  row=$(row_get "$1")
  [[ -n "$row" ]] || return 0
  IFS=$'\t' read -r w wid r b mac <<<"$row"
  [[ "$mac" == "$2" ]] && row_set "$1" "$w" "$wid" "$r" "$b" -
  return 0
}

# after_dashes ARGS -> dies unless ARGS holds "--" with a command after it
after_dashes() {
  [[ "${1:-}" == "--" && $# -gt 1 ]] || die "usage: mac.sh $verb ... -- <command>"
}

# remote INSTANCE SCRIPT -> runs SCRIPT on the Mac, with no stdin
remote() { nsc ssh "$1" -T -- "$2" </dev/null; }

# remote_in INSTANCE SCRIPT -> the same, stdin passed through
remote_in() { nsc ssh "$1" -T -- "$2"; }

cmd_up() {
  local worker="${1:-}" repo="${2:-}" base="${3:-}" wid="${4:-}"
  [[ -n "$worker" && -n "$repo" && -n "$base" ]] || die "usage: mac.sh rent <worker> <repo-url> <base> -- <command>"
  [[ "$worker" =~ ^[A-Za-z0-9-]+$ ]] || die "worker name: letters, digits, and - only"
  [[ -z "$wid" || "$wid" =~ ^[0-9a-f-]{36}$ ]] || die "worker id: a UUID"
  need_tools
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
    || { cmd_down "$id" >/dev/null || true; die "could not send the keys to $id"; }
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
    || { cmd_down "$id" >/dev/null || true; die "the worker did not start on $id"; }
  wid=$(tail -1 <<<"$wid")
  [[ "$wid" =~ ^[0-9a-f-]{36}$ ]] \
    || { cmd_down "$id" >/dev/null || true; die "the worker on $id has no ID in agent-cli-state.json"; }
  printf '%s\t%s\n' "$id" "$wid"
}

cmd_alive() {
  local id="${1:-}"
  [[ -n "$id" && "$id" != "-" ]] || return 1
  need_tools
  remote "$id" 'pgrep -f "worker start" >/dev/null' >/dev/null 2>&1 || return 1
}

cmd_down() {
  local id="${1:-}" log why
  [[ -n "$id" && "$id" != "-" ]] || die "instance id required"
  need_tools
  # A Mac whose worker hangs must still be destroyed, so this step may fail.
  remote "$id" 'pkill -f "worker start"; rm -f ~/.ho-env' >/dev/null 2>&1 || true
  log=$(mktemp)
  if nsc destroy "$id" --force </dev/null >"$log" 2>&1; then
    rm -f "$log"; echo "destroyed $id"; return 0
  fi
  # Proven 2026-11-12: nsc destroy of an ID Namespace does not hold exits 1
  # with "Failed: <id>: does not exist.", so that Mac costs nothing.
  if grep -q 'does not exist\.' "$log"; then
    rm -f "$log"; echo "already gone $id"; return 0
  fi
  why=$(grep -v -e '^info:' -e '^[[:space:]]*$' "$log" | head -1 || true)
  rm -f "$log"
  echo "mac.sh: could not destroy $id${why:+ ($why)}. It still runs and costs money until you destroy it by hand: nsc destroy $id --force" >&2
  return 1
}

cmd_rent() {
  local worker="${1:-}" repo="${2:-}" base="${3:-}" up mac wid res agent
  verb=rent; shift 3 || true; after_dashes "$@"; shift
  key_check
  up=$(cmd_up "$worker" "$repo" "$base") || exit 1
  IFS=$'\t' read -r mac wid <<<"$up"
  if ! res=$("$@" </dev/null); then
    cmd_down "$mac" >/dev/null || echo "mac.sh: no agent started, so no row names $mac" >&2
    exit 1
  fi
  IFS=$'\t' read -r agent _ <<<"$res"
  row_set "$agent" "$worker" "$wid" "$repo" "$base" "$mac"
  printf '%s\n' "$res"
}

cmd_renew() {
  local agent="${1:-}" row w wid r b mac up new
  verb=renew; shift || true; after_dashes "$@"; shift
  row=$(row_get "$agent")
  if [[ -z "$row" ]]; then "$@"; return; fi
  IFS=$'\t' read -r w wid r b mac <<<"$row"
  if cmd_alive "$mac" 2>/dev/null; then "$@"; return; fi
  key_check
  # Renting now would replace the only row that names the old Mac.
  if [[ "$mac" != "-" ]] && ! cmd_down "$mac" >/dev/null; then
    die "no note sent: $mac was not given back"
  fi
  up=$(cmd_up "$w" "$r" "$b" "$wid") || exit 1
  IFS=$'\t' read -r new _ <<<"$up"
  if ! MAC_NEW_BASE="$b" "$@"; then
    # A new Mac not given back takes the row, so a return finds it.
    cmd_down "$new" >/dev/null || row_set "$agent" "$w" "$wid" "$r" "$b" "$new"
    exit 1
  fi
  row_set "$agent" "$w" "$wid" "$r" "$b" "$new"
}

cmd_return() {
  local agent="${1:-}" row w wid r b mac line rc=0
  verb=return; shift || true; after_dashes "$@"; shift
  row=$(row_get "$agent")
  [[ -n "$row" ]] && IFS=$'\t' read -r w wid r b mac <<<"$row"
  if [[ -z "$row" || "$mac" == "-" ]]; then echo "$agent: no Mac"; return 0; fi
  "$@" || rc=$?
  if (( rc == 1 )); then echo "$agent: $mac kept, its run has not ended"; return 0; fi
  (( rc == 0 )) || die "could not check the run of $agent, so $mac is kept"
  line=$(cmd_down "$mac") || exit 1
  row_clear "$agent" "$mac"
  echo "$agent: $line"
}

case "${1:-}" in
  rent)   shift; cmd_rent "$@" ;;
  renew)  shift; cmd_renew "$@" ;;
  return) shift; cmd_return "$@" ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 1 ;;
esac
