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
#   mac.sh renew <agent> -- <command>      -> the agent's worker answers /healthz, or
#                                             it has no Mac: runs the command (the
#                                             send). A check that cannot run stops,
#                                             with no note sent and no Mac rented.
#                                             Else, the worker does not answer or
#                                             Namespace no longer holds the Mac: gives
#                                             the old Mac back, rents a new one under
#                                             the same worker name and ID, runs the
#                                             command with MAC_NEW_BASE=<base>, and
#                                             names the new Mac in the row only after
#                                             it works; when it fails, gives the new
#                                             Mac back, and names it in the row
#                                             when that give-back fails too
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
# the repo at <base>, and starts `agent worker --management-addr
# 127.0.0.1:47199 start --name <worker>` in it. It waits until the worker's
# /readyz answers 200: Cursor's health server listens only once the worker
# can take runs, and by then the worker's ID is saved.
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
# A wrong command line: `stop: <why>` when there is one, then the usage on
# stderr, exit 64. The command's own exit code passes through.
set -euo pipefail

HOURS="${HANDOFF_MAC_HOURS:-4}"
MAC_MGMT_ADDR=127.0.0.1:47199
MACS="$HOME/.config/dispatch/cursor-macs.tsv"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../shared/gh.sh"
scratch="$(mktemp -d)"; tmps=(); trap 'rm -rf "$scratch" ${tmps[@]+"${tmps[@]}"}' EXIT
usage_text() { awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; }

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
  tmp=$(mktemp "$(dirname "$MACS")/.$(basename "$MACS").XXXXXX"); tmps+=("$tmp")
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
  [[ "${1:-}" == "--" && $# -gt 1 ]] || die_usage "usage: mac.sh $verb ... -- <command>"
}

# remote INSTANCE SCRIPT -> runs SCRIPT on the Mac, with no stdin
remote() { nsc ssh "$1" -T -- "$2" </dev/null; }

# remote_in INSTANCE SCRIPT -> the same, stdin passed through
remote_in() { nsc ssh "$1" -T -- "$2"; }

cmd_up() {
  local worker="${1:-}" repo="${2:-}" base="${3:-}" wid="${4:-}"
  local usage='usage: mac.sh rent <worker> <repo-url> <base> -- <command>'
  [[ -n "$worker" && -n "$repo" && -n "$base" ]] || die_usage "$usage"
  [[ "$worker" =~ ^[A-Za-z0-9-]+$ ]] || die_usage "$usage" "worker name: letters, digits, and - only"
  [[ -z "$wid" || "$wid" =~ ^[0-9a-f-]{36}$ ]] || die_usage "$usage" "worker id: a UUID"
  need_tools
  local dir cid id key token name state="" out err
  key="${CURSOR_API_KEY:-}"
  [[ -n "$key" ]] || die "CURSOR_API_KEY is not set"
  gh_out auth token || die "gh is not signed in ($err): run gh auth login"; token="$out"
  dir=$(mktemp -d "$scratch/create.XXXXXX"); cid="$dir/cid"
  nsc create </dev/null --machine_type mac/silicon:6x14 \
    --selectors macos.version=26.x,image.with=xcode-26 \
    --duration "${HOURS}h" --purpose "handoff $worker" \
    --cidfile "$cid" --wait_timeout 5m >"$dir/create.log" 2>&1 \
    || { tail -3 "$dir/create.log" >&2; die "nsc create failed"; }
  id=$(cat "$cid")
  [[ -n "$id" ]] || die "nsc create printed no instance id"
  # From here on, a failure must not leave a rented Mac behind.
  name="${repo##*/}"
  { printf 'export CURSOR_API_KEY=%q\n' "$key"; printf 'export GH_TOKEN=%q\n' "$token"; } \
    | remote_in "$id" 'umask 077; cat > ~/.ho-env' >/dev/null \
    || { cmd_down "$id" >/dev/null || true; die "could not send the keys to $id"; }
  # Cursor has no flag to pick the worker ID, so this writes Cursor's own state file, see #455
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
    (. ~/.ho-env; ~/.local/bin/agent worker --management-addr $MAC_MGMT_ADDR start --name $(printf %q "$worker") </dev/null >~/worker.log 2>&1 &)
    for i in \$(seq 1 45); do
      if curl -fsS -o /dev/null http://$MAC_MGMT_ADDR/readyz 2>/dev/null; then
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

# worker_state MAC -> "alive" or "dead"; stops when the check cannot run.
# nsc's own failure exits 1 as a failed remote command can, so the remote
# check prints a word, and only that word counts. A Mac Namespace no longer
# holds is dead: nsc prints "Failed: <id>: does not exist.".
worker_state() {
  local id="$1" out last
  if [[ "$id" == "-" ]]; then echo dead; return 0; fi
  need_tools
  out=$(remote "$id" "if curl -fsS -o /dev/null --max-time 10 http://$MAC_MGMT_ADDR/healthz; then echo alive; else c=\$?; if [ \$c -eq 7 ]; then echo dead; else echo \"curl exit \$c\"; fi; fi" 2>&1) || true
  last=$(awk 'NF { l = $0 } END { print l }' <<<"$out")
  case "$last" in alive|dead) echo "$last"; return 0 ;; esac
  if grep -q 'does not exist\.' <<<"$out"; then echo dead; return 0; fi
  die "could not check the worker on $id (${last:-no output}); no note sent and no Mac rented"
}

cmd_down() {
  local id="${1:-}" log why
  [[ -n "$id" && "$id" != "-" ]] || die "instance id required"
  need_tools
  # A Mac whose worker hangs must still be destroyed, so this step may fail.
  # The [a] keeps the pattern from matching this remote shell's own command line.
  remote "$id" 'pkill -f "[a]gent worker"; rm -f ~/.ho-env' >/dev/null 2>&1 || true
  log=$(mktemp "$scratch/destroy.XXXXXX")
  if nsc destroy "$id" --force </dev/null >"$log" 2>&1; then
    echo "destroyed $id"; return 0
  fi
  # Proven 2026-11-12: nsc destroy of an ID Namespace does not hold exits 1
  # with "Failed: <id>: does not exist.", so that Mac costs nothing.
  if grep -q 'does not exist\.' "$log"; then
    echo "already gone $id"; return 0
  fi
  why=$(grep -v -e '^info:' -e '^[[:space:]]*$' "$log" | head -1 || true)
  echo "stop: could not destroy $id${why:+ ($why)}. It still runs and costs money until you destroy it by hand: nsc destroy $id --force" >&2
  return 1
}

cmd_rent() {
  local worker="${1:-}" repo="${2:-}" base="${3:-}" up mac wid res agent
  verb=rent; shift 3 || true; after_dashes "$@"; shift
  key_check
  up=$(cmd_up "$worker" "$repo" "$base") || exit
  IFS=$'\t' read -r mac wid <<<"$up"
  if ! res=$("$@" </dev/null); then
    cmd_down "$mac" >/dev/null || die "no agent started, so no row names $mac"
    exit 1
  fi
  IFS=$'\t' read -r agent _ <<<"$res"
  row_set "$agent" "$worker" "$wid" "$repo" "$base" "$mac"
  printf '%s\n' "$res"
}

cmd_renew() {
  local agent="${1:-}" row w wid r b mac up new st
  verb=renew; shift || true; after_dashes "$@"; shift
  row=$(row_get "$agent")
  if [[ -z "$row" ]]; then "$@"; return; fi
  IFS=$'\t' read -r w wid r b mac <<<"$row"
  st=$(worker_state "$mac") || exit 1
  if [[ "$st" == alive ]]; then "$@"; return; fi
  key_check
  # Renting now would replace the only row that names the old Mac.
  if [[ "$mac" != "-" ]] && ! cmd_down "$mac" >/dev/null; then
    die "no note sent: $mac was not given back"
  fi
  up=$(cmd_up "$w" "$r" "$b" "$wid") || exit
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
  *) die_usage "$(usage_text)" ;;
esac
