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

t_ck_reuses_old_shape() {
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" worktree add -q -b feat/2-y "$T/root/app/feat-2-y" main
  resolve acme/app feat/2-y
  eq stdout "MAIN=$T/dev/app WORKTREE=$T/root/app/feat-2-y BRANCH=feat/2-y DEFAULT=main STATE=reused FROM=existing" "$out"
}

t_ck_stops_dirty() {
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" worktree add -q -b feat/2-y "$T/root/app/feat-2-y" main
  printf 'a\n' > "$T/root/app/feat-2-y/a.txt"
  resolve acme/app feat/2-y
  eq stderr "$(printf 'stop: dirty worktree at %s:\n?? a.txt' "$T/root/app/feat-2-y")" "$err"
}

t_ck_default_from_origin_head() {
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" push -q origin main:trunk
  git -C "$T/dev/app" fetch -q origin
  git -C "$T/dev/app" remote set-head origin trunk >/dev/null
  printf 'gh: not logged in\n' > "$FAKE_GH/repo-view.fail"
  resolve acme/app feat/3-z --base main
  eq stdout "MAIN=$T/dev/app WORKTREE=$T/root/acme/app/feat-3-z BRANCH=feat/3-z DEFAULT=trunk STATE=created FROM=base:main" "$out"
}

t_ck_no_default() {
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" remote set-head origin -d
  printf 'gh: not logged in\n' > "$FAKE_GH/repo-view.fail"
  resolve acme/app feat/3-z --base main
  eq stderr "stop: could not find the default branch of acme/app: gh failed and origin/HEAD is not set. Set it with: git -C $T/dev/app remote set-head origin --auto" "$err"
}

t_ck_reuses_spaced_path() {
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" worktree add -q -b feat/2-y "$T/my wt/feat-2-y" main
  resolve acme/app feat/2-y
  eq stdout "MAIN=$T/dev/app WORKTREE=$T/my wt/feat-2-y BRANCH=feat/2-y DEFAULT=main STATE=reused FROM=existing" "$out"
}

t_ck_base_without_value() {
  ck_setup
  resolve acme/app feat/x --base
  eq stderr "stop: usage: checkout.sh <owner/repo> <branch> [--base <ref>]" "$err"
}

t_ck_alias_origin() {
  ck_setup
  git init -q -b main "$T/dev/app"
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/dev/app" branch feat/4-a
  git -C "$T/dev/app" remote add origin gh:acme/app
  git -C "$T/dev/app" config url.https://github.com/.insteadOf gh:
  resolve acme/app feat/4-a
  eq stdout "MAIN=$T/dev/app WORKTREE=$T/root/acme/app/feat-4-a BRANCH=feat/4-a DEFAULT=main STATE=created FROM=local" "$out"
}

t_ck_github_rewrite() {
  ck_setup
  git init -q -b main "$T/dev/app"
  git -C "$T/dev/app" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/dev/app" branch feat/x
  git -C "$T/dev/app" remote add origin https://github.com/acme/app.git
  git -C "$T/dev/app" config url.https://github.com/other/app.git.insteadOf https://github.com/acme/app.git
  resolve acme/app feat/x
  eq stderr "stop: no checkout of acme/app under $T/dev. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ck_worktrees_lists_all() {
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" worktree add -q -b feat/1-a "$T/w/feat 1" main
  git -C "$T/dev/app" worktree add -q --detach "$T/w/det" main
  git -C "$T/dev/app" worktree add -q -b feat/2-b "$T/w/locked" main
  git -C "$T/dev/app" worktree lock "$T/w/locked"
  git -C "$T/dev/app" worktree add -q -b feat/3-c "$T/w/gone" main
  rm -rf "$T/w/gone"
  resolve worktrees "$T/dev/app"
  eq stdout "BRANCH=main LOCKED=0 PRUNABLE=0 WORKTREE=$T/dev/app
BRANCH= LOCKED=0 PRUNABLE=0 WORKTREE=$T/w/det
BRANCH=feat/1-a LOCKED=0 PRUNABLE=0 WORKTREE=$T/w/feat 1
BRANCH=feat/2-b LOCKED=1 PRUNABLE=0 WORKTREE=$T/w/locked
BRANCH=feat/3-c LOCKED=0 PRUNABLE=1 WORKTREE=$T/w/gone" \
    "$(printf '%s\n' "$out" | sed -n 1p; printf '%s\n' "$out" | sed 1d | LC_ALL=C sort)"
}

t_ck_worktrees_outside_git() {
  ck_setup; mkdir -p "$T/plain"
  resolve worktrees "$T/plain"
  eq stderr "stop: not a git checkout: $T/plain" "$err"
}

