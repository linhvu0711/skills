# sync-repos.sh: the cases for embed-source's templates/sync-repos.sh. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The sync script a project copies, and the manifest template it starts from.
ES_SYNC="$here/../templates/sync-repos.sh"
ES_SYNC_MANIFEST="$here/../templates/repos-readme.md"

# es_remote: a git repo at $T/zod, the library's remote, with package.json
# at 3.1.0 tagged v3.1.0, then at 3.2.0 tagged v3.2.0. A local path, so no
# case needs the network.
es_remote() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  local r="$T/zod"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email "t""@""example.invalid"; git -C "$r" config user.name t
  git -C "$r" config commit.gpgsign false
  printf '{"version":"3.1.0"}\n' > "$r/package.json"
  git -C "$r" add package.json; git -C "$r" commit -qm 3.1.0; git -C "$r" tag v3.1.0
  printf '{"version":"3.2.0"}\n' > "$r/package.json"
  git -C "$r" commit -qam 3.2.0; git -C "$r" tag v3.2.0
}

# es_sync_project [<ref>]: a project in $T/proj with the sync script in its
# scripts/ folder and a manifest row for zod at <ref>, v3.1.0 when not given.
es_sync_project() {
  P="$T/proj"
  mkdir -p "$P/scripts" "$P/repos"
  cp "$ES_SYNC" "$P/scripts/sync-repos.sh"
  es_row "${1:-v3.1.0}"
}

# es_row <ref>: the manifest's zod row, at <ref>.
es_row() {
  cp "$ES_SYNC_MANIFEST" "$P/repos/README.md"
  printf '| zod | zod | %s | %s | package.json |\n' "$T/zod" "$1" >> "$P/repos/README.md"
}

t_es_sync_fetches_missing() {
  # Given: no checkout of zod
  es_remote; es_sync_project
  # When
  run bash "$P/scripts/sync-repos.sh"
  # Then
  eq exit 0 "$code"
  eq "stdout line 1" "sync-repos: fetching zod at v3.1.0" "$(printf '%s\n' "$out" | sed -n 1p)"
  eq marker "v3.1.0" "$(cat "$P/repos/zod/.embed-source-ref")"
  has package.json '"3.1.0"' "$(cat "$P/repos/zod/package.json")"
  [ ! -e "$P/repos/zod/.git" ] || eq ".git" "gone" "still there"
}

t_es_sync_moved_ref() {
  # Given: zod fetched at v3.1.0, then the manifest row moved to v3.2.0
  es_remote; es_sync_project
  bash "$P/scripts/sync-repos.sh" >/dev/null
  es_row v3.2.0
  # When
  run bash "$P/scripts/sync-repos.sh"
  # Then
  eq "stdout line 1" "sync-repos: fetching zod at v3.2.0" "$(printf '%s\n' "$out" | sed -n 1p)"
  eq marker "v3.2.0" "$(cat "$P/repos/zod/.embed-source-ref")"
  has package.json '"3.2.0"' "$(cat "$P/repos/zod/package.json")"
}

t_es_sync_keeps_unmarked() {
  # Given: a zod folder made by hand, with no marker
  es_remote; es_sync_project
  mkdir -p "$P/repos/zod"; touch "$P/repos/zod/own"
  # When
  run bash "$P/scripts/sync-repos.sh"
  # Then
  eq stdout "sync-repos: repos/zod exists without a marker; remove it by hand if you want it refetched" "$out"
  [ -e "$P/repos/zod/own" ] || eq own "still there" "gone"
  [ ! -e "$P/repos/zod/.embed-source-ref" ] || eq marker "none" "written"
}

cases=(
  "embed-source sync: a missing checkout is fetched at its ref|t_es_sync_fetches_missing"
  "embed-source sync: a moved ref is fetched again|t_es_sync_moved_ref"
  "embed-source sync: a checkout with no marker is kept|t_es_sync_keeps_unmarked"
)
