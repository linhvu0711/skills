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

# co_rollout <id> <cwd> <prompt> [<source>]: a rollout in today's day folder
# with one session_meta line (source default `cli`; a JSON object goes in as
# it is) and one user message.
co_rollout() {
  local d="$HOME/.codex/sessions/$(date +%Y/%m/%d)"
  mkdir -p "$d"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s","timestamp":"2026-10-01T10:00:00Z","source":%s}}\n' "$1" "$2" "$(src "${4:-cli}")" > "$d/rollout-2026-10-01T10-00-00-$1.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$3" >> "$d/rollout-2026-10-01T10-00-00-$1.jsonl"
}

# src <source>: the source as JSON: an object as it is, a word quoted.
src() { case "$1" in "{"*) printf '%s' "$1" ;; *) printf '"%s"' "$1" ;; esac; }

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

t_cof_interactive_only() {
  cof_home
  co_rollout c1 /p/app "fix the export"
  co_rollout x1 /p/app "read the config" exec
  run python3 "$F" --cwd /p/app --interactive --all --json --limit 0
  eq exit 0 "$code"
  eq ids "c1" "$(ids)"
}

t_cof_helper_threads() {
  cof_home
  co_rollout c1 /p/app "fix the export"
  co_rollout h1 /p/app "read the config" '{"subagent":{"thread_spawn":{"parent_thread_id":"c1","depth":1}}}'
  run python3 "$F" --cwd /p/app --all --json --limit 0
  eq exit 0 "$code"
  eq ids "c1" "$(ids)"
  eq helpers "rollout-2026-10-01T10-00-00-h1.jsonl" "$(printf '%s' "$out" | python3 -c 'import json,os,sys; print(" ".join(os.path.basename(p) for p in json.load(sys.stdin)["sessions"][0]["subagents"]))')"
}

cases=(
  "finder lists a project session|t_cof_lists_project_session"
  "finder lists a session's helper threads|t_cof_helper_threads"
  "finder leaves out headless exec runs when asked|t_cof_interactive_only"
  "finder lists sessions under each cwd|t_cof_each_cwd"
  "finder lists every project|t_cof_every_project"
)
