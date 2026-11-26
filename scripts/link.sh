#!/usr/bin/env bash
# link.sh: link every skill and skill agent in this repo into the local
# folders, so a new or renamed one works with no step by hand. The
# post-commit, post-checkout, post-merge, and post-rewrite hooks run it.
#
#   link.sh
#   link.sh --status
#
# The folders are ${SKILLS_HOME:-$HOME/.agents/skills}, where each skill
# links to skills/<name>/ here, ${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}
# and ${ANTIGRAVITY_SKILLS_HOME:-$HOME/.gemini/config/skills}, Antigravity's
# global skills folder, where each skill links to its link in the first
# folder. Each skill agent, skills/<name>/agents/<agent>.md, and each shared
# agent, the explorer and the runner in shared/agents/<agent>.md, becomes a file per
# harness, on the last try of its try list for that harness, written by
# scripts/agents.sh:
# ${CLAUDE_AGENTS_HOME:-$HOME/.claude/agents}/<agent>.md for Claude Code and
# ${CODEX_AGENTS_HOME:-$HOME/.codex/agents}/<agent>.toml for Codex. Antigravity
# gets no agent file: it runs only inside T3, which starts each helper on its
# try list. Only `.md` files in agents/ count, so a Codex openai.yaml
# stays out. Each file it writes starts with a mark that names its source; a file it wrote whose source is gone, and
# a link it made that now points to nothing, after a rename or delete, is
# removed. A name already taken by something else stays as it is.
#
# An earlier version wrote a "skills" Antigravity plugin in
# ${ANTIGRAVITY_PLUGINS_HOME:-$HOME/.gemini/config/plugins}/skills/. Its agent
# files with the mark, its plugin.json with the words it wrote, and the
# subagent-gate key of its hooks.json are removed; a file or key of the
# user's own there stays.
#
# It also wires the subagent gate, shared/gate/subagent-gate.sh: one
# PreToolUse entry in ${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json} and
# one in ${CODEX_HOOKS_FILE:-$HOME/.codex/hooks.json}. It replaces only an entry
# that runs that script, in its place, and leaves every other key and hook. A
# file it cannot read as JSON stays as it is, with a skip: line.
#
# Each folder under ${T3_ANTIGRAVITY_HOME:-$HOME/.t3/userdata/providers/antigravity},
# a private Antigravity home T3 Code keeps, gets config/plugins, a link to
# ${ANTIGRAVITY_PLUGINS_HOME:-$HOME/.gemini/config/plugins}, made when missing,
# so a chat T3 starts sees the same plugins as a terminal chat.
#
# Run in a linked worktree, it does nothing: the links point to the main
# checkout, as adopt.sh's do.
#
# Exit 0, with `linked <link>`, `unlinked <link>`, `wrote <file>`,
# `removed <file>`, or `skip: <why>` per change and nothing when all are good.
# With no T3 Antigravity folder, `skip: no T3 Antigravity folder in <folder>`
# on every run.
#
# --status writes nothing and prints one line per target, its fields joined
# by a tab: `<state> <kind> <harness> <name> <path> <folder>`, the state `ok`,
# `missing`, or `stale`, the kind `skill`, `agent`, `gate`, or `plugins`, the
# harness `shared` for the first skills folder, and the folder the setting
# names for it: a skills or agents folder, a hook file's folder, or a T3
# Antigravity folder. A target something else
# holds, and each file of an agent that agents.sh cannot render, adds, as a
# seventh field, the words its `skip:` line gives. Any other argument: the
# usage line on stderr, exit 64.
set -euo pipefail

die_usage() { local u="$1"; shift; [ $# -eq 0 ] || printf 'stop: %s\n' "$*" >&2; printf '%s\n' "$u" >&2; exit 64; }
die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

case "$#:${1:-}" in
  0:) visit=fix ;;
  1:--status) visit=record ;;
  *) die_usage 'usage: link.sh [--status]' ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(git -C "$here/.." rev-parse --show-toplevel)"
git_dir="$(cd "$(git -C "$repo" rev-parse --path-format=absolute --git-dir)" && pwd -P)"
common_dir="$(cd "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)"
[ "$git_dir" = "$common_dir" ] || exit 0
command -v jq >/dev/null || die "link.sh needs jq to read and write hook files; install it, as with brew install jq"

