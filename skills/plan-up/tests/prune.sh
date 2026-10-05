# prune.sh: the cases for this skill's prune.sh. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# chat_plan <slug> <touch -t stamp>: a chat plan and its prompt in
# $PLAN_DIR, both dated <stamp>.
chat_plan() {
  printf '# Plan: [feat] Export orders as CSV\n\n## Facts\nRepo: `acme/shop`\n' > "$PLAN_DIR/plan-$1.md"
  : > "$PLAN_DIR/plan-$1.html"; : > "$PLAN_DIR/prompt-$1.md"
  touch -t "$2" "$PLAN_DIR/plan-$1.md" "$PLAN_DIR/plan-$1.html" "$PLAN_DIR/prompt-$1.md"
}

prune() { run bash "$here/../scripts/prune.sh" "$@"; }

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

cases=(
  "prune deletes a chat plan older than 30 days|t_prune_old_chat_plan"
  "prune keeps a new chat plan|t_prune_keeps_new_chat_plan"
  "prune -n names an old chat plan and keeps it|t_prune_dry_run_keeps_old_chat_plan"
)
