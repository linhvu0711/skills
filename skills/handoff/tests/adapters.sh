# adapters.sh: the cases for this skill's Devin and Cursor adapters, each
# driven through a fake curl. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_curl: a fake curl first on PATH, in the temp folder T (made when T is
# not set yet), HOME in T with no .zshrc, and DEVIN_USER_ID unset. cd into T.
# The curl answers from fixture files in $FAKE_CURL, by route: the method and
# the URL's path, query dropped, every / as _, as in
# POST_v3_organizations_org1_sessions. It logs `<METHOD> <path>` to calls,
# writes -d to <route>.data, writes <route>.json to the -o file, and prints
# <route>.code, or 200. A route with no fixture answers 404.
fake_curl() {
  [ -n "${T:-}" ] || T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/bin" "$T/curl" "$T/home"
  cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""; method=GET; data=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -d) data="$2"; shift 2 ;;
    -H|-F|-w) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
path="/${url#*://*/}"; path="${path%%\?*}"
key="$method$(printf '%s' "$path" | tr / _)"
printf '%s %s\n' "$method" "$path" >> "$FAKE_CURL/calls"
[ -z "$data" ] || printf '%s\n' "$data" > "$FAKE_CURL/$key.data"
if [ -f "$FAKE_CURL/$key.json" ]; then
  cat "$FAKE_CURL/$key.json" > "$out"
  cat "$FAKE_CURL/$key.code" 2>/dev/null || printf 200
else
  printf '{"detail":"fake curl: no fixture %s"}\n' "$key" > "$out"
  printf 404
fi
EOF
  chmod +x "$T/bin/curl"
  export PATH="$T/bin:$PATH" FAKE_CURL="$T/curl" HOME="$T/home"
  unset DEVIN_USER_ID
  cd "$T"
}

devin() { run env DEVIN_API_URL=https://devin.test DEVIN_ORG_ID=org1 DEVIN_API_KEY=k bash "$here/../scripts/adapters/devin.sh" "$@"; }

t_devin_start() {
  fake_curl
  printf '"https://att.test/p.md"\n' > "$FAKE_CURL/POST_v3_organizations_org1_attachments.json"
  printf '{"session_id":"devin-abc","url":"https://app.devin.ai/sessions/abc"}\n' > "$FAKE_CURL/POST_v3_organizations_org1_sessions.json"
  printf 'Repo: o/r\n\n# Brief\n' > p.md
  devin start p.md --title "#12 Export"
  eq exit 0 "$code"
  eq stdout "devin-abc	https://app.devin.ai/sessions/abc" "$out"
}

t_devin_poll() {
  fake_curl
  printf '{"session_id":"devin-abc","status":"running","status_detail":"waiting_for_user","pull_requests":[{"pr_url":"https://github.com/o/r/pull/5"}],"url":"https://app.devin.ai/sessions/abc"}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc.json"
  printf '{"items":[{"source":"user","message":"Go"},{"source":"devin","message":"Which file?"}],"has_next_page":false}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc_messages.json"
  devin poll abc
  eq exit 0 "$code"
  eq stdout "blocked	blocked|Which file?	https://github.com/o/r/pull/5	https://app.devin.ai/sessions/abc	Which file?" "$out"
}

t_devin_say() {
  fake_curl
  printf '"https://att.test/note.md"\n' > "$FAKE_CURL/POST_v3_organizations_org1_attachments.json"
  printf '{}\n' > "$FAKE_CURL/POST_v3_organizations_org1_sessions_devin-abc_messages.json"
  printf '# Changed\n' > note.md
  devin say devin-abc note.md
  eq exit 0 "$code"
  eq stdout "sent to devin-abc" "$out"
}

t_devin_failed_call() {
  fake_curl
  printf '"https://att.test/p.md"\n' > "$FAKE_CURL/POST_v3_organizations_org1_attachments.json"
  printf '400' > "$FAKE_CURL/POST_v3_organizations_org1_sessions.code"
  printf '{"detail":"platform must be one of linux, macos"}\n' > "$FAKE_CURL/POST_v3_organizations_org1_sessions.json"
  printf '# Brief\n' > p.md
  devin start p.md --platform mac
  eq exit 1 "$code"
  eq stderr "devin.sh: HTTP 400 on POST /sessions: platform must be one of linux, macos" "$err"
}

t_devin_no_key() {
  fake_curl
  printf '# Brief\n' > p.md
  run env -u DEVIN_API_KEY DEVIN_ORG_ID=org1 bash "$here/../scripts/adapters/devin.sh" start p.md
  eq exit 1 "$code"
  eq stderr "devin.sh: no DEVIN_API_KEY in ~/.zshrc or env" "$err"
}

cursor() { run env CURSOR_API_URL=https://cursor.test CURSOR_API_KEY=k bash "$here/../scripts/adapters/cursor.sh" "$@"; }

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
  run env -u CURSOR_API_KEY bash "$here/../scripts/adapters/cursor.sh" start p.md --repo o/r
  eq exit 1 "$code"
  eq stderr "cursor.sh: no CURSOR_API_KEY in ~/.zshrc or env (make one at cursor.com/dashboard, API Keys)" "$err"
}

cases=(
  "devin start sends the brief and prints the session|t_devin_start"
  "devin poll reads state, PR, and message|t_devin_poll"
  "devin say sends the note|t_devin_say"
  "devin start prints the API message on a failed call|t_devin_failed_call"
  "devin stops without an API key|t_devin_no_key"
  "cursor start sends the prompt and prints the agent|t_cursor_start"
  "cursor start stops on a repo it has not connected|t_cursor_repo_not_connected"
  "cursor poll reads the latest run|t_cursor_poll"
  "cursor poll finds the issue's PR on GitHub|t_cursor_poll_github_pr"
  "cursor say starts a new run|t_cursor_say"
  "cursor stops without an API key|t_cursor_no_key"
)
