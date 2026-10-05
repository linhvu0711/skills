# sessions-claude-extract.sh: the cases for the shared core's
# sessions/claude/extract_session.py. The repo's test.sh sources this file
# after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
X="$here/../sessions/claude/extract_session.py"

t_cce_helper_log_by_path() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  local f="$HOME/.claude/projects/-p-app/s1/subagents/agent-a1.jsonl"
  mkdir -p "$(dirname "$f")"
  printf '{"type":"user","message":{"role":"user","content":"read the config"},"isSidechain":true}\n' > "$f"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"found it"}]},"isSidechain":true}\n' >> "$f"
  run python3 "$X" "$f" --summary
  eq exit 0 "$code"
  has prompt "read the config" "$out"
  has reply "found it" "$out"
}

cases=(
  "extractor reads a helper log by path|t_cce_helper_log_by_path"
)
