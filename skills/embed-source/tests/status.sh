# status.sh: the cases for embed-source's scripts/status.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The status script, the sync script that defines the manifest format, and
# the manifest template a project starts from.
ES_STATUS="$here/../scripts/status.sh"
ES_FORMAT="$here/../templates/sync-repos.sh"
ES_MANIFEST="$here/../templates/repos-readme.md"

# es_project [<ref>]: a project in $T/proj where zod 3.1.0 is embedded,
# installed, and named in the README section. The manifest row's ref is
# <ref>, v3.1.0 when not given.
es_project() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
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
  es_project
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=no" "$out"
}

t_es_status_version_bump() {
  # Given: the installed zod moved to 3.2.0
  es_project
  printf '{"version":"3.2.0"}\n' > "$P/node_modules/zod/package.json"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.2.0 ref=v3.1.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_moved_ref() {
  # Given: the manifest row's ref moved to v3.2.0, the marker still at v3.1.0
  es_project v3.2.0
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=stale embedded=3.1.0 installed=3.1.0 ref=v3.2.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_missing_marker() {
  # Given: the checkout has no marker
  es_project
  rm "$P/repos/zod/.embed-source-ref"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=no embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_missing_checkout() {
  # Given: no checkout of zod at all
  es_project
  rm -rf "$P/repos/zod"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=no embedded=missing installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=yes" "$out"
}

t_es_status_reads_defined_marker() {
  # Given: a copy of the skill whose sync script names the marker .other-ref,
  # and an up-to-date project whose marker has that name
  es_project
  mv "$P/repos/zod/.embed-source-ref" "$P/repos/zod/.other-ref"
  mkdir -p "$T/skill/scripts" "$T/skill/templates"
  cp "$ES_STATUS" "$T/skill/scripts/status.sh"
  sed 's/^EMBED_MARKER=.*/EMBED_MARKER=".other-ref"/' "$ES_FORMAT" > "$T/skill/templates/sync-repos.sh"
  # When
  run bash "$T/skill/scripts/status.sh" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=no" "$out"
}

t_es_status_package_json() {
  # Given: zod not in node_modules, a package.json that asks for ^3.10.2,
  # and a node on PATH that fails, so only jq can read it
  es_project
  rm -rf "$P/node_modules"
  printf '{"dependencies":{"zod":"^3.10.2"}}\n' > "$P/package.json"
  mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 1\n' > "$T/bin/node"; chmod +x "$T/bin/node"
  export PATH="$T/bin:$PATH"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  has stdout "installed=3.10.2 " "$out"
}

t_es_status_no_jq() {
  # Given: zod embedded and installed, and a PATH with no jq on it
  es_project
  mkdir -p "$T/nobin"
  # When
  run env PATH="$T/nobin" "$BASH" "$ES_STATUS" "$P"
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "stop: jq is not installed: status.sh reads package.json versions with it" "$err"
}

t_es_status_idiom_no_header() {
  # Given: zod up to date, and an idiom file with no version header
  es_project
  mkdir -p "$P/docs/idioms"
  printf '# no header\n' > "$P/docs/idioms/zod-a.md"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=yes
  patterns: docs/idioms/zod-a.md:none " "$out"
}

t_es_status_stale_idiom() {
  # Given: zod up to date, one idiom file at 3.1.0 and one still at 3.0.0
  es_project
  mkdir -p "$P/docs/idioms"
  printf '<!-- embed-source: zod@3.1.0 -->\n' > "$P/docs/idioms/zod-a.md"
  printf '<!-- embed-source: zod@3.0.0 -->\n' > "$P/docs/idioms/zod-b.md"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=yes
  patterns: docs/idioms/zod-a.md:3.1.0 docs/idioms/zod-b.md:3.0.0 " "$out"
}

t_es_status_current_idiom() {
  # Given: zod up to date, and one idiom file at 3.1.0
  es_project
  mkdir -p "$P/docs/idioms"
  printf '<!-- embed-source: zod@3.1.0 -->\n' > "$P/docs/idioms/zod-a.md"
  # When
  run bash "$ES_STATUS" "$P"
  # Then
  eq stdout "lib=zod prefix=repos/zod synced=yes embedded=3.1.0 installed=3.1.0 ref=v3.1.0 readme=3.1.0 drift=no
  patterns: docs/idioms/zod-a.md:3.1.0 " "$out"
}

cases=(
  "embed-source status: stops when jq is missing|t_es_status_no_jq"
  "embed-source status: reads a dependency's version from package.json|t_es_status_package_json"
  "embed-source status: up to date says drift=no|t_es_status_up_to_date"
  "embed-source status: a version bump says drift=yes|t_es_status_version_bump"
  "embed-source status: a moved ref says synced=stale|t_es_status_moved_ref"
  "embed-source status: a missing marker says synced=no|t_es_status_missing_marker"
  "embed-source status: a missing checkout says embedded=missing|t_es_status_missing_checkout"
  "embed-source status: reads the marker name the sync script defines|t_es_status_reads_defined_marker"
  "embed-source status: an idiom file with no header says none and drift=yes|t_es_status_idiom_no_header"
  "embed-source status: a stale idiom file says drift=yes|t_es_status_stale_idiom"
  "embed-source status: a current idiom file says drift=no|t_es_status_current_idiom"
)
