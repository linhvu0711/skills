# find.sh: the cases for this skill's find.py. The repo's test.sh sources
# this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
F="$here/../scripts/find.py"

# rc_home: a fresh temp folder T with HOME at $T/home, holding both tools'
# session folders, and a project folder P that the case runs from. No session
# is this one.
rc_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  export HOME="$T/home"
  mkdir -p "$HOME/.claude/projects" "$HOME/.codex/sessions"
  P="$T/app"; mkdir -p "$P"; cd "$P"
  unset CLAUDE_CODE_SESSION_ID
}

# rc_claude <id> <prompt> [<days ago>]: a Claude Code transcript of P, with one
# user prompt and one reply, last changed <days ago> days back (default 0).
rc_claude() {
  local d f
  d="$HOME/.claude/projects/$(python3 -c 'import re,sys; print(re.sub(r"[^a-zA-Z0-9]", "-", sys.argv[1]))' "$P")"
  f="$d/$1.jsonl"; mkdir -p "$d"
  printf '{"type":"user","message":{"role":"user","content":"%s"},"timestamp":"2026-10-01T10:00:00Z","cwd":"%s","sessionId":"%s"}\n' "$2" "$P" "$1" > "$f"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"cwd":"%s"}\n' "$P" >> "$f"
  rc_age "$f" "${3:-0}"
}

# rc_codex <id> <prompt> [<days ago>] [<source>]: a Codex rollout of P in
# today's day folder, with one user message, last changed <days ago> days back
# (default 0), started by <source> (default `cli`; `exec` is a script's run).
rc_codex() {
  local d f
  d="$HOME/.codex/sessions/$(date +%Y/%m/%d)"; f="$d/rollout-2026-10-01T10-00-00-$1.jsonl"; mkdir -p "$d"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s","timestamp":"2026-10-01T10:00:00Z","source":"%s"}}\n' "$1" "$P" "${4:-cli}" > "$f"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$2" >> "$f"
  rc_age "$f" "${3:-0}"
}

# rc_age <file> <days>: set the file's mtime to <days> days ago.
rc_age() { python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2])*86400; os.utime(sys.argv[1],(t,t))' "$1" "$2"; }

# heads: the first two words of each stdout line, one pair per line.
heads() { printf '%s\n' "$out" | cut -d' ' -f1,2; }

t_rc_both_tools() {
  rc_home
  rc_claude s1 "fix the export" 2
  rc_claude s2 "add the flag"
  rc_codex c1 "export button"
  run python3 "$F" export
  eq exit 0 "$code"
  eq sessions "codex c1
claude s1" "$(heads)"
}

t_rc_leaves_out_recall() {
  rc_home
  rc_claude s1 "fix the export" 1
  rc_claude s3 "fix the export"
  rc_claude r1 "/recall export"
  export CLAUDE_CODE_SESSION_ID=s3
  run python3 "$F" export
  eq exit 0 "$code"
  eq sessions "claude s1" "$(heads)"
}

t_rc_no_match() {
  rc_home
  rc_claude s2 "add the flag"
  run python3 "$F" export
  eq exit 1 "$code"
  eq out "No sessions on export." "$out"
}

t_rc_common_words() {
  rc_home
  rc_claude s1 "fix the export"
  rc_codex c1 "export button"
  run python3 "$F" the
  eq exit 1 "$code"
  eq out "No sessions on the." "$out"
}

t_rc_ten_newest() {
  rc_home
  local k
  for k in 0 1 2 3 4 5 6 7 8 9 10 11; do rc_claude "n$k" "fix the export" "$k"; done
  run python3 "$F" export
  eq exit 0 "$code"
  eq sessions "claude n0
claude n1
claude n2
claude n3
claude n4
claude n5
claude n6
claude n7
claude n8
claude n9" "$(printf '%s\n' "$out" | head -10 | cut -d' ' -f1,2)"
  eq last "Skipped 2 older sessions." "$(printf '%s\n' "$out" | sed -n '11,$p')"
}

t_rc_no_codex() {
  rc_home
  rm -rf "$HOME/.codex"
  rc_claude s1 "fix the export"
  run python3 "$F" export
  eq exit 0 "$code"
  eq first "claude s1" "$(printf '%s\n' "$out" | head -1 | cut -d' ' -f1,2)"
  eq last "Codex is not installed: Claude Code sessions only." "$(printf '%s\n' "$out" | sed -n '2,$p')"
}

t_rc_leaves_out_exec() {
  # Given: a Codex session a person started, and one a script started
  rc_home
  rc_codex c1 "export button"
  rc_codex x1 "export the config" 0 exec
  # When
  run python3 "$F" export
  # Then
  eq exit 0 "$code"
  eq sessions "codex c1" "$(heads)"
}

cases=(
  "finds a topic in Claude Code and Codex sessions, newest first|t_rc_both_tools"
  "leaves out this session and earlier recall runs|t_rc_leaves_out_recall"
  "no session matches|t_rc_no_match"
  "a topic of only common words matches nothing|t_rc_common_words"
  "keeps the 10 newest and says how many it skipped|t_rc_ten_newest"
  "Codex is not installed|t_rc_no_codex"
  "leaves out Codex runs a script started|t_rc_leaves_out_exec"
)
