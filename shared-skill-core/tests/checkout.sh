# checkout.sh: the cases for the shared core's checkout.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The checkout resolver.
C="$here/../checkout.sh"

# ck_setup: a fresh temp folder T and the fake gh, whose `repo view` names
# main as the default branch.
ck_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  fake_gh
  printf '{"defaultBranchRef":{"name":"main"}}\n' > "$FAKE_GH/repo-view.json"
}

# ck <owner/repo> <dir>: a main checkout at <dir> on main with one commit. Its
# origin is the GitHub URL of <owner/repo>, rewritten by insteadOf to a bare
# repo at $T/remotes/<owner/repo>.git (made by the first ck of that slug), so
# fetches stay local while the configured URL still names the slug.
ck() {
  local slug="$1" dir="$2" bare="$T/remotes/$1.git"
  git init -q -b main "$dir"
  git -C "$dir" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  if [ ! -d "$bare" ]; then mkdir -p "$(dirname "$bare")"; git clone -q --bare "$dir" "$bare"; fi
  git -C "$dir" remote add origin "https://github.com/$slug.git"
  git -C "$dir" config "url.$bare.insteadOf" "https://github.com/$slug.git"
  git -C "$dir" fetch -q origin
  git -C "$dir" remote set-head origin main >/dev/null
}

# resolve <args...>: run the resolver from T, with the worktree root, the
# search root, and the repo map all inside T.
resolve() {
  cd "$T"
  run env WORKTREES_ROOT="$T/root" KICKOFF_DEV_ROOT="$T/dev" KICKOFF_REPO_MAP="$T/map.tsv" bash "$C" "$@"
}

t_ck_creates() {
  ck_setup; ck acme/app "$T/dev/app"
  resolve acme/app feat/1-x --base main
  eq stdout "MAIN=$T/dev/app WORKTREE=$T/root/acme/app/feat-1-x BRANCH=feat/1-x DEFAULT=main STATE=created FROM=base:main" "$out"
}

t_ck_two_repos_one_name() {
  ck_setup; ck acme/app "$T/dev/acme/app"; ck other/app "$T/dev/other/app"
  resolve acme/app feat/x --base main
  resolve other/app feat/x --base main
  eq stdout "MAIN=$T/dev/other/app WORKTREE=$T/root/other/app/feat-x BRANCH=feat/x DEFAULT=main STATE=created FROM=base:main" "$out"
}

t_ck_no_checkout() {
  ck_setup; mkdir -p "$T/dev"
  resolve acme/app feat/x --base main
  eq stderr "stop: no checkout of acme/app under $T/dev. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ck_two_checkouts() {
  ck_setup; ck acme/app "$T/dev/a/app"; ck acme/app "$T/dev/b/app"
  resolve acme/app feat/x --base main
  eq stderr "stop: several checkouts of acme/app: $T/dev/a/app $T/dev/b/app. Add the right one to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ck_bad_branch() {
  ck_setup; ck acme/app "$T/dev/app"
  resolve acme/app feat..x --base main
  eq stderr "stop: not a valid branch name: feat..x" "$err"
}

cases=(
  "creates a worktree at root/owner/repo/branch|t_ck_creates"
  "two repos with one name get two folders|t_ck_two_repos_one_name"
  "stops when no checkout is found|t_ck_no_checkout"
  "stops on two checkouts|t_ck_two_checkouts"
  "stops on a bad branch name|t_ck_bad_branch"
)
