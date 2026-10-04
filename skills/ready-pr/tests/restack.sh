# restack.sh: the cases for this skill's restack.sh. The repo's
# test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

restack="$here/../scripts/restack.sh"

# pr <number> <base> <head> [fork]: one PR as `gh pr list --json` prints it.
pr() {
  local fork=false; [ "${4:-}" = fork ] && fork=true
  printf '{"number":%s,"baseRefName":"%s","headRefName":"%s","url":"https://github.com/o/r/pull/%s","isCrossRepository":%s}' "$1" "$2" "$3" "$1" "$fork"
}

t_restack_lists_stack_in_order() {
  fake_gh
  printf '[%s,%s]\n' "$(pr 13 feat/a feat/d)" "$(pr 11 feat/a feat/b)" > "$FAKE_GH/pr-list.feat_a.json"
  printf '[%s]\n' "$(pr 12 feat/b feat/c)" > "$FAKE_GH/pr-list.feat_b.json"
  run bash "$restack" list o/r feat/a
  eq exit 0 "$code"
  eq stdout "STACK=3
11 feat/a feat/b https://github.com/o/r/pull/11 fork=false
12 feat/b feat/c https://github.com/o/r/pull/12 fork=false
13 feat/a feat/d https://github.com/o/r/pull/13 fork=false" "$out"
}

t_restack_lists_child_behind_fork_of_same_name() {
  fake_gh
  printf '[%s,%s]\n' "$(pr 11 feat/a feat/b fork)" "$(pr 12 feat/a feat/b)" > "$FAKE_GH/pr-list.feat_a.json"
  printf '[%s]\n' "$(pr 13 feat/b feat/c)" > "$FAKE_GH/pr-list.feat_b.json"
  run bash "$restack" list o/r feat/a
  eq exit 0 "$code"
  eq stdout "STACK=3
11 feat/a feat/b https://github.com/o/r/pull/11 fork=true
12 feat/a feat/b https://github.com/o/r/pull/12 fork=false
13 feat/b feat/c https://github.com/o/r/pull/13 fork=false" "$out"
}

t_restack_stops_past_100_prs() {
  fake_gh
  { printf '['; for n in $(seq 1 101); do [ "$n" = 1 ] || printf ','; pr "$n" feat/a "feat/x$n"; done; printf ']\n'; } > "$FAKE_GH/pr-list.feat_a.json"
  run bash "$restack" list o/r feat/a
  eq exit 1 "$code"
  eq stderr "stop: more than 100 open PRs on feat/a; restack lists at most 100" "$err"
}

t_restack_lists_nothing() {
  fake_gh
  run bash "$restack" list o/r feat/a
  eq exit 0 "$code"
  eq stdout "STACK=0" "$out"
}

# stack [clash]: a temp folder T with a bare origin and R, its clone; cd into R.
# main has f=a; feat/a adds p (a1); feat/b on it adds b (b1, which also sets
# f=b with `clash`); feat/c on it adds c (c1); all pushed. Then main sets f=main,
# and feat/a is rebased onto it and force-pushed, R left on it. A_OLD is feat/a's
# tip before that; $T/stack holds `restack.sh list` lines for feat/b and feat/c.
stack() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; R="$T/repo"
  git init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$R" 2>/dev/null; cd "$R"
  git config user.email "t""@""example.invalid"; git config user.name t
  git config commit.gpgsign false; git config core.hooksPath .no-hooks
  echo a > f; git add f; git commit -qm base; git branch -M main; git push -q origin main
  git checkout -qb feat/a; echo p > p; git add p; git commit -qm a1
  git checkout -qb feat/b; echo b > b; if [ "${1:-}" = clash ]; then echo b > f; fi
  git add b f; git commit -qm b1
  git checkout -qb feat/c; echo c > c; git add c; git commit -qm c1
  git push -q origin feat/a feat/b feat/c
  git checkout -q main; echo main > f; git commit -qam "main edits f"; git push -q origin main
  A_OLD="$(git rev-parse origin/feat/a)"
  git checkout -q feat/a; git rebase -q main; git push -q --force-with-lease origin feat/a
  printf '%s\n' "STACK=2" \
    "11 feat/a feat/b https://github.com/o/r/pull/11 fork=false" \
    "12 feat/b feat/c https://github.com/o/r/pull/12 fork=false" > "$T/stack"
}

