# sessions-codex-find.sh: the cases for the shared core's
# sessions/codex/find_session.py. The repo's test.sh sources this file after
# test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
F="$here/../sessions/codex/find_session.py"

# cof_home: a fresh temp folder T with HOME at $T/home, so the finder reads
# only the rollouts a case writes and keeps its index there too.
cof_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  export HOME="$T/home"
  mkdir -p "$HOME/.codex/sessions"
}

# co_rollout <id> <cwd> <prompt>: a rollout in today's day folder with one
# session_meta line and one user message.
co_rollout() {
  local d="$HOME/.codex/sessions/$(date +%Y/%m/%d)"
  mkdir -p "$d"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s","timestamp":"2026-10-01T10:00:00Z"}}\n' "$1" "$2" > "$d/rollout-2026-10-01T10-00-00-$1.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$3" >> "$d/rollout-2026-10-01T10-00-00-$1.jsonl"
}

# ids: the session ids in the finder's JSON on stdout, sorted, space-joined.
ids() { printf '%s' "$out" | python3 -c 'import json,sys; print(" ".join(sorted(s["id"] for s in json.load(sys.stdin)["sessions"])))'; }

t_cof_lists_project_session() {
  cof_home; co_rollout c1 /p/app "fix the export"
  run python3 "$F" --cwd /p/app --all --json
  eq exit 0 "$code"
  eq ids "c1" "$(ids)"
}

t_cof_each_cwd() {
  cof_home
  co_rollout c1 /p/app "fix the export"
  co_rollout c2 /wt/o/app/feat-x "add the button"
  co_rollout c3 /p/other "tidy the docs"
  run python3 "$F" --cwd /p/app --cwd /wt/o/app --include-subdirs --days 1 --all --json --limit 0
  eq exit 0 "$code"
  eq ids "c1 c2" "$(ids)"
}

t_cof_every_project() {
  cof_home
  co_rollout c1 /p/app "fix the export"
  co_rollout c2 /wt/o/app/feat-x "add the button"
  co_rollout c3 /p/other "tidy the docs"
  run python3 "$F" --all-projects --days 1 --all --json --limit 0
  eq exit 0 "$code"
  eq ids "c1 c2 c3" "$(ids)"
}

cases=(
  "finder lists a project session|t_cof_lists_project_session"
  "finder lists sessions under each cwd|t_cof_each_cwd"
  "finder lists every project|t_cof_every_project"
)
