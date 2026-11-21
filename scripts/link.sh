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
# harness, on that harness's backup model, written by scripts/agents.sh:
# ${CLAUDE_AGENTS_HOME:-$HOME/.claude/agents}/<agent>.md for Claude Code,
# ${CODEX_AGENTS_HOME:-$HOME/.codex/agents}/<agent>.toml for Codex, and
# ${ANTIGRAVITY_PLUGINS_HOME:-$HOME/.gemini/config/plugins}/skills/agents/<agent>.md
# in the "skills" Antigravity plugin, beside the plugin.json it writes when the
# repo has an agent, and the hooks.json that runs the subagent gate, whose
# subagent-gate key it owns. Only `.md` files in agents/ count, so a Codex openai.yaml
# stays out. Each file it writes starts with a mark that names its source; a file it wrote whose source is gone, and
# a link it made that now points to nothing, after a rename or delete, is
# removed. A name already taken by something else stays as it is.
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
# by a tab: `<state> <kind> <harness> <name> <path>`, the state `ok`,
# `missing`, or `stale`, the kind `skill`, `agent`, `manifest`, `gate`, or
# `plugins`, and the harness `shared` for the first skills folder. A target
# something else holds, and each file of an agent that agents.sh cannot
# render, adds, as a sixth field, the words its `skip:` line gives. Any other
# argument: the usage line on stderr, exit 2.
set -euo pipefail

status=0
case "$#:${1:-}" in
  0:) ;;
  1:--status) status=1 ;;
  *) echo "usage: link.sh [--status]" >&2; exit 2 ;;
esac

repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
git_dir="$(cd "$(git -C "$repo" rev-parse --path-format=absolute --git-dir)" && pwd -P)"
common_dir="$(cd "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)"
[ "$git_dir" = "$common_dir" ] || exit 0

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
[ "$status" = 1 ] || mkdir -p "$agents" "$claude" "$claude_agents" "$codex_agents" "$antigravity"

# record <state> <kind> <harness> <name> <path> [<why>]: one --status line.
record() { local IFS=$'\t'; printf '%s\n' "$*"; }

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

# link_state <folder> <name> <target>: set st to the state of the folder's link
# for the name, and why to what holds it when something else does.
link_state() {
  local l="$1/$2"; why=""
  if [ ! -e "$l" ] && [ ! -L "$l" ]; then st=missing
  elif [ ! -e "$l" ]; then st=stale; why="$l is a link to nothing, not made here"
  elif ! [ "$l" -ef "$3" ]; then st=stale; why="$l is not this repo's $2"
  else st=ok; fi
}

# link <folder> <name> <target>: make the folder's link for the name. Fails,
# saying why, when something else holds the name.
link() {
  link_state "$@"
  case "$st" in
    missing) ln -s "$3" "$1/$2"; printf 'linked %s\n' "$1/$2" ;;
    stale) printf 'skip: %s\n' "$why" >&2; return 1 ;;
  esac
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

# put_state <path> <temp>: set st to the state of the path against the temp
# file, and why to what holds it when something else does.
put_state() {
  why=""
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then st=missing
  elif [ -z "$(made_from "$1")" ]; then st=stale; why="$1 is not this repo's $(basename "$1")"
  elif cmp -s "$2" "$1"; then st=ok
  else st=stale; fi
}

# put <path> <temp>: move the temp file to the path when the path is free, or
# a file this script wrote, and the content differs. Says why and drops the
# temp when something else holds it.
put() {
  put_state "$1" "$2"
  if [ "$st" = ok ] || [ -n "$why" ]; then
    rm -f "$2"; [ -z "$why" ] || printf 'skip: %s\n' "$why" >&2; return 0
  fi
  mv "$2" "$1"; printf 'wrote %s\n' "$1"
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

# agent_path <harness> <name>: the harness's file for the agent.
agent_path() {
  case "$1" in
    claude) printf '%s/%s.md' "$claude_agents" "$2" ;;
    codex) printf '%s/%s.toml' "$codex_agents" "$2" ;;
    antigravity) printf '%s/skills/agents/%s.md' "$plugins" "$2" ;;
  esac
}