t_ck_worktrees_bare_first() {
  ck_setup; ck acme/app "$T/dev/app"
  git clone -q --bare "$T/dev/app" "$T/app.git"
  git -C "$T/app.git" worktree add -q -b feat/1-a "$T/w/feat-1-a" main
  resolve worktrees "$T/w/feat-1-a"
  eq stdout "BRANCH= LOCKED=0 PRUNABLE=0 WORKTREE=$T/app.git
BRANCH=feat/1-a LOCKED=0 PRUNABLE=0 WORKTREE=$T/w/feat-1-a" "$out"
}

t_ck_main_by_search() {
  ck_setup; ck acme/app "$T/dev/app"
  resolve main acme/app
  eq stdout "FROM=search MAIN=$T/dev/app" "$out"
}

t_ck_main_from_map() {
  ck_setup; ck acme/app "$T/dev/app"
  resolve main acme/app
  resolve main acme/app
  eq stdout "FROM=map MAIN=$T/dev/app" "$out"
}

t_ck_main_no_checkout() {
  ck_setup; mkdir -p "$T/dev"
  resolve main acme/app
  eq stderr "stop: no checkout of acme/app under $T/dev. Clone it, or add a line to $T/map.tsv: acme/app<TAB>/path" "$err"
}

t_ck_slug_alias() {
  # Given: a checkout whose origin is the alias gh:acme/app, rewritten to GitHub
  ck_setup
  git init -q -b main "$T/dev/app"
  git -C "$T/dev/app" remote add origin gh:acme/app
  git -C "$T/dev/app" config url.https://github.com/.insteadOf gh:
  # When
  run bash "$C" slug "$T/dev/app"
  # Then
  eq stdout "acme/app" "$out"
}

t_ck_slug_no_remote() {
  # Given: the case above with no origin added
  ck_setup
  git init -q -b main "$T/dev/app"
  # When
  run bash "$C" slug "$T/dev/app"
  # Then
  eq stderr "stop: $T/dev/app has no GitHub remote" "$err"
}

# ck_listed <dir> <ignore> <list>: commit a .gitignore holding <ignore> and a
# .worktreeinclude holding <list>, one pattern per line, to the main checkout
# at <dir>, and push them, so a worktree made from origin/main has them too.
ck_listed() {
  printf '%s\n' "$2" > "$1/.gitignore"
  printf '%s\n' "$3" > "$1/.worktreeinclude"
  git -C "$1" add .gitignore .worktreeinclude
  git -C "$1" -c user.email="t""@""example.invalid" -c user.name=t commit -q -m list
  git -C "$1" push -q origin main
}

t_ck_copies_listed() {
  # Given: .dev.vars is git-ignored and listed, and only in the main checkout
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" .dev.vars .dev.vars
  printf 'TOKEN=local\n' > "$T/dev/app/.dev.vars"
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq file TOKEN=local "$(cat "$T/root/acme/app/feat-1-x/.dev.vars" 2>/dev/null || true)"
  eq stderr "worktreeinclude: copied .dev.vars" "$err"
}

t_ck_names_missing() {
  # Given: the case above, with .env.local listed too and in no checkout
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" $'.dev.vars\n.env.local' $'.dev.vars\n.env.local'
  printf 'TOKEN=local\n' > "$T/dev/app/.dev.vars"
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq exit 0 "$code"
  eq stderr $'worktreeinclude: copied .dev.vars\nworktreeinclude: not in the main checkout, skipped: .env.local' "$err"
}

t_ck_copies_only_listed() {
  # Given: ignored node_modules and dist, and a listed notes.txt git does not ignore
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" $'.dev.vars\nnode_modules/\ndist/' $'.dev.vars\nnotes.txt'
  mkdir -p "$T/dev/app/node_modules/x" "$T/dev/app/dist"
  printf 'TOKEN=local\n' > "$T/dev/app/.dev.vars"
  printf 'deep\n' > "$T/dev/app/node_modules/x/.dev.vars"
  printf 'js\n' > "$T/dev/app/dist/app.js"
  printf 'note\n' > "$T/dev/app/notes.txt"
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq ignored '!! .dev.vars' "$(git -C "$T/root/acme/app/feat-1-x" status --porcelain --ignored)"
  eq stderr $'worktreeinclude: copied .dev.vars\nworktreeinclude: not git-ignored, skipped: notes.txt' "$err"
}

t_ck_copies_in_named_folder() {
  # Given: vendor/ is ignored whole, and the list names a file inside it
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" vendor/ 'vendor/**/config.json'
  mkdir -p "$T/dev/app/vendor/a"
  printf 'v=1\n' > "$T/dev/app/vendor/a/config.json"
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq file v=1 "$(cat "$T/root/acme/app/feat-1-x/vendor/a/config.json" 2>/dev/null || true)"
}

