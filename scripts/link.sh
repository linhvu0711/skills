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
# folder, and ${CLAUDE_AGENTS_HOME:-$HOME/.claude/agents}, where each skill agent
# skills/<name>/agents/<agent>.md links to its file here. Only `.md` files in
# agents/ link, so a Codex openai.yaml stays out. A link that one of these made
# and that now points to nothing, after a rename or delete, is removed. A name
# already taken by something else stays as it is.
#
# Each folder under ${T3_ANTIGRAVITY_HOME:-$HOME/.t3/userdata/providers/antigravity},
# a private Antigravity home T3 Code keeps, gets config/plugins, a link to
# ${ANTIGRAVITY_PLUGINS_HOME:-$HOME/.gemini/config/plugins}, made when missing,
# so a chat T3 starts sees the same plugins as a terminal chat.
#
# Run in a linked worktree, it does nothing: the links point to the main
# checkout, as adopt.sh's do.
#
# Exit 0, with `linked <link>`, `unlinked <link>`, or `skip: <why>` per
# change and nothing when all links are good. With no T3 Antigravity folder,
# `skip: no T3 Antigravity folder in <folder>` on every run.
set -euo pipefail

repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
git_dir="$(cd "$(git -C "$repo" rev-parse --git-dir)" && pwd -P)"
common_dir="$(cd "$(git -C "$repo" rev-parse --git-common-dir)" && pwd -P)"
[ "$git_dir" = "$common_dir" ] || exit 0

agents="${SKILLS_HOME:-$HOME/.agents/skills}"
claude="${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}"
claude_agents="${CLAUDE_AGENTS_HOME:-$HOME/.claude/agents}"
antigravity="${ANTIGRAVITY_SKILLS_HOME:-$HOME/.gemini/config/skills}"
plugins="${ANTIGRAVITY_PLUGINS_HOME:-$HOME/.gemini/config/plugins}"
t3="${T3_ANTIGRAVITY_HOME:-$HOME/.t3/userdata/providers/antigravity}"
mkdir -p "$agents" "$claude" "$claude_agents" "$antigravity"

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
  link "$claude_agents" "$(basename "$f")" "$f" || true
done

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
