#!/usr/bin/env bash
# adopt.sh: move a skill from the local skills folder into the repo.
#
#   adopt.sh <name>
#
# The local skills folder is ${SKILLS_HOME:-$HOME/.agents/skills}. The skill
# folder moves to skills/<name>/ in this repo, a link takes its old place,
# and check.sh runs on the moved folder.
#
# Exit 0: `adopted <name>`, then the check's `check: clean`.
# Exit 1: `stop: <why>` on stderr and nothing changed; or the check found a
# leak in the moved folder, which stays moved so it can be fixed before the
# commit (the pre-commit hook blocks the commit until then).
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: adopt.sh <name>"
name="$1"
[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "not a skill name: $name"
home="${SKILLS_HOME:-$HOME/.agents/skills}"
repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)" || die "adopt.sh is not inside a git repo"

[ ! -L "$home/$name" ] || die "$home/$name is already a link"
[ -d "$home/$name" ] || die "no skill named $name in $home"
[ ! -e "$repo/skills/$name" ] || die "skills/$name already exists in the repo"

mkdir -p "$repo/skills"
mv "$home/$name" "$repo/skills/$name"
ln -s "$repo/skills/$name" "$home/$name"
echo "adopted $name"

cd "$repo"
exec bash scripts/check.sh "skills/$name"
