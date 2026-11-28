# devin.sh: the cases for dispatch's Devin adapter, driven through the fake
# curl of lib.sh. tests/run.sh sources this file after lib.sh and runs its
# cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# devin <args>: run the Devin adapter on the fake curl, with HOME in the temp
# folder and only the keys a case gives.
devin() { run env -u DEVIN_USER_ID HOME="$T/home" DEVIN_API_URL=https://devin.test DEVIN_ORG_ID=org1 DEVIN_API_KEY=k bash "$here/../../skills/dispatch/scripts/adapters/devin.sh" "$@"; }

t_devin_start() {
  fake_curl
  printf '{"attachment_id":"att-1","name":"p.md","url":"https://att.test/p.md"}\n' > "$FAKE_CURL/POST_v3_organizations_org1_attachments.json"
  printf '{"session_id":"devin-abc","url":"https://app.devin.ai/sessions/abc"}\n' > "$FAKE_CURL/POST_v3_organizations_org1_sessions.json"
  printf 'Repo: o/r\n\n# Brief\n' > p.md
  devin start p.md --title "#12 Export"
  eq exit 0 "$code"
  eq stdout "devin-abc	https://app.devin.ai/sessions/abc" "$out"
  has prompt 'ATTACHMENT:"https://att.test/p.md"' "$(jq -r .prompt "$FAKE_CURL/POST_v3_organizations_org1_sessions.data")"
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

t_devin_poll_every_pr() {
  fake_curl
  printf '{"session_id":"devin-abc","status":"running","status_detail":"working","pull_requests":[{"pr_url":"https://github.com/o/r/pull/5"},{"pr_url":"https://github.com/o/r/pull/6"}],"url":"https://app.devin.ai/sessions/abc"}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc.json"
  printf '{"items":[],"has_next_page":false}\n' > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc_messages.json"
  devin poll abc
  eq exit 0 "$code"
  eq stdout "working	working|-	https://github.com/o/r/pull/5,https://github.com/o/r/pull/6	https://app.devin.ai/sessions/abc	-" "$out"
}

t_devin_say() {
  fake_curl
  printf '{"attachment_id":"att-2","name":"note.md","url":"https://att.test/note.md"}\n' > "$FAKE_CURL/POST_v3_organizations_org1_attachments.json"
  printf '{}\n' > "$FAKE_CURL/POST_v3_organizations_org1_sessions_devin-abc_messages.json"
  printf '# Changed\n' > note.md
  devin say devin-abc note.md
  eq exit 0 "$code"
  eq stdout "sent to devin-abc" "$out"
}

t_devin_release() {
  # Given
  fake_curl
  # When
  devin release abc
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
  [ ! -f "$FAKE_CURL/calls" ] || eq "API calls" "" "$(cat "$FAKE_CURL/calls")"
}

t_devin_facts_pages() {
  # Given: two pages of repos, the second behind the cursor c2
  fake_curl
  printf '{"items":[{"repo_full_name":"o/a"}],"has_next_page":true,"end_cursor":"c2"}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_repositories.json"
  printf '{"items":[{"repo_full_name":"git.example.com/o/b"}],"has_next_page":false}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_repositories.after-c2.json"
  # When
  devin facts
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf 'repo\thttps://github.com/o/a\nrepo\thttps://git.example.com/o/b\nmode\tnormal\nmode\tfast\nmode\tlite\nmode\tultra\nmode\tfusion')" "$out"
}

t_devin_poll_pages() {
  # Given: a session whose messages span two pages
  fake_curl
  printf '{"session_id":"devin-abc","status":"running","status_detail":"waiting_for_user","pull_requests":[{"pr_url":"https://github.com/o/r/pull/5"}],"url":"https://app.devin.ai/sessions/abc"}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc.json"
  printf '{"items":[{"source":"devin","message":"First"}],"has_next_page":true,"end_cursor":"c2"}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc_messages.json"
  printf '{"items":[{"source":"devin","message":"Second"},{"source":"user","message":"ok"}],"has_next_page":false}\n' \
    > "$FAKE_CURL/GET_v3_organizations_org1_sessions_devin-abc_messages.after-c2.json"
  # When
  devin poll abc
  # Then
  eq exit 0 "$code"
  eq stdout "blocked	blocked|Second	https://github.com/o/r/pull/5	https://app.devin.ai/sessions/abc	Second" "$out"
}

cases=(
  "devin release holds nothing|t_devin_release"
  "devin start sends the brief and prints the session|t_devin_start"
  "devin poll reads state, PR, and message|t_devin_poll"
  "devin poll lists every PR of the session|t_devin_poll_every_pr"
  "devin say sends the note|t_devin_say"
  "devin facts reads every page|t_devin_facts_pages"
  "devin poll keeps the last devin message across pages|t_devin_poll_pages"
)
