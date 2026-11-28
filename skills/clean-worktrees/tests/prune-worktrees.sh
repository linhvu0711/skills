# prune-worktrees.sh: the cases for this skill's prune-worktrees.sh. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

P="$here/../scripts/prune-worktrees.sh"

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

# root_wt <worktree> <branch>: a new repo (repo, on main) with a worktree at
# <worktree> on <branch>, merged into main. It runs in a subshell, so T, R,
# and the folder the case runs prune from stay the session's repo.
root_wt() { ( repo; git branch -M main; git worktree add -q -b "$2" "$1" main; git merge -q --ff-only "$2" ); }

t_prune_removes_merged() {
  wt_repo; gh_remote; fake_gh; wt "$T/elsewhere/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'removed %s (<1M), branch feat/1-a deleted (-D)\nfreed <1M' "$T/elsewhere/feat-1-a")" "$out"
  [ ! -e "$T/elsewhere/feat-1-a" ] || eq "$T/elsewhere/feat-1-a" "gone" "still there"
  eq "branch list" "" "$(git branch --list feat/1-a)"
}

t_prune_alias_origin() {
  # Given: origin is gh:acme/app, an insteadOf alias for GitHub, and the branch's PR merged
  wt_repo; fake_gh
  git remote add origin gh:acme/app
  git config url.https://github.com/.insteadOf gh:
  git update-ref refs/remotes/origin/main main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  # When
  run bash "$P"
  # Then
  eq stdout "$(printf 'removed %s (<1M), branch feat/1-a deleted (-D)\nfreed <1M' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_no_pr() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  git update-ref refs/remotes/origin/feat/1-a feat/1-a
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s (<1M): no PR\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_dirty() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  printf 'a\n' > "$T/w/feat-1-a/a.txt"; printf 'b\n' > "$T/w/feat-1-a/b.txt"
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq stdout "$(printf 'kept %s (<1M): 2 uncommitted files\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_unpushed() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a 2
  run bash "$P"
  eq stdout "$(printf 'kept %s (<1M): 2 commits not on GitHub\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_open_pr() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 159 OPEN "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq stdout "$(printf 'kept %s (<1M): PR #159 open\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_moved_tip() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED 0000000000000000000000000000000000000000
  run bash "$P"
  eq stdout "$(printf 'kept %s (<1M): PR #43 merged, tip is not its last commit\nnothing to prune' "$T/w/feat-1-a")" "$out"
  eq "branch list" "+ feat/1-a" "$(git branch --list feat/1-a)"
}

t_prune_git_only() {
  wt_repo; fake_gh; wt "$T/w/feat-2-b" feat/2-b
  git merge -q --ff-only feat/2-b
  run bash "$P"
  eq exit 0 "$code"
  eq stdout "$(printf 'removed %s (<1M), branch feat/2-b deleted (-d)\nfreed <1M' "$T/w/feat-2-b")" "$out"
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
  eq stdout "$(printf 'kept %s (<1M): this session is in it\nnothing to prune' "$T/w/feat-1-a")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_all() {
  wt_repo; gh_remote; fake_gh
  root_wt "$T/root/b/feat-2-b" feat/2-b
  run env WORKTREES_ROOT="$T/root" bash "$P" all
  eq exit 0 "$code"
  eq stdout "$(printf 'removed %s (<1M), branch feat/2-b deleted (-d)\nfreed <1M' "$T/root/b/feat-2-b")" "$out"
  [ ! -e "$T/root/b/feat-2-b" ] || eq "$T/root/b/feat-2-b" "gone" "still there"
}

t_prune_removes_named() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-3-c" feat/3-c; printf 'a\n' > "$T/w/feat-3-c/a.txt"
  run bash "$P" --remove "$T/w/feat-3-c"
  eq exit 0 "$code"
  eq stdout "$(printf 'removed %s (<1M), branch feat/3-c kept: git branch -d refused\nfreed <1M' "$T/w/feat-3-c")" "$out"
  [ ! -e "$T/w/feat-3-c" ] || eq "$T/w/feat-3-c" "gone" "still there"
  eq "branch list" "  feat/3-c" "$(git branch --list feat/3-c)"
}

t_prune_keeps_locked() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  git worktree lock "$T/w/feat-1-a"
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  run bash "$P"
  eq stdout "$(printf 'kept %s (<1M): locked\nnothing to prune' "$T/w/feat-1-a")" "$out"
}

t_prune_keeps_in_use() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  # The full path: $T/bin/sleep is the no-op one.
  local pid; cd "$T/w/feat-1-a"; /bin/sleep 30 & pid=$!; cd "$R"
  run bash "$P"
  kill "$pid"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s (<1M): in use by sleep (pid %s)\nnothing to prune' "$T/w/feat-1-a" "$pid")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

t_prune_keeps_late_in_use() {
  wt_repo; gh_remote; fake_gh; wt "$T/w/feat-1-a" feat/1-a
  head_pr feat/1-a 43 MERGED "$(git rev-parse feat/1-a)"
  # A gh that starts a process in the worktree while the script waits on it,
  # after the first read of the working folders.
  mv "$T/bin/gh" "$T/bin/gh-fake"
  printf '#!/usr/bin/env bash\ncd "%s"; /bin/sleep 30 >/dev/null 2>&1 & echo $! > "%s"; cd /\nexec "%s" "$@"\n' \
    "$T/w/feat-1-a" "$T/late.pid" "$T/bin/gh-fake" > "$T/bin/gh"
  chmod +x "$T/bin/gh"
  run bash "$P"
  local pid; pid="$(cat "$T/late.pid")"; kill "$pid"
  eq exit 0 "$code"
  eq stdout "$(printf 'kept %s (<1M): in use by sleep (pid %s)\nnothing to prune' "$T/w/feat-1-a" "$pid")" "$out"
  [ -d "$T/w/feat-1-a" ] || eq "$T/w/feat-1-a" "a folder" "missing"
}

cases=(
  "prune removes a merged worktree outside the root|t_prune_removes_merged"
  "prune keeps a branch with no PR|t_prune_keeps_no_pr"
  "prune keeps a dirty worktree|t_prune_keeps_dirty"
  "prune keeps unpushed commits|t_prune_keeps_unpushed"
  "prune keeps an open PR|t_prune_keeps_open_pr"
  "prune keeps a merged PR whose tip moved|t_prune_keeps_moved_tip"
  "prune uses only git with no GitHub remote|t_prune_git_only"
  "prune counts an insteadOf alias origin as GitHub|t_prune_alias_origin"
  "prune stops and removes nothing when gh fails|t_prune_gh_fails"
  "prune skips the session's worktree|t_prune_skips_session"
  "prune all goes through every repo under the root|t_prune_all"
  "prune removes a named worktree and keeps an unmerged branch|t_prune_removes_named"
  "prune keeps a locked worktree|t_prune_keeps_locked"
  "prune keeps a worktree a live process is in|t_prune_keeps_in_use"
  "prune keeps a worktree a process enters while it runs|t_prune_keeps_late_in_use"
)