agents="${SKILLS_HOME:-$HOME/.agents/skills}"
claude="${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}"
claude_agents="${CLAUDE_AGENTS_HOME:-$HOME/.claude/agents}"
codex_agents="${CODEX_AGENTS_HOME:-$HOME/.codex/agents}"
antigravity="${ANTIGRAVITY_SKILLS_HOME:-$HOME/.gemini/config/skills}"
plugins="${ANTIGRAVITY_PLUGINS_HOME:-$HOME/.gemini/config/plugins}"
t3="${T3_ANTIGRAVITY_HOME:-$HOME/.t3/userdata/providers/antigravity}"
claude_settings="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
codex_hooks="${CODEX_HOOKS_FILE:-$HOME/.codex/hooks.json}"
gate="$repo/shared/gate/subagent-gate.sh"
scratch="$(mktemp -d)"; tmps=(); trap 'rm -rf "$scratch" ${tmps[@]+"${tmps[@]}"}' EXIT

# unlink_dead <folder> <target-prefix>...: remove each link in the folder that
# points to no file and whose target is one of the prefixes plus its name. A
# prefix is a pattern, so `*` stands for a skill folder a rename removed.
unlink_dead() {
  local dir="$1" l n p; shift
  for l in "$dir"/*; do
    [ -L "$l" ] && [ ! -e "$l" ] || continue
    n="$(basename "$l")"
    for p in "$@"; do
      # shellcheck disable=SC2053
      if [[ "$(readlink "$l")" == $p/"$n" ]]; then
        rm "$l"; printf 'unlinked %s\n' "$l"; break
      fi
    done
  done
}

# link_state <folder> <name> <target> [<own>]: set st to the state of the
# folder's link for the name, and why to what holds it when something else
# does. <own> is one more target that unlink_dead takes as this script's.
link_state() {
  local l="$1/$2" t; why=""
  if [ ! -e "$l" ] && [ ! -L "$l" ]; then st=missing
  elif [ ! -e "$l" ]; then
    st=stale; t="$(readlink "$l")"
    if [ "$t" != "$3" ] && [ "$t" != "${4-$3}" ]; then why="$l is a link to nothing, not made here"; fi
  elif ! [ "$l" -ef "$3" ]; then st=stale; why="$l is not this repo's $2"
  else st=ok; fi
}

# mark <source>: the words that mark a file as one this script wrote from
# <source>, a path in the repo.
mark() { printf 'Made by scripts/link.sh from %s. Edit that file, not this one.' "$1"; }

# made_from <path>: the source a file this script wrote names in its mark, or
# nothing for any other file or link.
made_from() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  head -n 2 "$1" | sed -n 's/^# Made by scripts\/link\.sh from \(.*\)\. Edit that file, not this one\.$/\1/p'
}

# put_state <path> <want>: set st to the state of the path against the file it
# should match, and why to what holds it when something else does.
put_state() {
  why=""
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then st=missing
  elif [ -z "$(made_from "$1")" ]; then st=stale; why="$1 is not this repo's $(basename "$1")"
  elif cmp -s "$2" "$1"; then st=ok
  else st=stale; fi
}

# sweep <folder> <glob>: remove each file there that this script wrote from a
# source the repo no longer has.
sweep() {
  local f s
  for f in "$1"/$2; do
    s="$(made_from "$f")"
    [ -n "$s" ] && [ ! -e "$repo/$s" ] || continue
    rm "$f"; printf 'removed %s\n' "$f"
  done
}

# drop_old_plugin: remove the "skills" Antigravity plugin an earlier version
# wrote: each agent file with this script's mark, the plugin.json that holds
# exactly the words it wrote, which has no mark since it is strict JSON, and
# the subagent-gate key of its hooks.json, the file too when no other key is
# left. A file or key of the user's own stays.
drop_old_plugin() {
  local d="$plugins/skills" f t
  for f in "$d"/agents/*.md; do
    [ -n "$(made_from "$f")" ] || continue
    rm "$f"; printf 'removed %s\n' "$f"
  done
  f="$d/plugin.json"
  if [ -f "$f" ] && [ ! -L "$f" ] && [ "$(cat "$f")" = '{
  "name": "skills",
  "description": "The skill agents of the skills repo, written by its scripts/link.sh."
}' ]; then
    rm "$f"; printf 'removed %s\n' "$f"
  fi
  f="$d/hooks.json"
  if [ -f "$f" ] && [ ! -L "$f" ] && jq -e 'has("subagent-gate")' "$f" >/dev/null 2>&1; then
    if jq -e 'keys == ["subagent-gate"]' "$f" >/dev/null; then
      rm "$f"; printf 'removed %s\n' "$f"
    else
      t="$(mktemp "$d/.hooks.json.XXXXXX")"; tmps+=("$t")
      jq 'del(.["subagent-gate"])' "$f" > "$t"; mv "$t" "$f"; printf 'wrote %s\n' "$f"
    fi
  fi
  rmdir "$d/agents" "$d" 2>/dev/null || true
}

# agent_folder <harness>: the folder the harness's agent files sit in.
agent_folder() {
  case "$1" in
    claude) printf '%s' "$claude_agents" ;;
    codex) printf '%s' "$codex_agents" ;;
  esac
}

# agent_path <harness> <name>: the harness's file for the agent.
agent_path() {
  case "$1" in
    claude) printf '%s/%s.md' "$claude_agents" "$2" ;;
    codex) printf '%s/%s.toml' "$codex_agents" "$2" ;;
  esac
}

# json_state <file> <jq filter> <entry json>: set st and why as link_state
# does for a JSON file this script shares with its owner, and write to want
# the file after the filter runs on it, with the entry as $e, a missing file
# being {}. A link is read through to its target, so a settings file kept in a
# dotfiles folder stays linked when fix writes it.
json_state() {
  local f="$1" old t; why=""
  if [ -L "$f" ] && t="$(realpath "$f" 2>/dev/null)"; then f="$t"; fi
  if [ -e "$f" ]; then
    old="$(jq . "$f" 2>/dev/null)" || { st=stale; why="$f is not JSON"; return 0; }
  else
    old='{}'
  fi
  jq --argjson e "$3" "$2" <<<"$old" > "$want"
  if [ "$(jq -S . <<<"$old")" = "$(jq -S . "$want")" ]; then st=ok
  elif [ -e "$f" ]; then st=stale
  else st=missing; fi
}

# gate_entry <harness>: the gate's PreToolUse group for the harness.
gate_entry() {
  jq -cn --arg m "$(bash "$gate" "$1" matcher)" --arg c "bash '$gate' $1" \
    '{matcher: $m, hooks: [{type: "command", command: $c, timeout: 5}]}'
}

# hook_state <file> <harness>: json_state for the gate's PreToolUse entry in
# the file. The first group that runs only the gate is replaced in its place,
# since Codex keys its trust on the group's index, and any later one is
# removed; with none, the entry goes last. A group that runs the gate beside
# other hooks loses only the gate's command.
hook_state() {
  json_state "$1" '
    def gate: (.command // "") | contains("shared/gate/subagent-gate.sh");
    def only_gate: (.hooks // []) | length > 0 and all(gate);
    (.hooks.PreToolUse // []) as $g
    | ([$g | to_entries[] | select(.value | only_gate) | .key] | first) as $i
    | .hooks.PreToolUse = [$g | to_entries[]
        | if .key == $i then $e
          elif (.value | only_gate) then empty
          elif any(.value.hooks[]?; gate) then .value | .hooks |= map(select(gate | not))
          else .value end] + (if $i == null then [$e] else [] end)' "$(gate_entry "$2")"
}

# each_target <visit>: work out the state of every target, in order, and call
# <visit> on each with st, kind, h, name, path, folder, and why set, and want:
# the link's target for a skill or plugins target, else a scratch file that
# holds what the target should hold. folder is the one the setting names for
# the target, so a reader finds it without cutting the path.
each_target() {
  local f n src err shared d own
  kind=skill
  for f in "$repo"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    n="$(basename "$(dirname "$f")")"; name="$n"
    h=shared; path="$agents/$n"; folder="$agents"; want="$repo/skills/$n"
    link_state "$agents" "$n" "$want"; shared="$st"; "$1"
    for h in claude antigravity; do
      if [ "$h" = claude ]; then d="$claude"; own="../../.agents/skills/$n"; else d="$antigravity"; own="$agents/$n"; fi
      path="$d/$n"; folder="$d"; want="$agents/$n"
      link_state "$d" "$n" "$want" "$own"
      # A link to a shared link that is not this repo's reaches no skill. It
      # keeps its own why, so a folder of the user's own here is named too.
      if [ "$shared" = stale ]; then st=stale; fi
      "$1"
    done
  done

  kind=agent
  for f in "$repo"/skills/*/agents/*.md "$repo"/shared/agents/*.md; do
    [ -f "$f" ] || continue
    src="${f#"$repo"/}"; name="$(basename "$f" .md)"
    # Each harness renders on its own try list, so one may fail while the
    # other renders.
    for h in claude codex; do
      path="$(agent_path "$h" "$name")"; folder="$(agent_folder "$h")"; want="$scratch/$h-$name"
      if err="$(bash "$repo/scripts/agents.sh" render "$h" "$(mark "$src")" < "$f" 2>&1 >"$want")"; then
        put_state "$path" "$want"
      else
        want=""; why="$src:$err"
        if [ -e "$path" ] || [ -L "$path" ]; then st=stale; else st=missing; fi
      fi
      "$1"
    done
  done

  if [ -f "$gate" ]; then
    kind=gate; name=subagent-gate
    h=claude; path="$claude_settings"; folder="$(dirname "$path")"; want="$scratch/claude-hooks.json"; hook_state "$path" claude; "$1"
    h=codex; path="$codex_hooks"; folder="$(dirname "$path")"; want="$scratch/codex-hooks.json"; hook_state "$path" codex; "$1"
  fi

  # T3 runs Antigravity with a private home, so its chats see no plugin until
  # each private folder's config/plugins points at the real one.
  kind=plugins; h=antigravity; name=plugins; want="$plugins"
  for d in "$t3"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; path="$d/config/plugins"; folder="$d"
    link_state "$d/config" plugins "$plugins"; "$1"
  done
}

# record: the --status line of the target the pass is on.
record() {
  local IFS=$'\t'
  set -- "$st" "$kind" "$h" "$name" "$path" "$folder"
  [ -z "$why" ] || set -- "$@" "$why"
  printf '%s\n' "$*"
}

# fix: make the target the pass is on hold what the repo wants, or say on
# stderr what holds it. An agent agents.sh cannot render gives one why for
# each harness, so a why just said is not said again.
said=""
fix() {
  local to t
  [ "$st" != ok ] || return 0
  if [ -n "$why" ]; then
    [ "$why" = "$said" ] || printf 'skip: %s\n' "$why" >&2
    said="$why"; return 0
  fi
  case "$kind" in
    skill|plugins)
      [ "$st" = missing ] || return 0
      mkdir -p "$(dirname "$path")"; ln -s "$want" "$path"; printf 'linked %s\n' "$path" ;;
    *)
      to="$path"
      if [ -L "$to" ] && t="$(realpath "$to" 2>/dev/null)"; then to="$t"; fi
      mkdir -p "$(dirname "$to")"
      t="$(mktemp "$(dirname "$to")/.$(basename "$to").XXXXXX")"; tmps+=("$t"); cat "$want" > "$t"
      mv "$t" "$to"; printf 'wrote %s\n' "$to" ;;
  esac
}

if [ "$visit" = fix ]; then
  mkdir -p "$agents" "$claude" "$claude_agents" "$codex_agents" "$antigravity" "$plugins"
  unlink_dead "$agents" "$repo/skills"
  unlink_dead "$claude" "$agents" "../../.agents/skills"
  unlink_dead "$antigravity" "$agents"
  sweep "$claude_agents" '*.md'
  sweep "$codex_agents" '*.toml'
  drop_old_plugin
fi
each_target "$visit"
if [ "$visit" = fix ]; then
  found=0
  for d in "$t3"/*/; do if [ -d "$d" ]; then found=1; fi; done
  [ "$found" = 1 ] || printf 'skip: no T3 Antigravity folder in %s\n' "$t3" >&2
fi
exit 0
