# pane.sh: the cases for this skill's pane script, driven through a fake
# herdr and a fake claude in --dry-run. The repo's test.sh sources this file
# after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_herdr: a repo at R, a prompt file at $T/p.md, and a fake herdr and a
# fake claude first on PATH. herdr answers one workspace with one tab t1 that
# holds one pane p1. claude answers `auth status` with $T/auth.json, signed in
# unless a case writes it again. Inside herdr, as workspace w1, tab t1.
fake_herdr() {
  repo
  mkdir -p "$T/bin"
  printf '# Task\n' > "$T/p.md"
  cat > "$T/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"p1","tab_id":"t1"}]}}' ;;
  "tab list") echo '{"result":{"tabs":[{"tab_id":"t1"}]}}' ;;
  "pane layout") echo '{"result":{"layout":{"panes":[{"pane_id":"p1","rect":{"x":0}}]}}}' ;;
  *) printf 'fake herdr: no route for %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "auth status" ] && cat "$FAKE_AUTH"
EOF
  chmod +x "$T/bin/herdr" "$T/bin/claude"
  echo '{"loggedIn": true}' > "$T/auth.json"
  export PATH="$T/bin:$PATH" FAKE_AUTH="$T/auth.json"
  export HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=t1
}

pane() { run bash "$here/../scripts/pane.sh" "$R" export-orders "$T/p.md" "$@"; }

t_pane_dry_run() {
  fake_herdr
  pane --dry-run
  eq code 0 "$code"
  has out "claude sonnet high auto" "$out"
  has out "split p1 in t1" "$out"
}

t_pane_flags() {
  fake_herdr
  pane --model opus --effort max --mode bypassPermissions --dry-run
  eq code 0 "$code"
  has out "claude opus max bypassPermissions" "$out"
}

t_pane_no_claude() {
  fake_herdr
  rm "$T/bin/claude"
  ln -s "$(command -v jq)" "$T/bin/jq"
  ln -s "$(command -v git)" "$T/bin/git"
  PATH="$T/bin:/usr/bin:/bin"
  pane --dry-run
  eq code 1 "$code"
  eq err "stop: claude CLI not on PATH" "$(tail -1 <<<"$err")"
}

t_pane_not_logged_in() {
  fake_herdr
  echo '{"loggedIn": false}' > "$T/auth.json"
  pane --dry-run
  eq code 1 "$code"
  eq err "stop: claude CLI is not logged in; run: claude auth login" "$(tail -1 <<<"$err")"
}

cases=(
  "dry run starts claude on sonnet at high effort|t_pane_dry_run"
  "flags change model, effort, and mode|t_pane_flags"
  "stops when claude is missing|t_pane_no_claude"
  "stops when claude is not logged in|t_pane_not_logged_in"
)
