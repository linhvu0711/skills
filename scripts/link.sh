#!/usr/bin/env bash
# link.sh: link every skill in this repo into the local skills folders, so a
# new or renamed skill works with no step by hand. The post-commit,
# post-checkout, post-merge, and post-rewrite hooks run it.
#
#   link.sh
#
# The folders are ${SKILLS_HOME:-$HOME/.agents/skills}, where each skill
# links to skills/<name>/ here, and ${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills},
# where each skill links to its link in the first folder. A link that one of
# these made and that now points to no folder, after a skill was renamed or
# deleted, is removed. A name already taken by something else stays as it is.
#
# Run in a linked worktree, it does nothing: the links point to the main
# checkout, as adopt.sh's do.
#
# Exit 0, with `linked <link>`, `unlinked <link>`, or `skip: <why>` per
# change and nothing when all links are good.
set -euo pipefail

repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
git_dir="$(cd "$(git -C "$repo" rev-parse --git-dir)" && pwd -P)"
common_dir="$(cd "$(git -C "$repo" rev-parse --git-common-dir)" && pwd -P)"
[ "$git_dir" = "$common_dir" ] || exit 0

agents="${SKILLS_HOME:-$HOME/.agents/skills}"
claude="${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}"
mkdir -p "$agents" "$claude"

# unlink_dead <folder> <target-prefix>...: remove each link in the folder that
# points to no file and whose target is one of the prefixes plus its name.
unlink_dead() {
  local dir="$1" l n p; shift
  for l in "$dir"/*; do
    [ -L "$l" ] && [ ! -e "$l" ] || continue
    n="$(basename "$l")"
    for p in "$@"; do
      if [ "$(readlink "$l")" = "$p/$n" ]; then
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
  elif [ "$(cd "$l" && pwd -P)" != "$(cd "$repo/skills/$2" && pwd -P)" ]; then
    printf 'skip: %s is not this repo'"'"'s %s\n' "$l" "$2" >&2; return 1
  fi
}

unlink_dead "$agents" "$repo/skills"
unlink_dead "$claude" "$agents" "../../.agents/skills"

for f in "$repo"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  n="$(basename "$(dirname "$f")")"
  link "$agents" "$n" "$repo/skills/$n" && link "$claude" "$n" "$agents/$n" || true
done
exit 0
