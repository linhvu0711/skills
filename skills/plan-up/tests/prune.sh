# prune.sh: the cases for this skill's prune.py. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# chat_plan <slug> <touch -t stamp>: a chat plan and its prompt in
# $PLAN_DIR, both dated <stamp>.
chat_plan() {
  printf '# Plan: [feat] Export orders as CSV\n\n## Facts\nRepo: acme/shop\n' > "$PLAN_DIR/plan-$1.md"
  : > "$PLAN_DIR/plan-$1.html"; : > "$PLAN_DIR/prompt-$1.md"
  touch -t "$2" "$PLAN_DIR/plan-$1.md" "$PLAN_DIR/plan-$1.html" "$PLAN_DIR/prompt-$1.md"
}

# ticket_plan <slug>: a ticket plan in $PLAN_DIR, its issue the slug's last number.
ticket_plan() {
  printf '# Plan: #%s Export\n\n## Facts\nRepo: acme/shop        Base: main\n' "${1##*-}" > "$PLAN_DIR/plan-$1.md"
}

# run_plan <slug> <row>...: a run plan in $PLAN_DIR with these Stack rows.
run_plan() {
  local slug="$1"; shift
  { printf '# Plan: #71 Teams\n\n## Stack\n| Layer | Issue | Base | Size | Points |\n|---|---|---|---|---|\n'
    printf '%s\n' "$@"
    printf '\n## Facts\nRepo: acme/shop        Base: main\n'; } > "$PLAN_DIR/plan-$slug.md"
}

# closed <n>...: the fake gh lists these issues as closed.
closed() {
  local n list=""
  for n in "$@"; do list="$list${list:+,}{\"number\":$n}"; done
  printf '[%s]\n' "$list" > "$FAKE_GH/issue-list.json"
}

prune() { run python3 "$here/../scripts/prune.py" "$@"; }

t_prune_old_chat_plan() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  chat_plan acme-shop-chat-orders-csv 202001010000
  prune
  eq exit 0 "$code"
  eq stdout "$(printf 'pruned acme-shop-chat-orders-csv\npruned 1, kept 0')" "$out"
  eq left "" "$(ls "$PLAN_DIR")"
  [ ! -e "$FAKE_GH/issue-list.calls" ]
}

t_prune_keeps_new_chat_plan() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  chat_plan acme-shop-chat-orders-csv "$(date +%Y%m%d%H%M)"
  prune
  eq exit 0 "$code"
  eq stdout "pruned 0, kept 1" "$out"
  eq left 3 "$(ls "$PLAN_DIR" | wc -l | tr -d ' ')"
}

t_prune_dry_run_keeps_old_chat_plan() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  chat_plan acme-shop-chat-orders-csv 202001010000
  prune -n
  eq exit 0 "$code"
  eq stdout "$(printf 'pruned acme-shop-chat-orders-csv\npruned 1, kept 0 (dry run)')" "$out"
  eq left 3 "$(ls "$PLAN_DIR" | wc -l | tr -d ' ')"
}

t_prune_closed_plans() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  # Given: plan 42 and its files, all closed; plan 43, still open
  ticket_plan acme-shop-42; : > "$PLAN_DIR/plan-acme-shop-42.html"; : > "$PLAN_DIR/prompt-acme-shop-42.md"
  ticket_plan acme-shop-43
  closed 42 7
  # When
  prune
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf 'pruned acme-shop-42\npruned 1, kept 1')" "$out"
  eq left plan-acme-shop-43.md "$(ls "$PLAN_DIR")"
  prune
  eq "second stdout" "pruned 0, kept 1" "$out"
}

t_prune_run_plan() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  # Given: run 71 has every Stack issue closed; run 74 has #75 open
  run_plan acme-shop-71-run '| 1 | #71 Team entity | main | M | 4 |' '| 2 | #73 Add a member | layer 1 | S | 2 |'
  run_plan acme-shop-74-run '| 1 | #74 Invite | main | S | 2 |' '| 2 | #75 Team switcher | layer 1 | S | 2 |'
  closed 71 73 74
  # When
  prune
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf 'pruned acme-shop-71-run\npruned 1, kept 1')" "$out"
  eq left plan-acme-shop-74-run.md "$(ls "$PLAN_DIR")"
}

t_prune_stray() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  # Given: two files and no plan
  : > "$PLAN_DIR/prompt-acme-shop-9.md"; : > "$PLAN_DIR/todo-acme-shop-1.md"
  # When
  prune
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf 'stray prompt-acme-shop-9.md\nstray todo-acme-shop-1.md\npruned 0, kept 0')" "$out"
  eq left 2 "$(ls "$PLAN_DIR" | wc -l | tr -d ' ')"
}

t_prune_gh_error() {
  fake_gh; export PLAN_DIR="$T/plan"; mkdir -p "$PLAN_DIR"
  # Given: gh cannot list the closed issues
  ticket_plan acme-shop-42
  echo boom > "$FAKE_GH/issue-list.fail"
  # When
  prune
  # Then
  eq exit 0 "$code"
  eq stdout "pruned 0, kept 1" "$out"
  eq stderr "" "$err"
  eq left plan-acme-shop-42.md "$(ls "$PLAN_DIR")"
}

t_prune_default_folder() {
  fake_gh; export PLAN_DIR="$T/home/.agents/artifacts/plan"; mkdir -p "$PLAN_DIR"
  # Given: an old chat plan in the default folder, and no PLAN_DIR
  chat_plan acme-shop-chat-orders-csv 202001010000
  unset PLAN_DIR; export HOME="$T/home"
  # When
  prune
  # Then
  eq exit 0 "$code"
  eq stdout "$(printf 'pruned acme-shop-chat-orders-csv\npruned 1, kept 0')" "$out"
  eq left "" "$(ls "$T/home/.agents/artifacts/plan")"
}

cases=(
  "prune deletes a chat plan older than 30 days|t_prune_old_chat_plan"
  "prune keeps a new chat plan|t_prune_keeps_new_chat_plan"
  "prune -n names an old chat plan and keeps it|t_prune_dry_run_keeps_old_chat_plan"
  "prune deletes a plan whose issues are all closed and keeps one with an open issue|t_prune_closed_plans"
  "prune deletes a run plan only when every Stack issue is closed|t_prune_run_plan"
  "prune names a file that belongs to no plan as stray and keeps it|t_prune_stray"
  "prune keeps a plan when gh cannot list closed issues|t_prune_gh_error"
  "prune reads the default plan folder when PLAN_DIR is unset|t_prune_default_folder"
)
