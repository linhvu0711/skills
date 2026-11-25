#!/usr/bin/env bash
# Report every embedded library: synced ref, embedded version, installed version, idiom-file
# and README versions, drift. Truth comes from the manifest, the marker,
# the embedded package.json, the installed package.json, and file headers.
# Usage: status.sh [repo-root]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# The sync script owns the manifest format, so the two never disagree.
. "$here/../templates/sync-repos.sh"

ROOT="${1:-.}"
cd "$ROOT"

if [[ ! -f "$EMBED_MANIFEST" ]]; then
  echo "none: no $EMBED_MANIFEST found (nothing embedded yet)"
  exit 0
fi

embed_rows | while IFS='|' read -r lib package _repo ref vfile; do
    prefix="repos/$lib"

    synced="no"
    if [[ -f "$prefix/$EMBED_MARKER" ]]; then
      synced="yes"
      [[ "$(cat "$prefix/$EMBED_MARKER")" == "$ref" ]] || synced="stale"
    fi

    embedded="missing"
    [[ -f "$prefix/$vfile" ]] && embedded="$(node -p "require('./$prefix/$vfile').version" 2>/dev/null || echo unknown)"

    # Installed: root node_modules, then the pnpm store and workspace node_modules, then manifests.
    installed="absent"
    for pj in node_modules/"$package"/package.json \
              node_modules/.pnpm/"${package//\//+}"@*/node_modules/"$package"/package.json \
              packages/*/node_modules/"$package"/package.json apps/*/node_modules/"$package"/package.json; do
      [[ -f "$pj" ]] || continue
      installed="$(node -p "require('./$pj').version" 2>/dev/null || echo unknown)"; break
    done
    if [[ "$installed" == "absent" ]]; then
      for pj in package.json packages/*/package.json apps/*/package.json; do
        [[ -f "$pj" ]] || continue
        v="$(node -p "(p=>((p.dependencies||{})['$package']||(p.devDependencies||{})['$package']||'absent').replace(/^[\^~]/,''))(require('./$pj'))" 2>/dev/null || echo unknown)"
        [[ "$v" != "absent" ]] && { installed="$v"; break; }
      done
    fi

    patterns=""
    for f in docs/idioms/"$lib"-*.md; do
      [[ -f "$f" ]] || continue
      v="$(grep -oE 'embed-source: *[^ ]+@[0-9][^ >]*' "$f" | head -1 | sed -E 's/.*@//')"
      patterns+="${f}:${v:-none} "
    done

    readme="none"
    if [[ -f README.md ]]; then
      readme="$(sed -n '/embed-source:start/,/embed-source:end/p' README.md | grep -oE "^\| *$lib *\| *[0-9][^ |]*" | sed -E 's/.*\| *//' | head -1)"
      readme="${readme:-missing}"
    fi

    drift="no"
    [[ "$synced" != "yes" ]] && drift="yes"
    [[ "$embedded" != "$installed" ]] && drift="yes"
    [[ "$readme" != "$embedded" ]] && drift="yes"
    echo "$patterns" | grep -qE ":[^ ]+" && echo "$patterns" | tr ' ' '\n' | grep -v '^$' | grep -vq ":$embedded\$" && drift="yes"

    echo "lib=$lib prefix=$prefix synced=$synced embedded=$embedded installed=$installed ref=${ref//\{version\}/$installed} readme=$readme drift=$drift"
    [[ -n "$patterns" ]] && echo "  patterns: $patterns"
  done
