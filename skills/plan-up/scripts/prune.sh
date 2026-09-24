#!/usr/bin/env bash
# Delete plan files whose work is done.
#
#   prune.sh [-n]      -n: print what would go, delete nothing
#
# A slug goes when its `plan-<slug>.md` has a `Repo: owner/repo` line and
# every issue the slug names is closed: the number(s) in the slug, plus,
# for a `-run`, every `#N` in the `## Stack` table. Its `plan-<slug>.*`
# and `prompt-<slug>.*` files are deleted. A slug with no issue, an
# unknown repo, or a gh error stays. Files that belong to no plan are
# printed as `stray`, never deleted.

set -u
DIR="${PLAN_DIR:-$HOME/.agents/artifacts/plan}"
dry=0
[ "${1:-}" = "-n" ] && dry=1
[ -d "$DIR" ] || exit 0

cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT

# closed_file <owner/repo>: path of a file with the repo's closed issue
# numbers, one per line. Fails when gh cannot list them.
closed_file() {
  local f="$cache/${1//\//_}"
  [ -e "$f.err" ] && return 1
  if [ ! -e "$f" ]; then
    gh issue list -R "$1" --state closed -L 100000 --json number --jq '.[].number' >"$f" 2>/dev/null \
      || { rm -f "$f"; : >"$f.err"; return 1; }
  fi
  echo "$f"
}

pruned=0 kept=0
for md in "$DIR"/plan-*.md; do
  [ -e "$md" ] || continue
  slug=${md##*/plan-}
  slug=${slug%.md}

  repo=$(sed -n 's/^Repo:[[:space:]]*`*\([^`[:space:]]*\).*/\1/p' "$md" | head -1)
  tail=${slug#"${repo/\//-}-"}
  if [ -z "$repo" ] || [ "$tail" = "$slug" ] || ! [[ $tail =~ ^[0-9]+(-[0-9]+)*(-run)?$ ]]; then
    kept=$((kept + 1)); continue
  fi

  nums=$(echo "${tail%-run}" | tr '-' '\n')
  if [[ $tail == *-run ]]; then
    nums="$nums
$(sed -n '/^## Stack/,/^## [^S]/p' "$md" | grep -oE '^\| *[0-9]+ *\| *#[0-9]+' | grep -oE '[0-9]+$')"
  fi

  if ! f=$(closed_file "$repo"); then
    kept=$((kept + 1)); continue
  fi
  done_all=1
  for n in $nums; do
    grep -qx "$n" "$f" || { done_all=0; break; }
  done
  if [ "$done_all" = 0 ]; then
    kept=$((kept + 1)); continue
  fi

  echo "pruned $slug"
  [ "$dry" = 1 ] || rm -f "$DIR/plan-$slug".* "$DIR/prompt-$slug".*
  pruned=$((pruned + 1))
done

for f in "$DIR"/*; do
  [ -e "$f" ] || continue
  name=${f##*/}
  slug=$(echo "$name" | sed -nE 's/^(plan|prompt)-(.*)\.[a-z]+$/\2/p')
  [ -n "$slug" ] && [ -e "$DIR/plan-$slug.md" ] && continue
  echo "stray $name"
done

echo "pruned $pruned, kept $kept$([ "$dry" = 1 ] && echo ' (dry run)')"
