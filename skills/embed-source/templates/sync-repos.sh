#!/usr/bin/env bash
# Fetch every library listed in repos/README.md into repos/<lib> at its pinned tag.
# Safe to run twice: a folder already at the right tag is left alone.
# Never fails the install: without network it warns and exits 0.
# Set EMBED_SOURCE_SKIP=1 to skip (for example in CI that only lints and tests).
set -uo pipefail

cd "$(dirname "$0")/.."
MANIFEST="repos/README.md"

if [[ "${EMBED_SOURCE_SKIP:-}" == "1" ]]; then
  echo "sync-repos: skipped (EMBED_SOURCE_SKIP=1)"
  exit 0
fi
[[ -f "$MANIFEST" ]] || { echo "sync-repos: no $MANIFEST, nothing to fetch"; exit 0; }

grep -E '^\| *[A-Za-z0-9@/._-]+ *\|' "$MANIFEST" \
  | grep -vE '^\| *lib *\|' \
  | grep -vE '^\| *-+ *\|' \
  | while IFS='|' read -r _ lib _package repo ref _vfile _; do
    lib="$(echo "$lib" | xargs)"; repo="$(echo "$repo" | xargs)"; ref="$(echo "$ref" | xargs)"
    dir="repos/$lib"
    marker="$dir/.embed-source-ref"

    if [[ "$ref" == *"{version}"* ]]; then
      echo "sync-repos: $lib has an unresolved ref '$ref' in $MANIFEST, skipping"
      continue
    fi
    if [[ -f "$marker" && "$(cat "$marker")" == "$ref" ]]; then
      echo "sync-repos: $lib already at $ref"
      continue
    fi
    if [[ -d "$dir" && ! -f "$marker" ]]; then
      echo "sync-repos: $dir exists without a marker; remove it by hand if you want it refetched"
      continue
    fi

    tmp="$dir.tmp.$$"
    rm -rf "$tmp"
    echo "sync-repos: fetching $lib at $ref"
    if git clone --quiet --depth 1 --single-branch --branch "$ref" "$repo" "$tmp" 2>/dev/null; then
      rm -rf "$tmp/.git" "$dir"
      mv "$tmp" "$dir"
      printf '%s\n' "$ref" > "$marker"
      echo "sync-repos: $lib ready ($(du -sh "$dir" | cut -f1))"
    else
      rm -rf "$tmp"
      if [[ -d "$dir" ]]; then
        echo "sync-repos: could not fetch $lib at $ref (offline?), keeping the current copy"
      else
        echo "sync-repos: could not fetch $lib at $ref (offline?), run scripts/sync-repos.sh later"
      fi
    fi
  done
exit 0