# form <harness> <path> <source file> <source path>: write <path> through put,
# from agents.sh's form of the source for <harness>. With --status, print its
# line instead; the temp file then sits outside the folder, which may not
# exist.
form() {
  local t
  if [ "$status" = 1 ]; then t="$(mktemp)"; else t="$(mktemp "$(dirname "$2")/.link.XXXXXX")"; fi
  if ! bash "$repo/scripts/agents.sh" render "$1" "$(mark "$4")" < "$3" > "$t" 2>/dev/null; then
    rm -f "$t"; return 0
  fi
  if [ "$status" = 1 ]; then
    put_state "$2" "$t"; rm -f "$t"
    record "$st" agent "$1" "$(basename "$3" .md)" "$2" ${why:+"$why"}
  else
    put "$2" "$t"
  fi
}

# manifest: write the "skills" plugin's plugin.json when it is missing, or
# with --status print its line. It is strict JSON with no mark, since agy
# warns that `plugin install` cannot read a comment, so this script owns it
# only when it holds exactly these words.
manifest() {
  local p="$plugins/skills/plugin.json" want t
  want='{
  "name": "skills",
  "description": "The skill agents of the skills repo, written by its scripts/link.sh."
}'
  why=""
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then st=missing
  elif [ "$(cat "$p")" != "$want" ]; then st=stale; why="$p is not this repo's plugin.json"
  else st=ok; fi
  if [ "$status" = 1 ]; then
    record "$st" manifest antigravity plugin.json "$p" ${why:+"$why"}
  elif [ "$st" = missing ]; then
    t="$(mktemp "$plugins/skills/.link.XXXXXX")"; printf '%s\n' "$want" > "$t"
    mv "$t" "$p"; printf 'wrote %s\n' "$p"
  elif [ -n "$why" ]; then
    printf 'skip: %s\n' "$why" >&2
  fi
}

# merge_json <file> <jq filter> <entry json>: run the filter, with the entry
# as $e, on a JSON file this script shares with its owner, a missing file being
# {}. Sets st and why as link_state does. Writes the file only when the result
# differs and --status is off, and leaves a file jq cannot read. A link is
# written through to its target, so a settings file kept in a dotfiles folder
# stays linked.
merge_json() {
  local f="$1" old new t; why=""
  if [ -L "$f" ] && t="$(realpath "$f" 2>/dev/null)"; then f="$t"; fi
  if [ -e "$f" ]; then
    old="$(jq . "$f" 2>/dev/null)" || {
      st=stale; why="$f is not JSON"; [ "$status" = 1 ] || printf 'skip: %s\n' "$why" >&2; return 0; }
  else
    old='{}'
  fi
  new="$(jq --argjson e "$3" "$2" <<<"$old")"
  if [ "$(jq -S . <<<"$old")" = "$(jq -S . <<<"$new")" ]; then st=ok; return 0; fi
  if [ -e "$f" ]; then st=stale; else st=missing; fi
  [ "$status" = 0 ] || return 0
  mkdir -p "$(dirname "$f")"
  t="$(mktemp "$(dirname "$f")/.link.XXXXXX")"; printf '%s\n' "$new" > "$t"
  mv "$t" "$f"; printf 'wrote %s\n' "$f"
}

# gate_entry <harness>: the gate's PreToolUse group for the harness.
gate_entry() {
  jq -cn --arg m "$(bash "$gate" "$1" matcher)" --arg c "bash '$gate' $1" \
    '{matcher: $m, hooks: [{type: "command", command: $c, timeout: 5}]}'
}

