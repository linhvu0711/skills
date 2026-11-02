# cursor.sh: the cases for the shared Cursor client, shared/cursor/cursor.sh,
# driven through the fake curl of test-lib.sh. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# cursor <args>: run the Cursor client on the fake curl, with HOME in the
# temp folder (no .zshrc).
cursor() { run env HOME="$T/home" CURSOR_API_URL=https://cursor.test CURSOR_API_KEY=k bash "$here/../cursor/cursor.sh" "$@"; }

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

t_cursor_repo_not_connected() {
  fake_curl
  printf '{"items":[{"url":"https://github.com/o/other"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '# Brief\n' > p.md
  cursor start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "cursor.sh: Connect o/r to Cursor first: cursor.com/dashboard, Integrations, GitHub." "$err"
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

t_cursor_poll_github_pr() {
  fake_curl; fake_gh
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"RUNNING","git":{"branches":[]}}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  printf '[{"url":"https://github.com/o/r/pull/13","headRefName":"feat/12-export"},{"url":"https://github.com/o/r/pull/14","headRefName":"fix/120-other"}]\n' \
    > "$FAKE_GH/pr-list..json"
  cursor poll bc-1 --repo o/r --issue 12
  eq exit 0 "$code"
  eq stdout "working	run-2|RUNNING	https://github.com/o/r/pull/13	https://cursor.com/agents/bc-1	-" "$out"
}

t_cursor_say() {
  fake_curl
  printf '{"run":{"id":"run-3"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  printf '# Changed\n' > note.md
  cursor say bc-1 note.md
  eq exit 0 "$code"
  eq stdout "sent to bc-1 (run-3)" "$out"
}

t_cursor_no_key() {
  fake_curl
  printf '# Brief\n' > p.md
  run env -u CURSOR_API_KEY HOME="$T/home" bash "$here/../cursor/cursor.sh" start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "cursor.sh: no CURSOR_API_KEY in ~/.zshrc or env (make one at cursor.com/dashboard, API Keys)" "$err"
}

# fake_mac: a fake mac.sh in $T, CURSOR_MAC pointing there. It logs each
# call's args to $T/mac.calls; `up` prints mac-<n> and wid-1, n its call count, and
# `alive` exits with the content of $T/mac.alive (1 when missing), and `down`
# runs $T/mac.on-down first when it exists.
fake_mac() {
  cat > "$T/mac.sh" <<'EOF'
#!/usr/bin/env bash
d="$(dirname "$0")"
printf '%s\n' "$*" >> "$d/mac.calls"
case "$1" in
  up) n=$(( $(cat "$d/mac.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/mac.n"; printf 'mac-%s\twid-1\n' "$n" ;;
  alive) exit "$(cat "$d/mac.alive" 2>/dev/null || echo 1)" ;;
  down) [ ! -f "$d/mac.on-down" ] || bash "$d/mac.on-down"; echo "destroyed $2" ;;
esac
EOF
  export CURSOR_MAC="$T/mac.sh"
}

# cursor_mac <args>: cursor with the fake mac.sh and a crsr_ key.
cursor_mac() { run env HOME="$T/home" CURSOR_API_URL=https://cursor.test CURSOR_API_KEY="${KEY:-crsr_k}" bash "$here/../cursor/cursor.sh" "$@"; }

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
  eq "mac up" "up $w https://github.com/o/r dev" "$(cat "$T/mac.calls")"
  eq row "bc-1	$w	wid-1	https://github.com/o/r	dev	mac-1" "$(macs)"
}

t_cursor_start_macos_timeout() {
  fake_curl; fake_mac
  printf '{"items":[{"url":"https://github.com/o/r"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  echo 28 > "$FAKE_CURL/POST_v1_agents.exit"
  printf '# Brief\n' > p.md
  # The worker name is random, so the list answers with every agent on a
  # machine and the adapter must pick the one on its own worker.
  cat > "$T/bin/od" <<'EOF'
#!/usr/bin/env bash
echo " ab cd ef 01"
EOF
  chmod +x "$T/bin/od"
  printf '{"items":[{"id":"bc-0","env":{"type":"machine","name":"ho-other"}},{"id":"bc-2","url":"https://cursor.com/agents/bc-2","env":{"type":"machine","name":"ho-abcdef01"}}]}\n' \
    > "$FAKE_CURL/GET_v1_agents.json"
  cursor_mac start p.md --repo o/r --platform macos
  eq exit 0 "$code"
  eq stdout "bc-2	https://cursor.com/agents/bc-2" "$out"
}

t_cursor_start_windows() {
  fake_curl; fake_mac
  printf '# Brief\n' > p.md
  cursor_mac start p.md --repo o/r --platform windows
  eq exit 1 "$code"
  eq stderr "cursor.sh: Cursor has no Windows machine: hand this one to devin" "$err"
}

t_cursor_start_macos_grok_key() {
  fake_curl; fake_mac
  printf '# Brief\n' > p.md
  KEY=grok_k cursor_mac start p.md --repo o/r --platform macos
  eq exit 1 "$code"
  eq stderr "cursor.sh: a Mac worker refuses grok_ keys: put a personal crsr_ key in CURSOR_API_KEY" "$err"
  [ ! -f "$T/mac.calls" ] || { echo "a Mac was rented" >&2; exit 1; }
}

t_cursor_poll_frees_mac() {
  fake_curl; fake_mac
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\tmac-1\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"FINISHED","result":"Done"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  cursor_mac poll bc-1
  eq exit 0 "$code"
  eq "mac down" "down mac-1" "$(cat "$T/mac.calls")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	-" "$(macs)"
}

t_cursor_say_new_mac() {
  fake_curl; fake_mac
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\t-\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '{"run":{"id":"run-3"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  printf '# Changed\n' > note.md
  cursor_mac say bc-1 note.md
  eq exit 0 "$code"
  eq stdout "sent to bc-1 (run-3)" "$out"
  eq "mac calls" "alive -
up ho-1 https://github.com/o/r main wid-1" "$(cat "$T/mac.calls")"
  has "note" "This run is on a new Mac" "$(jq -r .prompt.text "$FAKE_CURL/POST_v1_agents_bc-1_runs.data")"
  has "note" "# Changed" "$(jq -r .prompt.text "$FAKE_CURL/POST_v1_agents_bc-1_runs.data")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	mac-1" "$(macs)"
}

t_cursor_say_mac_alive() {
  fake_curl; fake_mac
  echo 0 > "$T/mac.alive"
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\tmac-1\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '{"run":{"id":"run-3"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  printf '# Changed\n' > note.md
  cursor_mac say bc-1 note.md
  eq exit 0 "$code"
  eq "mac calls" "alive mac-1" "$(cat "$T/mac.calls")"
  eq note "# Changed" "$(jq -r .prompt.text "$FAKE_CURL/POST_v1_agents_bc-1_runs.data")"
}

t_cursor_poll_keeps_newer_mac() {
  fake_curl; fake_mac
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\tmac-1\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"FINISHED","result":"Done"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  # A say rents mac-2 while this poll frees mac-1.
  printf "printf 'bc-1\\tho-1\\twid-1\\thttps://github.com/o/r\\tmain\\tmac-2\\n' > \"%s\"\n" \
    "$T/home/.config/dispatch/cursor-macs.tsv" > "$T/mac.on-down"
  cursor_mac poll bc-1
  eq exit 0 "$code"
  eq "mac down" "down mac-1" "$(cat "$T/mac.calls")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	mac-2" "$(macs)"
}

t_cursor_say_send_fails() {
  fake_curl; fake_mac
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\t-\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '{"error":{"code":"agent_busy"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  echo 409 > "$FAKE_CURL/POST_v1_agents_bc-1_runs.code"
  printf '# Changed\n' > note.md
  cursor_mac say bc-1 note.md
  eq exit 1 "$code"
  eq "mac calls" "alive -
up ho-1 https://github.com/o/r main wid-1
down mac-1" "$(cat "$T/mac.calls")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	-" "$(macs)"
}

t_cursor_artifacts() {
  fake_curl
  printf '{"items":[{"path":"artifacts/video-1.mp4","sizeBytes":2048,"updatedAt":"2026-11-02T10:00:00Z"},{"path":"artifacts/checks.txt","sizeBytes":120,"updatedAt":"2026-11-02T10:00:00Z"}]}\n' \
    > "$FAKE_CURL/GET_v1_agents_bc-1_artifacts.json"
  cursor artifacts bc-1
  eq exit 0 "$code"
  eq stdout "artifacts/video-1.mp4	2048
artifacts/checks.txt	120" "$out"
}

# download_fixtures: the presigned URL for artifacts/video-1.mp4, and the file behind it.
download_fixtures() {
  printf '{"url":"https://s3.test/b/video-1.mp4?sig=x","expiresAt":"2026-11-02T10:15:00Z"}\n' \
    > "$FAKE_CURL/GET_v1_agents_bc-1_artifacts_download.json"
  printf 'MP4DATA\n' > "$FAKE_CURL/GET_b_video-1.mp4.json"
}

t_cursor_download() {
  fake_curl; download_fixtures
  cursor download bc-1 artifacts/video-1.mp4 proof/video-1.mp4
  eq exit 0 "$code"
  eq stdout "saved proof/video-1.mp4" "$out"
  eq file "MP4DATA" "$(cat proof/video-1.mp4)"
  has calls "GET /b/video-1.mp4" "$(cat "$FAKE_CURL/calls")"
}

t_cursor_download_fails() {
  fake_curl; download_fixtures
  printf 403 > "$FAKE_CURL/GET_b_video-1.mp4.code"
  cursor download bc-1 artifacts/video-1.mp4 proof/video-1.mp4
  eq exit 1 "$code"
  eq stderr "cursor.sh: download of artifacts/video-1.mp4 failed: HTTP 403" "$err"
  [ ! -e proof/video-1.mp4 ] || eq file "none" "proof/video-1.mp4"
}

t_cursor_start_api_reason() {
  fake_curl
  printf '{"items":[{"url":"https://github.com/o/r"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '{"error":{"code":"payment_required","message":"Add credit to run agents"}}\n' > "$FAKE_CURL/POST_v1_agents.json"
  printf 402 > "$FAKE_CURL/POST_v1_agents.code"
  printf '# Brief\n' > p.md
  cursor start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "cursor.sh: HTTP 402 on POST /agents: payment_required (Add credit to run agents)" "$err"
}

t_cursor_handoff_adapter() {
  fake_curl
  printf '{"items":[{"path":"artifacts/checks.txt","sizeBytes":120}]}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_artifacts.json"
  run env HOME="$T/home" CURSOR_API_URL=https://cursor.test CURSOR_API_KEY=k bash "$here/../../skills/handoff/scripts/adapters/cursor.sh" artifacts bc-1
  eq exit 0 "$code"
  eq stdout "artifacts/checks.txt	120" "$out"
}

t_cursor_start_macos_hold() {
  fake_curl; fake_mac
  printf '{"items":[{"url":"https://github.com/o/r"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '{"agent":{"id":"bc-1","url":"https://cursor.com/agents/bc-1"}}\n' > "$FAKE_CURL/POST_v1_agents.json"
  printf '# Brief\n' > p.md
  cursor_mac start p.md --repo o/r --platform macos --hold-mac
  eq exit 0 "$code"
  w=$(jq -r .env.name "$FAKE_CURL/POST_v1_agents.data")
  eq row "bc-1	$w	wid-1	https://github.com/o/r	main	mac-1	hold" "$(macs)"
}

t_cursor_hold_needs_macos() {
  fake_curl
  printf '# Brief\n' > p.md
  cursor start p.md --repo o/r --hold-mac
  eq exit 1 "$code"
  eq stderr "cursor.sh: --hold-mac needs --platform macos" "$err"
}

# held_row: agent bc-1 on a held mac-1, its latest run FINISHED.
held_row() {
  mkdir -p "$T/home/.config/dispatch"
  printf 'bc-1\tho-1\twid-1\thttps://github.com/o/r\tmain\tmac-1\thold\n' > "$T/home/.config/dispatch/cursor-macs.tsv"
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"FINISHED","result":"Done"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
}

t_cursor_poll_keeps_held_mac() {
  fake_curl; fake_mac; held_row
  cursor_mac poll bc-1
  eq exit 0 "$code"
  [ ! -f "$T/mac.calls" ] || eq "mac calls" "" "$(cat "$T/mac.calls")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	mac-1	hold" "$(macs)"
}

t_cursor_down_held_mac() {
  fake_curl; fake_mac; held_row
  cursor_mac down bc-1
  eq exit 0 "$code"
  eq stdout "bc-1: destroyed mac-1" "$out"
  eq "mac down" "down mac-1" "$(cat "$T/mac.calls")"
  eq row "bc-1	ho-1	wid-1	https://github.com/o/r	main	-	hold" "$(macs)"
}

t_cursor_down_no_mac() {
  fake_curl
  cursor down bc-9
  eq exit 0 "$code"
  eq stdout "bc-9: no Mac" "$out"
}

t_cursor_wait() {
  fake_curl
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"EXPIRED","result":"Ran out of time"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  cursor wait bc-1 --interval 0
  eq exit 0 "$code"
  eq stdout "expired	run-2|EXPIRED	-	https://cursor.com/agents/bc-1	Ran out of time" "$out"
}

t_cursor_wait_max() {
  fake_curl
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"RUNNING"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  cursor wait bc-1 --interval 0 --max 1
  eq exit 0 "$code"
  eq stdout "still running	https://cursor.com/agents/bc-1" "$out"
}

cases=(
  "cursor start sends the prompt and prints the agent|t_cursor_start"
  "cursor start stops on a repo it has not connected|t_cursor_repo_not_connected"
  "cursor poll reads the latest run|t_cursor_poll"
  "cursor poll finds the issue's PR on GitHub|t_cursor_poll_github_pr"
  "cursor say starts a new run|t_cursor_say"
  "cursor stops without an API key|t_cursor_no_key"
  "cursor start on macos rents a Mac and targets its worker|t_cursor_start_macos"
  "cursor start on macos finds the agent when create hangs|t_cursor_start_macos_timeout"
  "cursor start on windows stops|t_cursor_start_windows"
  "cursor start on macos stops on a grok_ key|t_cursor_start_macos_grok_key"
  "cursor poll destroys the Mac when the run ends|t_cursor_poll_frees_mac"
  "cursor say rents a new Mac when none runs|t_cursor_say_new_mac"
  "cursor say keeps a Mac that runs|t_cursor_say_mac_alive"
  "cursor poll keeps a Mac a say rented meanwhile|t_cursor_poll_keeps_newer_mac"
  "cursor say destroys its new Mac when the send fails|t_cursor_say_send_fails"
  "cursor artifacts lists each file with its size|t_cursor_artifacts"
  "cursor download saves the file the presigned URL holds|t_cursor_download"
  "cursor download stops when the file will not come|t_cursor_download_fails"
  "cursor start shows the API's reason|t_cursor_start_api_reason"
  "handoff's Cursor adapter runs the shared client|t_cursor_handoff_adapter"
  "cursor start --hold-mac marks the Mac held|t_cursor_start_macos_hold"
  "cursor start --hold-mac needs macos|t_cursor_hold_needs_macos"
  "cursor poll keeps a held Mac when the run ends|t_cursor_poll_keeps_held_mac"
  "cursor down gives back a held Mac|t_cursor_down_held_mac"
  "cursor down on an agent with no Mac says so|t_cursor_down_no_mac"
  "cursor wait prints the run that ended|t_cursor_wait"
  "cursor wait stops at --max|t_cursor_wait_max"
)
