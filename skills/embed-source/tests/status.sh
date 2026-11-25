# status.sh: the cases for embed-source's scripts/status.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The status script, the sync script that defines the manifest format, and
# the manifest template a project starts from.
ES_STATUS="$here/../scripts/status.sh"
ES_FORMAT="$here/../templates/sync-repos.sh"
ES_MANIFEST="$here/../templates/repos-readme.md"

# es_fake_node: a node first on PATH that answers the two `node -p` forms
# status.sh runs: `require('./<file>').version`, and the dependency lookup
# of a package.json. CI has no node to rely on, so jq reads the files.
es_fake_node() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/bin"
  cat > "$T/bin/node" <<'EOF'
#!/usr/bin/env bash
expr="$2"
file="$(printf '%s' "$expr" | sed -E "s/.*require\('\.\/([^']+)'\).*/\1/")"
case "$expr" in
  *dependencies*)
    pkg="$(printf '%s' "$expr" | sed -E "s/.*dependencies\|\|\{\}\)\['([^']+)'\].*/\1/")"
    jq -r --arg p "$pkg" '(.dependencies[$p] // .devDependencies[$p] // "absent") | sub("^[\\^~]"; "")' "$file" ;;
  *) jq -r '.version' "$file" ;;
esac
EOF
  chmod +x "$T/bin/node"
  export PATH="$T/bin:$PATH"
}

# es_project [<ref>]: a project in $T/proj where zod 3.1.0 is embedded,
# installed, and named in the README section. The manifest row's ref is
# <ref>, v3.1.0 when not given.
es_project() {
  P="$T/proj"
  mkdir -p "$P/repos/zod" "$P/node_modules/zod"
  cp "$ES_MANIFEST" "$P/repos/README.md"
  printf '| zod | zod | https://github.com/colinhacks/zod.git | %s | package.json |\n' "${1:-v3.1.0}" >> "$P/repos/README.md"
  printf '{"version":"3.1.0"}\n' > "$P/repos/zod/package.json"
  printf 'v3.1.0\n' > "$P/repos/zod/.embed-source-ref"
  printf '{"version":"3.1.0"}\n' > "$P/node_modules/zod/package.json"
  printf '<!-- embed-source:start -->\n| zod | 3.1.0 | x |\n<!-- embed-source:end -->\n' > "$P/README.md"
}

t_es_status_up_to_date() {
  # Given: zod embedded, installed, and in the README at 3.1.0, marker at v3.1.0
  es_fake_node; es_project
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=no" "$out"
}

t_es_status_version_bump() {
  # Given: the installed zod moved to 3.2.0
  es_fake_node; es_project
  printf '{"version":"3.2.0"}\n' > "$P/node_modules/zod/package.json"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.2.0 ref=v3.1.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_moved_ref() {
  # Given: the manifest row's ref moved to v3.2.0, the marker still at v3.1.0
  es_fake_node; es_project v3.2.0
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=stale embedded=3.1.0 installed=3.1.0 ref=v3.2.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_missing_marker() {
  # Given: the checkout has no marker
  es_fake_node; es_project
  rm "$P/repos/zod/.embed-source-ref"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=no embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_missing_checkout() {
  # Given: no checkout of zod at all
  es_fake_node; es_project
  rm -rf "$P/repos/zod"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=no embedded=missing installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_reads_defined_marker() {
  # Given: a copy of the skill whose sync script names the marker .other-ref,
  # and an up-to-date project whose marker has that name
  es_fake_node; es_project
  mv "$P/repos/zod/.embed-source-ref" "$P/repos/zod/.other-ref"
  mkdir -p "$T/skill/scripts" "$T/skill/templates"
  cp "$ES_STATUS" "$T/skill/scripts/status.sh"
  sed 's/^EMBED_MARKER=.*/EMBED_MARKER=".other-ref"/' "$ES_FORMAT" > "$T/skill/templates/sync-repos.sh"
  # When
  run bash "$T/skill/scripts/status.sh" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=no" "$out"
}

cases=(
  "embed-source status: up to date says drift=no|t_es_status_up_to_date"
  "embed-source status: a version bump says drift=yes|t_es_status_version_bump"
  "embed-source status: a moved ref says synced=stale|t_es_status_moved_ref"
  "embed-source status: a missing marker says synced=no|t_es_status_missing_marker"
  "embed-source status: a missing checkout says embedded=missing|t_es_status_missing_checkout"
  "embed-source status: reads the marker name the sync script defines|t_es_status_reads_defined_marker"
)
