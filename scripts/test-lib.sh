# test-lib.sh: the helpers every test case shares, the one fake gh, the
# fake curl, and the fake nsc. test.sh sources this file first, then each
# skills/*/tests/*.sh and shared/tests/*.sh, so the cases there call these
# helpers by name.
#
# Every leak string below is joined from two halves at runtime, so this file
# holds nothing check.sh flags.

# Run from a git hook or `git rebase --exec`, git sets GIT_DIR and its kin,
# and every temp repo below would write into the caller's repo instead.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

# A case's commit or checkout with the hooks on runs link.sh, which links
# skills, skill agents, and the Antigravity plugins folder into these folders;
# keep it off the real ones. The one T3 folder keeps its no-folder line quiet.
SKILLS_HOME="$(mktemp -d)/agents"; CLAUDE_SKILLS_HOME="${SKILLS_HOME%/agents}/claude"
CLAUDE_AGENTS_HOME="${SKILLS_HOME%/agents}/claude-agents"
ANTIGRAVITY_SKILLS_HOME="${SKILLS_HOME%/agents}/antigravity-skills"
ANTIGRAVITY_PLUGINS_HOME="${SKILLS_HOME%/agents}/antigravity-plugins"
T3_ANTIGRAVITY_HOME="${SKILLS_HOME%/agents}/t3"; mkdir -p "$T3_ANTIGRAVITY_HOME/p1"
export SKILLS_HOME CLAUDE_SKILLS_HOME CLAUDE_AGENTS_HOME ANTIGRAVITY_SKILLS_HOME ANTIGRAVITY_PLUGINS_HOME T3_ANTIGRAVITY_HOME

# This scripts/ folder. A sourced skill test file sets its own `here`.
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# repo: a fresh repo in a temp folder with scripts/ committed; cd into it.
# Sets T (the temp folder) and R (the repo, a physical path).
repo() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; R="$T/repo"
  mkdir -p "$R"; cd "$R"
  git init -q
  git config user.email "t""@""example.invalid"; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  cp -R "$scripts_dir" "$R/scripts"
  git add scripts; git commit -qm init
}

# run <cmd...>: run it, keep its exit code in `code`, stdout in `out`, stderr in `err`.
run() {
  code=0
  "$@" >"$T/out" 2>"$T/err" || code=$?
  out="$(cat "$T/out")"; err="$(cat "$T/err")"
}

eq() { [ "$2" = "$3" ] || { printf '%s: expected [%s], got [%s]\n' "$1" "$2" "$3" >&2; exit 1; }; }
has() { case "$3" in *"$2"*) ;; *) printf '%s: [%s] not in [%s]\n' "$1" "$2" "$3" >&2; exit 1 ;; esac; }

# fake_gh: a fake gh and a no-op sleep first on PATH, in the temp folder T
# (made when T is not set yet). The gh answers from fixture files in
# $FAKE_GH, by route: `pr list` is pr-list, `pr view` pr-view, `issue view`
# issue-view, `issue list` issue-list, `run view` run-view, `repo view` repo-view, `api graphql` graphql, `api user` user, `auth token` auth-token,
# `api repos/…/rules/branches/…` rules, `api repos/…/branches/…` branch,
# `api repos/…/status` status, `api repos/…/check-runs` check-runs,
# `api repos/…/actions/jobs/…` job, any other
# `api repos/…` repo, and `pr merge` pr-merge. Each
# route counts its calls in <route>.calls and logs their args in
# <route>.args, one line per call (a newline inside an arg becomes a space).
# Call n of a route prints <route>.<n>.fail or <route>.fail to stderr and
# fails when one exists. Else it prints <route>.stderr to stderr when one
# exists, as gh prints a hint beside its answer, and
# `pr list … --base <b>` or `--head <b>` prints pr-list.<b, with / as _>.json,
# or `[]` when there is none, and every other route prints <route>.<n>.json or
# <route>.json. The answer goes through `jq -r` when given -q or --jq.
fake_gh() {
  [ -n "${T:-}" ] || T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/bin" "$T/gh"
  cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
q=""; args=""; branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--jq) q="$2"; shift 2 ;;
    --base|--head) branch="${2:-}"; args="$args $1 $branch"; shift 2 ;;
    *) args="$args ${1//$'\n'/ }"; shift ;;
  esac
