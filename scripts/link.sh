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
# folder. Each skill agent, skills/<name>/agents/<agent>.md, becomes a file per
# harness, on that harness's backup model, written by scripts/agents.sh:
# ${CLAUDE_AGENTS_HOME:-$HOME/.claude/agents}/<agent>.md for Claude Code, and
# ${CODEX_AGENTS_HOME:-$HOME/.codex/agents}/<agent>.toml for Codex. Only `.md`
# files in agents/ count, so a Codex openai.yaml stays out. Each file it writes starts
# with a mark that names its source; a file it wrote whose source is gone, and
# a link it made that now points to nothing, after a rename or delete, is
# removed. A name already taken by something else stays as it is.
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

for f in "$repo"/skills/*/agents/*.md; do
  [ -f "$f" ] || continue
  src="${f#"$repo"/}"; n="$(basename "$f" .md)"
  if ! why="$(bash "$repo/scripts/agents.sh" render claude "" < "$f" 2>&1 >/dev/null)"; then
    printf 'skip: %s: %s\n' "$src" "$why" >&2; continue
  fi
  form claude "$claude_agents/$n.md" "$f" "$src"
  form codex "$codex_agents/$n.toml" "$f" "$src"
done
sweep "$claude_agents" '*.md'
sweep "$codex_agents" '*.toml'

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
