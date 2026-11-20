#!/usr/bin/env bash
# link.sh: link every skill and skill agent in this repo into the local
# folders, so a new or renamed one works with no step by hand. The
# post-commit, post-checkout, post-merge, and post-rewrite hooks run it.
#
#   link.sh
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
set -euo pipefail

repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
git_dir="$(cd "$(git -C "$repo" rev-parse --git-dir)" && pwd -P)"
common_dir="$(cd "$(git -C "$repo" rev-parse --git-common-dir)" && pwd -P)"
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
mkdir -p "$agents" "$claude" "$claude_agents" "$codex_agents" "$antigravity"

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

# link <folder> <name> <target>: make the folder's link for the name. Fails,
# saying why, when something else holds the name.
link() {
  local l="$1/$2"
  if [ ! -e "$l" ] && [ ! -L "$l" ]; then
    ln -s "$3" "$l"; printf 'linked %s\n' "$l"
  elif [ ! -e "$l" ]; then
    printf 'skip: %s is a link to nothing, not made here\n' "$l" >&2; return 1
  elif ! [ "$l" -ef "$3" ]; then
    printf 'skip: %s is not this repo'"'"'s %s\n' "$l" "$2" >&2; return 1
  fi
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

# put <path> <temp>: move the temp file to the path when the path is free, a
# file this script wrote, or one of its old links to an agent file, and the
# content differs. Says why and drops the temp when something else holds it.
put() {
  local p="$1" t="$2"
  if [ -L "$p" ] && [[ "$(readlink "$p")" == "$repo"/skills/*/agents/* ]]; then
    rm "$p"
  elif [ -e "$p" ] || [ -L "$p" ]; then
    if [ -z "$(made_from "$p")" ]; then
      rm -f "$t"; printf 'skip: %s is not this repo'"'"'s %s\n' "$p" "$(basename "$p")" >&2; return 0
    fi
    if cmp -s "$t" "$p"; then rm -f "$t"; return 0; fi
  fi
  mv "$t" "$p"; printf 'wrote %s\n' "$p"
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

# form <harness> <path> <source file> <source path>: write <path> through put,
# from agents.sh's form of the source for <harness>.
form() {
  local t; t="$(mktemp "$(dirname "$2")/.link.XXXXXX")"
  if bash "$repo/scripts/agents.sh" render "$1" "$(mark "$4")" < "$3" > "$t" 2>/dev/null; then
    put "$2" "$t"
  else
    rm -f "$t"
  fi
}

# manifest: write the "skills" plugin's plugin.json when it is missing. It is
# strict JSON with no mark, since agy warns that `plugin install` cannot read
# a comment, so this script owns it only when it holds exactly these words.
manifest() {
  local p="$plugins/skills/plugin.json" want t
  want='{
  "name": "skills",
  "description": "The skill agents of the skills repo, written by its scripts/link.sh."
}'
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then
    t="$(mktemp "$plugins/skills/.link.XXXXXX")"; printf '%s\n' "$want" > "$t"
    mv "$t" "$p"; printf 'wrote %s\n' "$p"
  elif [ "$(cat "$p")" != "$want" ]; then
    printf 'skip: %s is not this repo'"'"'s plugin.json\n' "$p" >&2
  fi
}

# merge_json <file> <jq filter> <entry json>: run the filter, with the entry
# as $e, on a JSON file this script shares with its owner, a missing file being
# {}. Writes the file only when the result differs, and leaves a file jq
# cannot read. A link is written through to its target, so a settings file
# kept in a dotfiles folder stays linked.
merge_json() {
  local f="$1" old new t
  if [ -L "$f" ] && t="$(realpath "$f" 2>/dev/null)"; then f="$t"; fi
  if [ -e "$f" ]; then
    old="$(jq . "$f" 2>/dev/null)" || { printf 'skip: %s is not JSON\n' "$f" >&2; return 0; }
  else
    old='{}'
  fi
  new="$(jq --argjson e "$3" "$2" <<<"$old")"
  [ "$(jq -S . <<<"$old")" != "$(jq -S . <<<"$new")" ] || return 0
  mkdir -p "$(dirname "$f")"
  t="$(mktemp "$(dirname "$f")/.link.XXXXXX")"; printf '%s\n' "$new" > "$t"
  mv "$t" "$f"; printf 'wrote %s\n' "$f"
}

# hook_entry <file> <harness>: put the gate's PreToolUse entry in the file. The
# first group that runs only the gate is replaced in its place, since Codex
# keys its trust on the group's index, and any later one is removed; with
# none, the entry goes last. A group that runs the gate beside other hooks
# loses only the gate's command.
hook_entry() {
  local entry
  entry="$(jq -cn --arg m "$(bash "$gate" "$2" matcher)" --arg c "bash '$gate' $2" \
    '{matcher: $m, hooks: [{type: "command", command: $c, timeout: 5}]}')"
  merge_json "$1" '
    def gate: (.command // "") | contains("shared/gate/subagent-gate.sh");
    def only_gate: (.hooks // []) | length > 0 and all(gate);
    (.hooks.PreToolUse // []) as $g
    | ([$g | to_entries[] | select(.value | only_gate) | .key] | first) as $i
    | .hooks.PreToolUse = [$g | to_entries[]
        | if .key == $i then $e
          elif (.value | only_gate) then empty
          elif any(.value.hooks[]?; gate) then .value | .hooks |= map(select(gate | not))
          else .value end] + (if $i == null then [$e] else [] end)' "$entry"
}

# plugin_hooks: put the gate's entry in the "skills" plugin's hooks.json,
# under its own subagent-gate key, so every other key stays.
plugin_hooks() {
  local entry
  entry="$(jq -cn --arg m "$(bash "$gate" antigravity matcher)" --arg c "bash '$gate' antigravity" \
    '{PreToolUse: [{matcher: $m, hooks: [{type: "command", command: $c, timeout: 5}]}]}')"
  merge_json "$plugins/skills/hooks.json" '.["subagent-gate"] = $e' "$entry"
}

unlink_dead "$agents" "$repo/skills"
unlink_dead "$claude" "$agents" "../../.agents/skills"
unlink_dead "$antigravity" "$agents"
unlink_dead "$claude_agents" "$repo/skills/*/agents"

for f in "$repo"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  n="$(basename "$(dirname "$f")")"
  if link "$agents" "$n" "$repo/skills/$n"; then
    link "$claude" "$n" "$agents/$n" || true
    link "$antigravity" "$n" "$agents/$n" || true
  fi
done

for f in "$repo"/skills/*/agents/*.md "$repo"/shared/agents/*.md; do
  [ -f "$f" ] || continue
  src="${f#"$repo"/}"; n="$(basename "$f" .md)"
  if ! why="$(bash "$repo/scripts/agents.sh" render claude "" < "$f" 2>&1 >/dev/null)"; then
    printf 'skip: %s: %s\n' "$src" "$why" >&2; continue
  fi
  form claude "$claude_agents/$n.md" "$f" "$src"
  form codex "$codex_agents/$n.toml" "$f" "$src"
  mkdir -p "$plugins/skills/agents"
  form antigravity "$plugins/skills/agents/$n.md" "$f" "$src"
  any=1
done
sweep "$claude_agents" '*.md'
sweep "$codex_agents" '*.toml'
sweep "$plugins/skills/agents" '*.md'
[ -z "${any:-}" ] || manifest
if [ -f "$gate" ]; then
  hook_entry "$claude_settings" claude
  hook_entry "$codex_hooks" codex
  [ -z "${any:-}" ] || plugin_hooks
fi

# T3 runs Antigravity with a private home, so its chats see no plugin until
# each private folder's config/plugins points at the real one.
found=0
for d in "$t3"/*/; do
  [ -d "$d" ] || continue
  found=1; d="${d%/}"
  mkdir -p "$plugins" "$d/config"
  link "$d/config" plugins "$plugins" || true
done
[ "$found" = 1 ] || printf 'skip: no T3 Antigravity folder in %s\n' "$t3" >&2
exit 0
