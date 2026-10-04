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
  run env -u CURSOR_API_KEY HOME="$T/home" bash "$here/../scripts/adapters/cursor.sh" start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "cursor.sh: no CURSOR_API_KEY in ~/.zshrc or env (make one at cursor.com/dashboard, API Keys)" "$err"
}

cases=(
  "cursor start sends the prompt and prints the agent|t_cursor_start"
  "cursor start stops on a repo it has not connected|t_cursor_repo_not_connected"
  "cursor poll reads the latest run|t_cursor_poll"
  "cursor poll finds the issue's PR on GitHub|t_cursor_poll_github_pr"
  "cursor say starts a new run|t_cursor_say"
  "cursor stops without an API key|t_cursor_no_key"
)
