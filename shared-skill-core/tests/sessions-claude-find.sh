# sessions-claude-find.sh: the cases for the shared core's
# sessions/claude/find_sessions.py. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
F="$here/../sessions/claude/find_sessions.py"

# ccf_home: a fresh temp folder T with HOME at $T/home, so the finder reads
# only the sessions a case writes.
ccf_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  export HOME="$T/home"
  mkdir -p "$HOME/.claude/projects"
}

# cc_session <folder> <id> <cwd> <prompt> [<days ago>]: a transcript at
# ~/.claude/projects/<folder>/<id>.jsonl with one user prompt and one reply,
# last changed <days ago> days back (default 0).
cc_session() {
  local f="$HOME/.claude/projects/$1/$2.jsonl"
  mkdir -p "$(dirname "$f")"
  printf '{"type":"user","message":{"role":"user","content":"%s"},"timestamp":"2026-10-01T10:00:00Z","cwd":"%s","sessionId":"%s"}\n' "$4" "$3" "$2" > "$f"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"cwd":"%s"}\n' "$3" >> "$f"
  age "$f" "${5:-0}"
}

# age <file> <days>: set the file's mtime to <days> days ago.
age() { python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2])*86400; os.utime(sys.argv[1],(t,t))' "$1" "$2"; }

# ids: the session ids in the finder's JSON on stdout, sorted, space-joined.
ids() { printf '%s' "$out" | python3 -c 'import json,sys; print(" ".join(sorted(s["id"] for s in json.load(sys.stdin)["sessions"])))'; }

t_ccf_lists_project_session() {
  ccf_home; cc_session -p-app s1 /p/app "fix the export"
  run python3 "$F" --project-dir /p/app --all --json
  eq exit 0 "$code"
  eq ids "s1" "$(ids)"
}

t_ccf_worktrees_in_window() {
  ccf_home
  cc_session -p-app s1 /p/app "fix the export"
  cc_session -p-app--claude-worktrees-x w1 /p/app/.claude/worktrees/x "add the button"
  mkdir -p "$HOME/.claude/projects/-p-app--claude-worktrees-x/w1/subagents"
  printf '{"type":"user","message":{"role":"user","content":"read"},"isSidechain":true}\n' \
    > "$HOME/.claude/projects/-p-app--claude-worktrees-x/w1/subagents/agent-a1.jsonl"
  cc_session -p-app old /p/app "fix the export" 5
  cc_session -p-app-two sib /p/app-two "fix the export"
  run python3 "$F" --project-dir /p/app --include-subdirs --days 3 --all --json --limit 0
  eq exit 0 "$code"
  eq ids "s1 w1" "$(ids)"
  eq subagents "agent-a1.jsonl" "$(printf '%s' "$out" | python3 -c 'import json,os,sys; s=[x for x in json.load(sys.stdin)["sessions"] if x["id"]=="w1"][0]; print(" ".join(os.path.basename(p) for p in s["subagents"]))')"
}

t_ccf_topic_in_window() {
  ccf_home
  cc_session -p-app s1 /p/app "fix the export"
  cc_session -p-app s2 /p/app "handoff retry"
  cc_session -p-app s3 /p/app "handoff loop" 5
  run python3 "$F" "handoff" --project-dir /p/app --days 3 --json
  eq exit 0 "$code"
  eq ids "s2" "$(ids)"
}

t_ccf_every_project() {
  ccf_home
  cc_session -p-app s1 /p/app "fix the export"
  cc_session -p-tool t1 /p/tool "add the flag"
  run python3 "$F" --all-projects --days 1 --all --json --limit 0
  eq exit 0 "$code"
  eq ids "s1 t1" "$(ids)"
  eq cwds "/p/app /p/tool" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(" ".join(sorted(s["cwd"] for s in json.load(sys.stdin)["sessions"])))')"
}

cases=(
  "finder lists a project session|t_ccf_lists_project_session"
  "finder lists every project|t_ccf_every_project"
  "finder lists worktree sessions inside the day window|t_ccf_worktrees_in_window"
  "finder ranks by topic inside the day window|t_ccf_topic_in_window"
)
