# sessions-antigravity-adapter.sh: the cases for the shared core's
# sessions/antigravity/adapter.py. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
A="$here/../sessions/antigravity/adapter.py"

# ag_home: a fresh temp folder T with HOME at $T/home, holding the terminal
# chats folder C.
ag_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  C="$HOME/.gemini/antigravity-cli/conversations"; mkdir -p "$C"
}

# rows <fields>: each row of the find output, the named fields joined by spaces.
rows() {
  printf '%s' "$out" | python3 -c 'import json,sys; print("\n".join(" ".join(str(r.get(k)) for k in sys.argv[1:]) for r in json.load(sys.stdin)))' "$@"
}

t_aga_find_in_window() {
  # Given: one terminal chat of /p/app, today
  ag_home; agy_chat "$C/a1.db" /p/app "fix the export" done
  # When
  run python3 "$A" find --root /p/app --since "$(date +%F)"
  # Then
  eq exit 0 "$code"
  eq row "antigravity a1 fix the export" "$(rows harness id title)"
}

t_aga_rows_carry_query_fields() {
  # Given: one terminal chat of /p/app, today
  ag_home; agy_chat "$C/a1.db" /p/app "fix the export" done
  # When
  run python3 "$A" find --root /p/app --query export
  # Then
  eq row "a1 True False 1 fix the export 0m ago" "$(printf '%s' "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["id"], r["score"] > 0, r["current"], r["prompts"], r["first_prompt"], r["age"])')"
}

t_aga_skips_empty_chat() {
  # Given: a chat with no steps, as T3 makes at setup
  ag_home; agy_chat "$C/a2.db" /p/app "" ""
  # When
  run python3 "$A" find --root /p/app
  # Then
  eq exit 0 "$code"
  eq stdout "[]" "$out"
}

t_aga_marks_unreadable() {
  # Given: a file in the chats folder that is not a chat
  ag_home; printf 'not a database' > "$C/a3.db"
  # When
  run python3 "$A" find --root /p/app
  # Then
  eq exit 0 "$code"
  eq unreadable "not an Antigravity chat, project unknown" "$(rows unreadable)"
}

t_aga_probe_not_installed() {
  # Given: a fresh HOME with no .gemini and no .t3 folder
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"; mkdir -p "$HOME"
  # When
  run python3 "$A" probe --root /p/app
  # Then
  eq stdout '{"harness": "antigravity", "label": "Antigravity", "sessions": 0, "installed": false}' "$out"
}

cases=(
  "adapter finds a terminal chat in the window|t_aga_find_in_window"
  "adapter rows carry the score and prompt count|t_aga_rows_carry_query_fields"
  "adapter skips a chat with no steps|t_aga_skips_empty_chat"
  "adapter marks a file it cannot read|t_aga_marks_unreadable"
  "probe says Antigravity is not installed|t_aga_probe_not_installed"
)