t_restack_moves_children_bottom_first() {
  stack
  run bash "$restack" move "$R" feat/a "$A_OLD" "$T/stack"
  eq exit 0 "$code"
  eq "line 1" "MOVED https://github.com/o/r/pull/11" "$(printf '%s\n' "$out" | sed -n 1p | cut -d' ' -f1-2)"
  eq "line 2" "MOVED https://github.com/o/r/pull/12" "$(printf '%s\n' "$out" | sed -n 2p | cut -d' ' -f1-2)"
  eq "line 3" "RESTACK=moved 2" "$(printf '%s\n' "$out" | sed -n 3p)"
  eq "commits on main" "c1
b1
a1" "$(git log --format=%s origin/main..origin/feat/c)"
  eq "feat/b's parent" "$(git rev-parse origin/feat/a)" "$(git rev-parse origin/feat/b~1)"
  eq "local feat/c" "$(git rev-parse origin/feat/c)" "$(git rev-parse feat/c)"
  eq worktrees 1 "$(git worktree list | wc -l | tr -d ' ')"
}

t_restack_stops_on_clash() {
  stack clash
  b="$(git rev-parse origin/feat/b)"; c="$(git rev-parse origin/feat/c)"
  run bash "$restack" move "$R" feat/a "$A_OLD" "$T/stack"
  eq exit 1 "$code"
  eq stdout "CLASH https://github.com/o/r/pull/11: f
LEFT https://github.com/o/r/pull/12
RESTACK=stopped" "$out"
  eq "origin/feat/b" "$b" "$(git rev-parse origin/feat/b)"
  eq "origin/feat/c" "$c" "$(git rev-parse origin/feat/c)"
  eq worktrees 1 "$(git worktree list | wc -l | tr -d ' ')"
  eq status "" "$(git status --porcelain)"
}

t_restack_skips_unpushed_branch() {
  stack
  git checkout -q feat/b; git commit -q --allow-empty -m local; git checkout -q feat/a
  b="$(git rev-parse origin/feat/b)"
  run bash "$restack" move "$R" feat/a "$A_OLD" "$T/stack"
  eq exit 1 "$code"
  eq stdout "SKIP https://github.com/o/r/pull/11: feat/b has 1 commit(s) not on origin
LEFT https://github.com/o/r/pull/12
RESTACK=stopped" "$out"
  eq "origin/feat/b" "$b" "$(git rev-parse origin/feat/b)"
}

t_restack_skips_merge_commits() {
  stack
  git checkout -q -b side feat/b; echo s > s; git add s; git commit -qm side
  git checkout -q feat/b; echo b2 >> b; git commit -qam b2; git merge -q --no-ff -m merge side
  git push -q origin feat/b; git checkout -q feat/a
  b="$(git rev-parse origin/feat/b)"
  run bash "$restack" move "$R" feat/a "$A_OLD" "$T/stack"
  eq exit 1 "$code"
  eq stdout "SKIP https://github.com/o/r/pull/11: feat/b has merge commits; move it by hand
LEFT https://github.com/o/r/pull/12
RESTACK=stopped" "$out"
  eq "origin/feat/b" "$b" "$(git rev-parse origin/feat/b)"
}

t_restack_skips_dirty_worktree() {
  stack
  git worktree add -q "$T/bwt" feat/b; echo x >> "$T/bwt/b"
  b="$(git rev-parse origin/feat/b)"
  run bash "$restack" move "$R" feat/a "$A_OLD" "$T/stack"
  eq exit 1 "$code"
  eq stdout "SKIP https://github.com/o/r/pull/11: worktree $T/bwt has uncommitted changes
LEFT https://github.com/o/r/pull/12
RESTACK=stopped" "$out"
  eq "origin/feat/b" "$b" "$(git rev-parse origin/feat/b)"
}

cases=(
  "restack lists the stack in order|t_restack_lists_stack_in_order"
  "restack lists nothing on a bare branch|t_restack_lists_nothing"
  "restack moves children bottom first|t_restack_moves_children_bottom_first"
  "restack stops on a clash|t_restack_stops_on_clash"
  "restack skips an unpushed branch|t_restack_skips_unpushed_branch"
  "restack skips a dirty worktree|t_restack_skips_dirty_worktree"
  "restack skips a child with merge commits|t_restack_skips_merge_commits"
  "restack lists a child behind a fork of the same name|t_restack_lists_child_behind_fork_of_same_name"
  "restack stops past 100 PRs on a branch|t_restack_stops_past_100_prs"
)
