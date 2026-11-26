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
  printf '%s' "$out" | jq -r '.[] as $r | [$ARGS.positional[] | $r[.] | tostring] | join(" ")' --args "$@"
}

# days_ago <n>: the local date n days back, YYYY-MM-DD.
days_ago() { python3 -c 'import datetime as d,sys; print(d.date.today()-d.timedelta(days=int(sys.argv[1])))' "$1"; }

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
  eq row "a1 true false 1 fix the export 0m ago" "$(printf '%s' "$out" | jq -r '.[0] | "\(.id) \(.score > 0) \(.current) \(.prompts) \(.first_prompt) \(.age)"')"
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

t_aga_reads_t3_chat() {
  # Given: a chat T3 started: its first prompt wrapped in T3's instructions,
  # the attachments folder as a second workspace, and a title
  ag_home
  local p="<t3_code_instructions>x</t3_code_instructions>"$'\n'"<user_request>"$'\n'"fix the export"$'\n'"</user_request>"$'\n'"<runtime_info>y</runtime_info>"
  agy_chat "$HOME/.t3/userdata/providers/antigravity/p1/antigravity-acp/conversations/t1.db" "$HOME/.t3/userdata/attachments,/p/app" "$p" done 0 "Fix the export"
  # When
  run python3 "$A" find --root /p/app
  # Then
  eq row "t1 /p/app Fix the export | fix the export" "$(printf '%s' "$out" | jq -r '.[0] | "\(.id) \(.cwd) \(.title) | \(.first_prompt)"')"
}

t_aga_extract() {
  # Given: one terminal chat of /p/app
  ag_home; agy_chat "$C/a1.db" /p/app "fix the export" done
  # When
  run python3 "$A" extract a1 --summary --after-compact
  # Then
  eq exit 0 "$code"
  eq turns "---
## 🧑 User
fix the export
## 🤖 Antigravity
done" "$(printf '%s\n' "$out" | sed -n '/^---$/,$p' | grep -v '^$')"
}

t_aga_keeps_root_and_window() {
  # Given: chats of /p/app today, of /p/app/sub today, of /p/app-two today,
  # and of /p/app 30 days ago
  ag_home
  agy_chat "$C/a1.db" /p/app "fix the export" done
  agy_chat "$C/a2.db" /p/app/sub "fix the sub" done
  agy_chat "$C/a3.db" /p/app-two "fix the twin" done
  agy_chat "$C/a4.db" /p/app "fix the old" done 30
  # When
  run python3 "$A" find --root /p/app --since "$(days_ago 7)"
  # Then
  eq ids "a1
a2" "$(rows id | sort)"
}


cases=(
  "adapter finds a terminal chat in the window|t_aga_find_in_window"
  "adapter rows carry the score and prompt count|t_aga_rows_carry_query_fields"
  "adapter skips a chat with no steps|t_aga_skips_empty_chat"
  "adapter marks a file it cannot read|t_aga_marks_unreadable"
  "adapter reads a T3 chat|t_aga_reads_t3_chat"
  "adapter extract renders the prompts and replies|t_aga_extract"
  "adapter keeps chats below the root and in the window|t_aga_keeps_root_and_window"
)
