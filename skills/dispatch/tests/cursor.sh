# cursor.sh: the cases for this skill's Cursor adapter, driven through the fake
# curl of test-lib.sh. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# cursor <args>: run the Cursor adapter on the fake curl, with HOME in the
# temp folder (no .zshrc).
cursor() { run env HOME="$T/home" CURSOR_API_URL=https://cursor.test CURSOR_API_KEY=k bash "$here/../scripts/adapters/cursor.sh" "$@"; }

agent_bc1='{"id":"bc-1","status":"RUNNING","latestRunId":"run-2","url":"https://cursor.com/agents/bc-1"}'

t_cursor_start() {
  fake_curl
  printf '{"items":[{"url":"https://github.com/o/r"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '{"agent":{"id":"bc-1","url":"https://cursor.com/agents/bc-1"}}\n' > "$FAKE_CURL/POST_v1_agents.json"
  printf '# Brief\n' > p.md
  cursor start p.md --repo o/r --title "#12 Export"
  eq exit 0 "$code"
  eq stdout "bc-1	https://cursor.com/agents/bc-1" "$out"
}

t_cursor_poll() {
  fake_curl
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"FINISHED","result":"Opened the PR","git":{"branches":[{"prUrl":"https://github.com/o/r/pull/9"}]}}\n' \
    > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  cursor poll bc-1
  eq exit 0 "$code"
  eq stdout "finished	run-2|FINISHED	https://github.com/o/r/pull/9	https://cursor.com/agents/bc-1	Opened the PR" "$out"
}

t_cursor_say() {
  fake_curl
  printf '{"run":{"id":"run-3"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  printf '# Changed\n' > note.md
  cursor say bc-1 note.md
  eq exit 0 "$code"
  eq stdout "sent to bc-1 (run-3)" "$out"
}

# fake_mac: a fake mac.sh in $T, HANDOFF_MAC pointing there. It logs each
# call's args to $T/mac.calls.
# `rent <worker> <repo> <base> -- <command>` runs the command and prints its
# output; `renew <agent> -- <command>` runs the command, with MAC_NEW_BASE from
# $T/mac.new when that file exists.
# `return <agent> -- <command>` runs the command and prints
# `<agent>: destroyed mac-1` when it passes, `<agent>: mac-1 kept, its run has
# not ended` when it exits 1, and else fails as mac.sh does.
fake_mac() {
  cat > "$T/mac.sh" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
printf '%s\n' "$*" >> "$d/mac.calls"
case "$1" in
  rent) shift 5; "$@" ;;
  renew) shift 3
         if [ -f "$d/mac.new" ]; then MAC_NEW_BASE="$(cat "$d/mac.new")" "$@"; else "$@"; fi ;;
  return) a="$2"; shift 3; rc=0; "$@" || rc=$?
          case "$rc" in
            0) echo "$a: destroyed mac-1" ;;
            1) echo "$a: mac-1 kept, its run has not ended" ;;
            *) echo "stop: could not check the run of $a, so mac-1 is kept" >&2; exit 1 ;;
          esac ;;
esac
EOF
  export HANDOFF_MAC="$T/mac.sh"
}

# cursor_mac <args>: cursor with the fake mac.sh and a crsr_ key.
cursor_mac() { run env HOME="$T/home" CURSOR_API_URL=https://cursor.test CURSOR_API_KEY="${KEY:-crsr_k}" bash "$here/../scripts/adapters/cursor.sh" "$@"; }

macs() { cat "$T/home/.config/dispatch/cursor-macs.tsv"; }

t_cursor_start_macos() {
  fake_curl; fake_mac
  printf '{"items":[{"url":"https://github.com/o/r"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '{"agent":{"id":"bc-1","url":"https://cursor.com/agents/bc-1"}}\n' > "$FAKE_CURL/POST_v1_agents.json"
  printf '# Brief\n' > p.md
  cursor_mac start p.md --repo o/r --base dev --platform macos
  eq exit 0 "$code"
  eq stdout "bc-1	https://cursor.com/agents/bc-1" "$out"
  w=$(jq -r .env.name "$FAKE_CURL/POST_v1_agents.data")
  eq env "machine" "$(jq -r .env.type "$FAKE_CURL/POST_v1_agents.data")"
  has "mac rent" "rent $w https://github.com/o/r dev -- bash " "$(cat "$T/mac.calls")"
}

t_cursor_poll_leaves_mac() {
  # Given: an agent on mac-1 whose run ended
  fake_curl; fake_mac
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\tmac-1\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"FINISHED","result":"Done"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  # When
  cursor_mac poll bc-1
  # Then
  eq exit 0 "$code"
  eq stdout "finished	run-2|FINISHED	-	https://cursor.com/agents/bc-1	Done" "$out"
  [ ! -f "$T/mac.calls" ] || eq "mac calls" "" "$(cat "$T/mac.calls")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_cursor_release_check_fails() {
  # Given: the run cannot be read
  fake_curl; fake_mac
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"detail":"bad gateway"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  printf 502 > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.code"
  # When
  cursor_mac release bc-1
  # Then
  eq exit 1 "$code"
  eq stdout "" "$out"
  has stderr "HTTP 502 on GET /agents/bc-1/runs/run-2" "$err"
  has stderr "stop: could not check the run of bc-1, so mac-1 is kept" "$err"
}

t_cursor_release() {
  # Given
  fake_curl; fake_mac
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"FINISHED","result":"Done"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  # When
  cursor_mac release bc-1
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1: destroyed mac-1" "$out"
  has "mac call" "return bc-1 -- bash " "$(cat "$T/mac.calls")"
}

t_cursor_say_through_renew() {
  # Given
  fake_curl; fake_mac
  printf '{"run":{"id":"run-3"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  printf '# Changed\n' > note.md
  # When
  cursor_mac say bc-1 note.md
  # Then
  eq exit 0 "$code"
  eq stdout "sent to bc-1 (run-3)" "$out"
  has "mac renew" "renew bc-1 -- bash " "$(cat "$T/mac.calls")"
  eq note "# Changed" "$(jq -r .prompt.text "$FAKE_CURL/POST_v1_agents_bc-1_runs.data")"
}

cases=(
  "cursor say sends through mac.sh renew|t_cursor_say_through_renew"
  "cursor release hands the run check to mac.sh return|t_cursor_release"
  "cursor release fails when the run cannot be read|t_cursor_release_check_fails"
  "cursor start sends the prompt and prints the agent|t_cursor_start"
  "cursor poll reads the latest run|t_cursor_poll"
  "cursor say starts a new run|t_cursor_say"
  "cursor start on macos rents a Mac and targets its worker|t_cursor_start_macos"
  "cursor poll leaves the Mac when the run ended|t_cursor_poll_leaves_mac"
)