# hook_entry <file> <harness>: put the gate's PreToolUse entry in the file. The
# first group that runs only the gate is replaced in its place, since Codex
# keys its trust on the group's index, and any later one is removed; with
# none, the entry goes last. A group that runs the gate beside other hooks
# loses only the gate's command.
hook_entry() {
  merge_json "$1" '
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

# plugin_hooks: put the gate's entry in the "skills" plugin's hooks.json,
# under its own subagent-gate key, so every other key stays.
plugin_hooks() {
  merge_json "$plugins/skills/hooks.json" '.["subagent-gate"] = {PreToolUse: [$e]}' "$(gate_entry antigravity)"
}

if [ "$status" = 0 ]; then
  unlink_dead "$agents" "$repo/skills"
  unlink_dead "$claude" "$agents" "../../.agents/skills"
  unlink_dead "$antigravity" "$agents"
fi

for f in "$repo"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  n="$(basename "$(dirname "$f")")"
  if [ "$status" = 1 ]; then
    link_state "$agents" "$n" "$repo/skills/$n"; shared="$st"
    record "$st" skill shared "$n" "$agents/$n" ${why:+"$why"}
    for h in claude antigravity; do
      if [ "$h" = claude ]; then d="$claude"; else d="$antigravity"; fi
      link_state "$d" "$n" "$agents/$n"
      # A link to a shared link that is not this repo's reaches no skill.
      if [ "$st" = ok ] && [ "$shared" != ok ]; then st=stale; why=""; fi
      record "$st" skill "$h" "$n" "$d/$n" ${why:+"$why"}
    done
  elif link "$agents" "$n" "$repo/skills/$n"; then
    link "$claude" "$n" "$agents/$n" || true
    link "$antigravity" "$n" "$agents/$n" || true
  fi
done

for f in "$repo"/skills/*/agents/*.md "$repo"/shared/agents/*.md; do
  [ -f "$f" ] || continue
  src="${f#"$repo"/}"; n="$(basename "$f" .md)"
  if ! why="$(bash "$repo/scripts/agents.sh" render claude "" < "$f" 2>&1 >/dev/null)"; then
    if [ "$status" = 0 ]; then printf 'skip: %s: %s\n' "$src" "$why" >&2; continue; fi
    for h in claude codex antigravity; do
      p="$(agent_path "$h" "$n")"
      if [ -e "$p" ] || [ -L "$p" ]; then st=stale; else st=missing; fi
      record "$st" agent "$h" "$n" "$p" "$src: $why"
    done
    continue
  fi
  form claude "$(agent_path claude "$n")" "$f" "$src"
  form codex "$(agent_path codex "$n")" "$f" "$src"
  [ "$status" = 1 ] || mkdir -p "$plugins/skills/agents"
  form antigravity "$(agent_path antigravity "$n")" "$f" "$src"
  any=1
done
if [ "$status" = 0 ]; then
  sweep "$claude_agents" '*.md'
  sweep "$codex_agents" '*.toml'
  sweep "$plugins/skills/agents" '*.md'
fi
[ -z "${any:-}" ] || manifest
if [ -f "$gate" ]; then
  hook_entry "$claude_settings" claude
  [ "$status" = 0 ] || record "$st" gate claude subagent-gate "$claude_settings" ${why:+"$why"}
  hook_entry "$codex_hooks" codex
  [ "$status" = 0 ] || record "$st" gate codex subagent-gate "$codex_hooks" ${why:+"$why"}
  if [ -n "${any:-}" ]; then
    plugin_hooks
    [ "$status" = 0 ] || record "$st" gate antigravity subagent-gate "$plugins/skills/hooks.json" ${why:+"$why"}
  fi
fi

# T3 runs Antigravity with a private home, so its chats see no plugin until
# each private folder's config/plugins points at the real one.
found=0
for d in "$t3"/*/; do
  [ -d "$d" ] || continue
  found=1; d="${d%/}"
  if [ "$status" = 1 ]; then
    link_state "$d/config" plugins "$plugins"
    record "$st" plugins antigravity plugins "$d/config/plugins" ${why:+"$why"}
    continue
  fi
  mkdir -p "$plugins" "$d/config"
  link "$d/config" plugins "$plugins" || true
done
[ "$found" = 1 ] || [ "$status" = 1 ] || printf 'skip: no T3 Antigravity folder in %s\n' "$t3" >&2
exit 0
