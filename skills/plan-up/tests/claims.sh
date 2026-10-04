# claims.sh: the cases for this skill's claims.py. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# issue_json <call> <assignees> <closing PRs> <timeline nodes> [<next>]:
# write the `gh api graphql` answer to call <call>, each list as JSON array
# items. <next>: the events go on after cursor <next>.
issue_json() {
  local more=false cursor=null
  [ -n "${5:-}" ] && { more=true; cursor="\"$5\""; }
  printf '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"assignees":{"nodes":[%s]},"closedByPullRequestsReferences":{"nodes":[%s],"pageInfo":{"hasNextPage":false,"endCursor":null}},"timelineItems":{"nodes":[%s],"pageInfo":{"hasNextPage":%s,"endCursor":%s}}}}}}\n' \
    "$2" "$3" "$4" "$more" "$cursor" > "$FAKE_GH/graphql.$1.json"
}

# vars <n>: the issue number and the cursors that call n sent, as
# `number=65 prAfter=p1 eventAfter=e1`.
vars() { sed -n "${1}p" "$FAKE_GH/graphql.args" | grep -oE '(number|prAfter|eventAfter)=[^ ]*' | paste -sd' ' -; }

claims() { run python3 "$here/../scripts/claims.py" o/r "$@"; }

pr70='{"number":70,"title":"Add the claim check","url":"https://github.com/o/r/pull/70","state":"OPEN","author":{"login":"bob"}}'
line70='#65 pr #70 "Add the claim check" @bob https://github.com/o/r/pull/70'

t_claims_closing_pr() {
  fake_gh; issue_json 1 '' "$pr70" ''
  claims 65
  eq exit 0 "$code"
  eq stdout "$line70" "$out"
}

t_claims_mentioning_pr() {
  fake_gh
  issue_json 1 '' '' '{"source":{"number":71,"title":"Refactor step 2","url":"https://github.com/o/r/pull/71","state":"OPEN","author":{"login":"carol"}}}'
  claims 65
  eq exit 0 "$code"
  eq stdout '#65 pr #71 "Refactor step 2" @carol https://github.com/o/r/pull/71' "$out"
}

t_claims_pr_once_open_only() {
  fake_gh
  issue_json 1 '' "$pr70" "{\"source\":$pr70},"'{"source":{"number":68,"title":"Old try","url":"https://github.com/o/r/pull/68","state":"MERGED","author":{"login":"bob"}}},{"source":{"number":69,"title":"Dropped","url":"https://github.com/o/r/pull/69","state":"CLOSED","author":{"login":"bob"}}},{"source":{}}'
  claims 65
  eq exit 0 "$code"
  eq stdout "$line70" "$out"
}

t_claims_next_page() {
  fake_gh
  issue_json 1 '' '' '' c1
  issue_json 2 '' '' '{"source":{"number":72,"title":"Late fix","url":"https://github.com/o/r/pull/72","state":"OPEN","author":{"login":"erin"}}}'
  claims 65
  eq exit 0 "$code"
  eq stdout '#65 pr #72 "Late fix" @erin https://github.com/o/r/pull/72' "$out"
  eq "call 2" "number=65 eventAfter=c1" "$(vars 2)"
}

t_claims_each_list_pages_on_its_own() {
  fake_gh
  pr71='{"number":71,"title":"Refactor step 2","url":"https://github.com/o/r/pull/71","state":"OPEN","author":{"login":"carol"}}'
  pr73='{"number":73,"title":"Second try","url":"https://github.com/o/r/pull/73","state":"OPEN","author":{"login":"dave"}}'
  printf '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"assignees":{"nodes":[]},"closedByPullRequestsReferences":{"nodes":[%s],"pageInfo":{"hasNextPage":true,"endCursor":"p1"}},"timelineItems":{"nodes":[{"source":%s}],"pageInfo":{"hasNextPage":false,"endCursor":"e1"}}}}}}\n' \
    "$pr70" "$pr71" > "$FAKE_GH/graphql.1.json"
  printf '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"assignees":{"nodes":[]},"closedByPullRequestsReferences":{"nodes":[%s],"pageInfo":{"hasNextPage":false,"endCursor":"p2"}},"timelineItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n' \
    "$pr73" > "$FAKE_GH/graphql.2.json"
  claims 65
  eq exit 0 "$code"
  eq stdout "$line70
#65 pr #71 \"Refactor step 2\" @carol https://github.com/o/r/pull/71
#65 pr #73 \"Second try\" @dave https://github.com/o/r/pull/73" "$out"
  eq "call 2" "number=65 prAfter=p1 eventAfter=e1" "$(vars 2)"
}

t_claims_other_assignee() {
  fake_gh; issue_json 1 '{"login":"me"},{"login":"dave"}' '' ''
  claims 65
  eq exit 0 "$code"
  eq stdout '#65 assignee @dave' "$out"
}

t_claims_none() {
  fake_gh; issue_json 1 '{"login":"me"}' '' ''
  claims 65
  eq exit 0 "$code"
  eq stdout "" "$out"
}

t_claims_each_issue() {
  fake_gh; issue_json 1 '' '' ''; issue_json 2 '{"login":"dave"}' '' ''
  claims 65 66
  eq exit 0 "$code"
  eq stdout '#66 assignee @dave' "$out"
  eq "call 1" "number=65" "$(vars 1)"
  eq "call 2" "number=66" "$(vars 2)"
}

t_claims_gh_fails() {
  fake_gh; printf 'gh: Could not resolve to an Issue with the number of 65.\n' > "$FAKE_GH/graphql.fail"
  claims 65
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr 'claims: #65: gh: Could not resolve to an Issue with the number of 65.' "$err"
}

cases=(
  "claims names an open PR that closes the issue|t_claims_closing_pr"
  "claims names an open PR that only mentions the issue|t_claims_mentioning_pr"
  "claims lists a PR once and skips closed and merged PRs|t_claims_pr_once_open_only"
  "claims reads a PR on the next page of links|t_claims_next_page"
  "claims reads each list of links to its own end|t_claims_each_list_pages_on_its_own"
  "claims names an assignee other than the user|t_claims_other_assignee"
  "claims prints nothing when no one is on the issue|t_claims_none"
  "claims checks each issue of a run|t_claims_each_issue"
  "claims fails when gh fails|t_claims_gh_fails"
)