done
case "$args" in
  " pr list"*) key=pr-list ;;
  " pr view"*) key=pr-view ;;
  " issue view"*) key=issue-view ;;
  " issue list"*) key=issue-list ;;
  " run view"*) key=run-view ;;
  " repo view"*) key=repo-view ;;
  " api graphql"*) key=graphql ;;
  " api user"*) key=user ;;
  " auth token"*) key=auth-token ;;
  " api repos/"*/rules/branches/*) key=rules ;;
  " api repos/"*/branches/*) key=branch ;;
  " api repos/"*/status*) key=status ;;
  " api repos/"*/check-runs*) key=check-runs ;;
  " api repos/"*/actions/jobs/*) key=job ;;
  " api repos/"*) key=repo ;;
  " pr merge"*) key=pr-merge ;;
  *) printf 'fake gh: no route for%s\n' "$args" >&2; exit 2 ;;
esac
n=$(( $(cat "$FAKE_GH/$key.calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_GH/$key.calls"
printf '%s\n' "${args# }" >> "$FAKE_GH/$key.args"
for f in "$FAKE_GH/$key.$n.fail" "$FAKE_GH/$key.fail"; do
  if [ -f "$f" ]; then cat "$f" >&2; exit 1; fi
done
if [ -f "$FAKE_GH/$key.stderr" ]; then cat "$FAKE_GH/$key.stderr" >&2; fi
if [ "$key" = pr-list ]; then
  f="$FAKE_GH/pr-list.$(printf '%s' "$branch" | tr / _).json"
  if [ -f "$f" ]; then answer="$(cat "$f")"; else answer='[]'; fi
else
  f="$FAKE_GH/$key.$n.json"; [ -f "$f" ] || f="$FAKE_GH/$key.json"
  answer="$(cat "$f")"
fi
if [ -n "$q" ]; then jq -r "$q" <<<"$answer"; else printf '%s\n' "$answer"; fi
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sleep"
  chmod +x "$T/bin/gh" "$T/bin/sleep"
  export PATH="$T/bin:$PATH" FAKE_GH="$T/gh"
}

# fake_curl: a fake curl first on PATH, in the temp folder T (made when T is
# not set yet). cd into T.
# The curl answers from fixture files in $FAKE_CURL, by route: the method and
# the URL's path, query dropped, every / as _, as in
# POST_v3_organizations_org1_sessions. It logs `<METHOD> <path>` to calls,
# writes -d to <route>.data, writes <route>.json to the -o file, and prints
# <route>.code, or 200. A route with no fixture answers 404; a <route>.exit
# fixture makes the call exit with that code instead.
fake_curl() {
  [ -n "${T:-}" ] || T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/bin" "$T/curl"
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
# A <key>.exit file makes the call fail with that curl exit code, as a
# timeout (28) does.
[ ! -f "$FAKE_CURL/$key.exit" ] || exit "$(cat "$FAKE_CURL/$key.exit")"
if [ -f "$FAKE_CURL/$key.json" ]; then
  cat "$FAKE_CURL/$key.json" > "$out"
  cat "$FAKE_CURL/$key.code" 2>/dev/null || printf 200
else
  printf '{"detail":"fake curl: no fixture %s"}\n' "$key" > "$out"
  printf 404
fi
EOF
  chmod +x "$T/bin/curl"
  export PATH="$T/bin:$PATH" FAKE_CURL="$T/curl"
  cd "$T"
}

# fake_nsc: a fake nsc first on PATH, beside the fake gh. Call n logs its
# args to $FAKE_NSC/calls and its stdin to $FAKE_NSC/stdin.<n>; `create`
# writes mac-1 to its --cidfile; a call prints $FAKE_NSC/<n>.out and exits
# with $FAKE_NSC/<n>.exit when those files exist.
fake_nsc() {
  fake_gh
  mkdir -p "$T/nsc"
  cat > "$T/bin/nsc" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_NSC/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_NSC/n"
printf '%s\n' "$*" >> "$FAKE_NSC/calls"
cat > "$FAKE_NSC/stdin.$n"
if [ "$1" = create ]; then
  while [ $# -gt 0 ]; do [ "$1" = --cidfile ] && echo mac-1 > "$2"; shift; done
fi
[ ! -f "$FAKE_NSC/$n.out" ] || cat "$FAKE_NSC/$n.out"
[ ! -f "$FAKE_NSC/$n.exit" ] || exit "$(cat "$FAKE_NSC/$n.exit")"
exit 0
EOF
  chmod +x "$T/bin/nsc"
  export FAKE_NSC="$T/nsc"
  printf 'gho_secret\n' > "$FAKE_GH/auth-token.json"
}

# agy_chat <file> <cwd> <prompt> <reply> [<days ago>] [<title>]: an Antigravity
# chat file, in the shape agy 1.5.12 writes: SQLite with protobuf blobs, its
# id the file's stem, one prompt and one reply <days ago> days back (default
# 0). <cwd> is one path or several joined by `,`. An empty prompt writes a chat
# with no steps. A title also goes in conversation_summaries.db beside the
# conversations folder. Shared, since the session adapter's tests and recall's
# both build chats.
agy_chat() {
  mkdir -p "$(dirname "$1")"
  python3 -I - "$@" <<'EOF'
import os, sqlite3, sys, time

def varint(n):
    out = b""
    while True:
        b = n & 0x7F; n >>= 7
        out += bytes([b | (0x80 if n else 0)])
        if not n:
            return out

def field(num, value):
    if isinstance(value, int):
        return varint(num << 3) + varint(value)
    data = value.encode() if isinstance(value, str) else value
    return varint(num << 3 | 2) + varint(len(data)) + data

path, cwd, prompt, reply = sys.argv[1:5]
days = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else 0
title = sys.argv[6] if len(sys.argv) > 6 else ""
cid = os.path.splitext(os.path.basename(path))[0]
when = field(1, field(1, int(time.time()) - days * 86400))
spaces = b"".join(field(12, "file://" + p) for p in cwd.split(","))
db = sqlite3.connect(path)
db.execute("create table trajectory_meta (trajectory_id text, cascade_id text)")
db.execute("create table steps (idx integer, step_type integer, metadata blob, step_payload blob)")
db.execute("insert into trajectory_meta values ('t-' || ?, ?)", (cid, cid))
if prompt:
    ask = field(1, 14) + field(19, field(2, prompt) + field(12, spaces))
    answer = field(1, 15) + field(20, field(1, reply))
    db.execute("insert into steps values (0, 14, ?, ?)", (when, ask))
    db.execute("insert into steps values (1, 15, ?, ?)", (when, answer))
db.commit()
if title:
    summary = sqlite3.connect(os.path.join(os.path.dirname(path), "..", "conversation_summaries.db"))
    summary.execute("create table if not exists conversation_summaries (conversation_id text, title text)")
    summary.execute("insert into conversation_summaries values (?, ?)", (cid, title))
    summary.commit()
EOF
}
