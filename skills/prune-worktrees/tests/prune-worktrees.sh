# prune-worktrees.sh: the cases for this skill's prune-worktrees.sh. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The prune-worktrees script.
P="$here/../scripts/prune-worktrees.sh"

# wt_repo: repo, on a branch named main.
wt_repo() { repo; git branch -M main; }

# gh_remote: an origin on GitHub that is never contacted, with origin/main
# and origin/HEAD set from the local main.
gh_remote() {
  git remote add origin https://github.com/acme/app.git
  git update-ref refs/remotes/origin/main main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

# head_pr <branch> <number> <STATE> <sha>: the PR whose head is <branch>, as
# `gh pr list --head <branch> --json number,state,headRefOid` prints it.
head_pr() {
  printf '[{"number":%s,"state":"%s","headRefOid":"%s"}]\n' "$2" "$3" "$4" \
    > "$FAKE_GH/pr-list.$(printf '%s' "$1" | tr / _).json"
}

# wt <dir> <branch> [n]: a worktree of the repo on a new branch from main,
# with n empty commits (1 when not given).
wt() {
  git worktree add -q -b "$2" "$1" main
  local i; for i in $(seq "${3:-1}"); do git -C "$1" commit -q --allow-empty -m "c$i"; done
}

t_prune_removes_merged() {
  wt_repo; gh_remote; fake_gh; wt "$T/elsewhere/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "removed $T/elsewhere/feat-1-a, branch feat/1-a deleted (-D)" "$out"
  [ ! -e "$T/elsewhere/feat-1-a" ] || eq "$T/elsewhere/feat-1-a" "gone" "still there"
  eq "branch list" "" "$(git branch --list feat/1-a)"
}

t_prune_keeps_no_pr() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  git update-ref refs/remotes/origin/feat/1-a feat/1-a
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s: no PR\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_dirty() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'a\n' > "$T/w/feat-1-a/a.txt"; printf 'b\n' > "$T/w/feat-1-a/b.txt"
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq stdout "$(printf 'kept %s: 2 uncommitted files\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_unpushed() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a 2
  run bash "$P"
  eq stdout "$(printf 'kept %s: 2 commits not on GitHub\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_open_pr() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 159 OPEN "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq stdout "$(printf 'kept %s: PR #159 open\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_moved_tip() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED 0000000000000000000000000000000000000000
  run bash "$P"
  eq stdout "$(printf 'kept %s: PR #43 merged, tip is not its last commit\nnothing to prune' "$T/w/feat-1-a")" "$out"
  eq "branch list" "+ feat/1-a" "$(git branch --list feat/1-a)"
}

t_prune_git_only() {
  wt_repo; fake_gh; wt "$T/w/feat-2-b" feat/2-b
  git merge -q --ff-only feat/2-b
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "removed $T/w/feat-2-b, branch feat/2-b deleted (-d)" "$out"
  [ ! -e "$FAKE_GH/pr-list.args" ] || eq "gh calls" "none" "$(cat "$FAKE_GH/pr-list.args")"
}

t_prune_gh_fails() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  printf 'error connecting to api.github.com\n' > "$FAKE_GH/pr-list.fail"
  run bash "$P"
  eq exit 1 "$code"
  eq stdout "" "$out"
  eq stderr "stop: gh failed: error connecting to api.github.com" "$err"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_skips_session() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  cd "$T/w/feat-1-a"; run bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s: this session is in it\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_clears_stale() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/gone" feat/9-x; rm -rf "$T/w/gone"
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "cleared 1 stale entry" "$out"
  eq "worktree list lines" 1 "$(git worktree list | wc -l | tr -d ' ')"
}

t_prune_all() {
  wt_repo; gh_remote; fake_gh
  mkdir "$T/b"; git -C "$T/b" init -q -b main
  git -C "$T/b" -c user.email="t""@""example.invalid" -c user.name=t commit -q --allow-empty -m init
  git -C "$T/b" worktree add -q -b feat/2-b "$T/root/b/feat-2-b" main
  git -C "$T/b" merge -q --ff-only feat/2-b
  run env WORKTREES_ROOT="$T/root" bash "$P" all
  eq exit 0 "$code"
  eq stdout "removed $T/root/b/feat-2-b, branch feat/2-b deleted (-d)" "$out"
  [ ! -e "$T/root/b/feat-2-b" ] || eq "$T/root/b/feat-2-b" "gone" "still there"
}

t_prune_removes_named() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-3-c" feat/3-c; printf 'a\n' > "$T/w/feat-3-c/a.txt"
  run bash "$P" --remove "$T/w/feat-3-c"
  eq exit 0 "$code"
  eq stdout "removed $T/w/feat-3-c, branch feat/3-c kept: git branch -d refused" "$out"
  [ ! -e "$T/w/feat-3-c" ] || eq "$T/w/feat-3-c" "gone" "still there"
  eq "branch list" "  feat/3-c" "$(git branch --list feat/3-c)"
}

t_prune_nothing() {
  wt_repo; gh_remote; fake_gh
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "nothing to prune" "$out"
}

cases=(
  "prune removes a merged worktree outside the root|t_prune_removes_merged"
  "prune keeps a branch with no PR|t_prune_keeps_no_pr"
  "prune says when there is nothing to prune|t_prune_nothing"
  "prune keeps a dirty worktree|t_prune_keeps_dirty"
  "prune keeps unpushed commits|t_prune_keeps_unpushed"
  "prune keeps an open PR|t_prune_keeps_open_pr"
  "prune keeps a merged PR whose tip moved|t_prune_keeps_moved_tip"
  "prune uses only git with no GitHub remote|t_prune_git_only"
  "prune stops and removes nothing when gh fails|t_prune_gh_fails"
  "prune skips the session's worktree|t_prune_skips_session"
  "prune clears a stale entry|t_prune_clears_stale"
  "prune all goes through every repo under the root|t_prune_all"
  "prune removes a named worktree and keeps an unmerged branch|t_prune_removes_named"
)
