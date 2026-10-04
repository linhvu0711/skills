# test-lib.sh: the helpers every test case shares, the one fake gh, and the
# fake curl. test.sh sources this file first, then each skills/*/tests/*.sh
# and shared-skill-core/tests/*.sh, so the cases there call these helpers by
# name.
#
# Every leak string below is joined from two halves at runtime, so this file
# holds nothing check.sh flags.

# Run from a git hook or `git rebase --exec`, git sets GIT_DIR and its kin,
# and every temp repo below would write into the caller's repo instead.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

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
# issue-view, `repo view` repo-view, `api graphql` graphql, `api user` user,
# `api repos/…/rules/branches/…` rules, `api repos/…/branches/…` branch,
# `api repos/…/status` status, and `api repos/…/check-runs` check-runs. Each
# route counts its calls in <route>.calls and logs their args in
# <route>.args, one line per call (a newline inside an arg becomes a space).
# Call n of a route prints <route>.<n>.fail or <route>.fail to stderr and
# fails when one exists. Else
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
  " repo view"*) key=repo-view ;;
  " api graphql"*) key=graphql ;;
  " api user"*) key=user ;;
  " api repos/"*/rules/branches/*) key=rules ;;
  " api repos/"*/branches/*) key=branch ;;
  " api repos/"*/status*) key=status ;;
  " api repos/"*/check-runs*) key=check-runs ;;
  *) printf 'fake gh: no route for%s\n' "$args" >&2; exit 2 ;;
esac
n=$(( $(cat "$FAKE_GH/$key.calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_GH/$key.calls"
printf '%s\n' "${args# }" >> "$FAKE_GH/$key.args"
for f in "$FAKE_GH/$key.$n.fail" "$FAKE_GH/$key.fail"; do
  if [ -f "$f" ]; then cat "$f" >&2; exit 1; fi
done
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
# <route>.code, or 200. A route with no fixture answers 404.
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