t_ck_second_run_copies_nothing() {
  # Given: the first copy case, run once
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" .dev.vars .dev.vars
  printf 'TOKEN=local\n' > "$T/dev/app/.dev.vars"
  resolve acme/app feat/1-x --base main
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq "run 2" "|STATE=reused FROM=existing|TOKEN=local" "$err|${out##* BRANCH=feat/1-x DEFAULT=main }|$(cat "$T/root/acme/app/feat-1-x/.dev.vars" 2>/dev/null || true)"
}

t_ck_reused_gets_missing() {
  # Given: the first copy case, run once, then the copy lost, as after a crash
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" .dev.vars .dev.vars
  printf 'TOKEN=local\n' > "$T/dev/app/.dev.vars"
  resolve acme/app feat/1-x --base main
  rm -f "$T/root/acme/app/feat-1-x/.dev.vars"
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq copy "TOKEN=local|worktreeinclude: copied .dev.vars" "$(cat "$T/root/acme/app/feat-1-x/.dev.vars" 2>/dev/null || true)|$err"
}

t_ck_keeps_worktree_link() {
  # Given: the first copy case, run once, then the worktree's .dev.vars made a link to no file
  ck_setup; ck acme/app "$T/dev/app"
  ck_listed "$T/dev/app" .dev.vars .dev.vars
  printf 'TOKEN=local\n' > "$T/dev/app/.dev.vars"
  resolve acme/app feat/1-x --base main
  ln -sf "$T/nowhere/vars" "$T/root/acme/app/feat-1-x/.dev.vars"
  # When
  resolve acme/app feat/1-x --base main
  # Then
  eq link "$T/nowhere/vars|" "$(readlink "$T/root/acme/app/feat-1-x/.dev.vars")|$err"
}

t_ck_holder_names_worktree() {
  # Given: app with feat/1-a checked out in a worktree whose path has a space
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" worktree add -q -b feat/1-a "$T/w/feat 1" main
  # When
  resolve holder "$T/dev/app" feat/1-a
  # Then
  eq exit 0 "$code"
  eq stdout "$T/w/feat 1" "$out"
}

t_ck_holder_none() {
  # Given: app with feat/1-a checked out in a worktree whose path has a space
  ck_setup; ck acme/app "$T/dev/app"
  git -C "$T/dev/app" worktree add -q -b feat/1-a "$T/w/feat 1" main
  # When
  resolve holder "$T/dev/app" feat/9-z
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
}

cases=(
  "keeps a link the worktree has at a listed path|t_ck_keeps_worktree_link"
  "copies a listed git-ignored file into a new worktree|t_ck_copies_listed"
  "names a listed file the main checkout lacks|t_ck_names_missing"
  "copies nothing the list does not name|t_ck_copies_only_listed"
  "copies a file in an ignored folder the list names|t_ck_copies_in_named_folder"
  "a second run copies nothing again|t_ck_second_run_copies_nothing"
  "a reused worktree gets a listed file it lacks|t_ck_reused_gets_missing"
  "creates a worktree at root/owner/repo/branch|t_ck_creates"
  "two repos with one name get two folders|t_ck_two_repos_one_name"
  "stops when no checkout is found|t_ck_no_checkout"
  "stops on two checkouts|t_ck_two_checkouts"
  "stops on a bad branch name|t_ck_bad_branch"
  "reuses an old-shape worktree by its branch|t_ck_reuses_old_shape"
  "stops on a dirty worktree for the branch|t_ck_stops_dirty"
  "default branch falls back to origin/HEAD|t_ck_default_from_origin_head"
  "stops when gh and origin/HEAD both fail|t_ck_no_default"
  "reuses a worktree whose path has a space|t_ck_reuses_spaced_path"
  "stops when --base has no value|t_ck_base_without_value"
  "finds a checkout whose origin is an alias rewritten to GitHub|t_ck_alias_origin"
  "a rewrite to another GitHub repo names only that repo|t_ck_github_rewrite"
  "worktrees lists each worktree with its branch, lock, and gone state|t_ck_worktrees_lists_all"
  "worktrees stops on a folder outside git|t_ck_worktrees_outside_git"
  "worktrees lists a bare repo first, as git does|t_ck_worktrees_bare_first"
  "holder names the worktree on a branch|t_ck_holder_names_worktree"
  "holder names nothing for a free branch|t_ck_holder_none"
  "main finds the one checkout by search|t_ck_main_by_search"
  "main reads the map it wrote|t_ck_main_from_map"
  "main stops when no checkout is found|t_ck_main_no_checkout"
  "slug names the repo an alias origin points at|t_ck_slug_alias"
  "slug stops on a checkout with no GitHub remote|t_ck_slug_no_remote"
)
