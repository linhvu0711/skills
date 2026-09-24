#!/usr/bin/env bash
# Report every embedded library: synced ref, embedded version, installed version, idiom-file
# and README versions, drift. Truth comes from the manifest, the .embed-source-ref marker,
# the embedded package.json, the installed package.json, and file headers.
# Usage: status.sh [repo-root]
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"
MANIFEST="repos/README.md"

if [[ ! -f "$MANIFEST" ]]; then
  echo "none: no $MANIFEST found (nothing embedded yet)"
  exit 0
fi

# Manifest rows: | lib | package | repo | ref | version_file |
grep -E '^\| *[A-Za-z0-9@/._-]+ *\|' "$MANIFEST" \
  | grep -vE '^\| *lib *\|' \
  | grep -vE '^\| *-+ *\|' \
  | while IFS='|' read -r _ lib package repo ref vfile _; do
    lib="$(echo "$lib" | xargs)"; package="$(echo "$package" | xargs)"
    repo="$(echo "$repo" | xargs)"; ref="$(echo "$ref" | xargs)"; vfile="$(echo "$vfile" | xargs)"
    prefix="repos/$lib"

    synced="no"
    if [[ -f "$prefix/.embed-source-ref" ]]; then
      synced="yes"
      [[ "$(cat "$prefix/.embed-source-ref")" == "$ref" ]] || synced="stale"
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
