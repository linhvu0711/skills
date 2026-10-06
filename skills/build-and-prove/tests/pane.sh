# pane.sh: the cases for this skill's pane script, driven through a fake
# herdr and a fake claude. The repo's test.sh sources this file
# after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_herdr: a repo at R, a prompt file at $T/p.md, and a fake herdr and a
# fake claude first on PATH. herdr logs each call as one line in
# $T/herdr.log and answers one workspace with one tab t1 that holds one pane
# p1; a split makes pane p2, and an agent is working once prompted. claude
# answers `auth status` with $T/auth.json, signed in unless a case writes it
# again. Inside herdr, as workspace w1, tab t1.
fake_herdr() {
  repo
  mkdir -p "$T/bin"
  printf '# Task\n' > "$T/p.md"
  cat > "$T/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"p1","tab_id":"t1"}]}}' ;;
  "tab list") echo '{"result":{"tabs":[{"tab_id":"t1"}]}}' ;;
  "pane layout") echo '{"result":{"layout":{"panes":[{"pane_id":"p1","rect":{"x":0}}]}}}' ;;
  "pane split") echo '{"result":{"pane":{"pane_id":"p2"}}}' ;;
  "agent get") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "pane rename"|"pane resize"|"agent start"|"agent prompt") echo '{}' ;;
  *) printf 'fake herdr: no route for %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "auth status" ] && cat "$FAKE_AUTH"
EOF
  chmod +x "$T/bin/herdr" "$T/bin/claude"
  echo '{"loggedIn": true}' > "$T/auth.json"
  export PATH="$T/bin:$PATH" FAKE_AUTH="$T/auth.json" FAKE_HERDR_LOG="$T/herdr.log"
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

t_pane_starts_claude() {
  fake_herdr
  pane
  eq code 0 "$code"
  eq start "agent start export-orders --kind claude --pane p2 --timeout 90000 -- --model sonnet --effort high --permission-mode auto" \
    "$(grep '^agent start' "$T/herdr.log")"
}

t_pane_sends_prompt() {
  fake_herdr
  pane
  eq code 0 "$code"
  eq prompt "agent prompt export-orders Read $T/p.md whole and follow it. It is your task and your rules. Work in $R." \
    "$(grep '^agent prompt' "$T/herdr.log")"
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
  "starts claude on sonnet at high effort in the new pane|t_pane_starts_claude"
  "sends the prompt file to the new pane|t_pane_sends_prompt"
  "stops when claude is missing|t_pane_no_claude"
  "stops when claude is not logged in|t_pane_not_logged_in"
)
