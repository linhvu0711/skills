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

t_cursor_repo_not_connected() {
  fake_curl
  printf '{"items":[{"url":"https://github.com/o/other"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '# Brief\n' > p.md
  cursor start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "stop: Connect o/r to Cursor first: cursor.com/dashboard, Integrations, GitHub." "$err"
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
  run env -u CURSOR_API_KEY HOME="$T/home" bash "$here/../scripts/adapters/cursor.sh" start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "stop: no CURSOR_API_KEY in ~/.zshrc or env (make one at cursor.com/dashboard, API Keys)" "$err"
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
  eq stderr "stop: Cursor has no Windows machine: hand this one to devin" "$err"
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

t_cursor_interval() {
  # Given
  fake_curl
  # When
  cursor interval
  # Then
  eq exit 0 "$code"
  eq stdout "60" "$out"
  [ ! -f "$FAKE_CURL/calls" ] || eq "API calls" "" "$(cat "$FAKE_CURL/calls")"
}

t_cursor_facts() {
  # Given
  fake_curl
  printf '{"items":[{"url":"https://github.com/o/r.git"}]}\n' > "$FAKE_CURL/GET_v1_repositories.json"
  printf '{"items":[{"id":"claude-opus-5","displayName":"Claude Opus 5"}]}\n' > "$FAKE_CURL/GET_v1_models.json"
  # When
  cursor facts
  # Then
  eq exit 0 "$code"
  eq stdout "repo	https://github.com/o/r
model	claude-opus-5	Claude Opus 5" "$out"
}

t_cursor_release_run_goes() {
  # Given
  fake_curl; fake_mac
  printf '%s\n' "$agent_bc1" > "$FAKE_CURL/GET_v1_agents_bc-1.json"
  printf '{"id":"run-2","status":"RUNNING"}\n' > "$FAKE_CURL/GET_v1_agents_bc-1_runs_run-2.json"
  # When
  cursor_mac release bc-1
  # Then
  eq exit 0 "$code"
  eq stdout "bc-1: mac-1 kept, its run has not ended" "$out"
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

t_cursor_say_new_mac() {
  # Given: mac.sh renew rents a new Mac from base main
  fake_curl; fake_mac
  echo main > "$T/mac.new"
  printf '{"run":{"id":"run-3"}}\n' > "$FAKE_CURL/POST_v1_agents_bc-1_runs.json"
  printf '# Changed\n' > note.md
  # When
  cursor_mac say bc-1 note.md
  # Then
  eq exit 0 "$code"
  eq "first line" "This run is on a new Mac: the repo is a fresh clone of main. Before you change anything, fetch and check out the branch you worked on, and its PR's branch if one is open." \
    "$(jq -r .prompt.text "$FAKE_CURL/POST_v1_agents_bc-1_runs.data" | sed -n 1p)"
  has note "# Changed" "$(jq -r .prompt.text "$FAKE_CURL/POST_v1_agents_bc-1_runs.data")"
}

cases=(
  "cursor say sends through mac.sh renew|t_cursor_say_through_renew"
  "cursor say tells the agent on a new Mac to check its branch out|t_cursor_say_new_mac"
  "cursor release keeps the Mac while the run goes|t_cursor_release_run_goes"
  "cursor release hands the run check to mac.sh return|t_cursor_release"
  "cursor release fails when the run cannot be read|t_cursor_release_check_fails"
  "cursor facts lists repos and models|t_cursor_facts"
  "cursor interval is 60|t_cursor_interval"
  "cursor start sends the prompt and prints the agent|t_cursor_start"
  "cursor start stops on a repo it has not connected|t_cursor_repo_not_connected"
  "cursor poll reads the latest run|t_cursor_poll"
  "cursor poll finds the issue's PR on GitHub|t_cursor_poll_github_pr"
  "cursor say starts a new run|t_cursor_say"
  "cursor stops without an API key|t_cursor_no_key"
  "cursor start on macos rents a Mac and targets its worker|t_cursor_start_macos"
  "cursor start on macos finds the agent when create hangs|t_cursor_start_macos_timeout"
  "cursor start on windows stops|t_cursor_start_windows"
  "cursor poll leaves the Mac when the run ended|t_cursor_poll_leaves_mac"
)
