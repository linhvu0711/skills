#!/usr/bin/env bash
# Fetch every library listed in repos/README.md into repos/<lib> at its pinned tag.
# Safe to run twice: a folder already at the right tag is left alone.
# When the repo cannot be reached, as without network, it warns and exits 0;
# a missing tag or any other failure stops it.
# Set EMBED_SOURCE_SKIP=1 to skip (for example in CI that only lints and tests).
#
# This file also defines the manifest and the marker for the skill's status
# check, which sources it; a source runs only the definitions.

EMBED_MANIFEST="repos/README.md"
EMBED_MARKER=".embed-source-ref"

# embed_rows: one line per lib row of the manifest, its cells trimmed and
# joined by |, as lib|package|repo|ref|version_file. Run from the project root.
embed_rows() {
  grep -E '^\| *[A-Za-z0-9@/._-]+ *\|' "$EMBED_MANIFEST" \
    | grep -vE '^\| *lib *\|' \
    | grep -vE '^\| *-+ *\|' \
    | while IFS='|' read -r _ lib package repo ref vfile _; do
      printf '%s|%s|%s|%s|%s\n' "$(echo "$lib" | xargs)" "$(echo "$package" | xargs)" \
        "$(echo "$repo" | xargs)" "$(echo "$ref" | xargs)" "$(echo "$vfile" | xargs)"
    done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
tmps=(); trap 'rm -rf ${tmps[@]+"${tmps[@]}"}' EXIT

if [[ "${EMBED_SOURCE_SKIP:-}" == "1" ]]; then
  echo "sync-repos: skipped (EMBED_SOURCE_SKIP=1)"
  exit 0
fi
[[ -f "$EMBED_MANIFEST" ]] || { echo "sync-repos: no $EMBED_MANIFEST, nothing to fetch"; exit 0; }

while IFS='|' read -r lib _package repo ref _vfile; do
    dir="repos/$lib"
    marker="$dir/$EMBED_MARKER"

    if [[ "$ref" == *"{version}"* ]]; then
      echo "sync-repos: $lib has an unresolved ref '$ref' in $EMBED_MANIFEST, skipping"
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

    mkdir -p "$(dirname "$dir")"
    tmp="$(mktemp -d "$dir.XXXXXX")"; tmps+=("$tmp")
    echo "sync-repos: fetching $lib at $ref"
    if git clone --quiet --depth 1 --single-branch --branch "$ref" "$repo" "$tmp" 2>/dev/null; then
      rm -rf "$tmp/.git" "$dir"
      mv "$tmp" "$dir"
      printf '%s\n' "$ref" > "$marker"
      echo "sync-repos: $lib ready ($(du -sh "$dir" | cut -f1))"
    else
      # Only a repo that cannot be reached is the expected failure: ls-remote
      # exits 128 then, and 2 when the repo answers but lacks the tag.
      reach=0; git ls-remote --exit-code "$repo" "$ref" >/dev/null 2>&1 || reach=$?
      if [ "$reach" -ne 128 ]; then
        echo "stop: could not fetch $lib at $ref, though $repo answers; check the tag in $EMBED_MANIFEST" >&2
        exit 1
      fi
      if [[ -d "$dir" ]]; then
        echo "sync-repos: could not fetch $lib at $ref (offline?), keeping the current copy"
      else
        echo "sync-repos: could not fetch $lib at $ref (offline?), run scripts/sync-repos.sh later"
      fi
    fi
  done < <(embed_rows)
exit 0
