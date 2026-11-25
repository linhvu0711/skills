# sessions-find-all.sh: the cases for the shared core's sessions/find_all.py.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
S="$here/../sessions/find_all.py"

# fa_home: a fresh HOME with one Claude session and one Codex rollout of
# /p/app, both changed today, and no Antigravity folder.
fa_home() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$T/home"
  mkdir -p "$HOME/.claude/projects/-p-app"
  printf '{"type":"user","message":{"role":"user","content":"fix the export"},"timestamp":"2026-10-01T10:00:00Z","cwd":"/p/app","sessionId":"s1"}\n' > "$HOME/.claude/projects/-p-app/s1.jsonl"
  local d="$HOME/.codex/sessions/$(date +%Y/%m/%d)"; mkdir -p "$d"
  printf '{"type":"session_meta","payload":{"id":"c1","cwd":"/p/app","timestamp":"2026-10-01T10:00:00Z","source":"cli"}}\n' > "$d/rollout-2026-10-01T10-00-00-c1.jsonl"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add the flag"}]}}\n' >> "$d/rollout-2026-10-01T10-00-00-c1.jsonl"
}

# fa_fake <finder body>: a copy of the sessions folder at $T/sessions with one
# more harness, `fake`, whose finder is a Python script with this body.
fa_fake() {
  cp -R "$here/../sessions" "$T/sessions"; mkdir -p "$T/sessions/fake"
  cat > "$T/sessions/fake/adapter.py" <<'EOF'
import importlib.util, os
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("adapter_lib", os.path.join(here, "..", "adapter_lib.py"))
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)
HARNESS = lib.Harness(name="fake", label="Fake", data=[here], finder=os.path.join(here, "finder.py"),
                      extractor="", flags=lambda roots, days: [], title=lambda s: s.get("first_prompt") or "",
                      current="", extract_flags=())
EOF
  printf '%s\n' "$1" > "$T/sessions/fake/finder.py"
}

# days_ago <n>: the local date n days back, YYYY-MM-DD.
days_ago() { python3 -c 'import datetime as d,sys; print(d.date.today()-d.timedelta(days=int(sys.argv[1])))' "$1"; }

# harnesses: each harness as `<harness> <installed> <ids of its rows>`, one per line.
harnesses() {
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for h in d["harnesses"]:
    ids = [r["id"] for r in d["sessions"] if r["harness"] == h["harness"]]
    print(" ".join([h["harness"], str(h["installed"])] + ids))'
}

t_fa_lists_harnesses() {
  # Given: a Claude session and a Codex rollout of /p/app, no Antigravity
  fa_home
  # When
  run python3 "$S" --root /p/app
  # Then
  eq harnesses "antigravity False
claude True s1
codex True c1" "$(harnesses)"
}

t_fa_window() {
  # Given: s1 changed today, s2 changed 30 days ago
  fa_home
  local f="$HOME/.claude/projects/-p-app/s2.jsonl"
  printf '{"type":"user","message":{"role":"user","content":"tidy the docs"},"timestamp":"2026-10-01T10:00:00Z","cwd":"/p/app","sessionId":"s2"}\n' > "$f"
  python3 -c 'import os,sys,time; t=time.time()-30*86400; os.utime(sys.argv[1],(t,t))' "$f"
  # When
  run python3 "$S" --root /p/app --since "$(days_ago 7)"
  # Then
  eq claude "claude True s1" "$(harnesses | grep '^claude ')"
}

t_fa_names_no_adapter_harness() {
  # Given: OpenCode's database, changed today
  fa_home; mkdir -p "$HOME/.local/share/opencode"; : > "$HOME/.local/share/opencode/opencode.db"
  # When
  run python3 "$S" --root /p/app --since "$(date +%F)"
  # Then
  has unread '"line": "found OpenCode sessions, cannot read them yet"' "$out"
}

t_fa_finder_runs_once() {
  # Given: a fake harness whose finder counts its runs
  fa_home
  fa_fake 'import json, os, time
here = os.path.dirname(os.path.abspath(__file__))
open(os.path.join(here, "runs"), "a").write("run\n")
print(json.dumps({"sessions": [{"id": "f1", "modified": time.time(), "cwd": "/p/app", "n_prompts": 1, "first_prompt": "hi", "age": "0m ago"}]}))'
  # When
  run python3 "$T/sessions/find_all.py" --root /p/app
  # Then
  eq runs "1 fake True f1" "$(wc -l < "$T/sessions/fake/runs" | tr -d ' ') $(harnesses | grep '^fake ')"
}

t_fa_failed_harness() {
  # Given: a fake harness whose finder fails, and a Claude session
  fa_home
  fa_fake 'import sys
print("boom", file=sys.stderr)
sys.exit(1)'
  # When
  run python3 "$T/sessions/find_all.py" --root /p/app
  # Then
  eq result '0 {"harness": "fake", "label": "Fake", "installed": true, "error": "fake finder failed: boom"} claude True s1' "$code $(printf '%s' "$out" | python3 -c 'import json,sys; print(json.dumps([h for h in json.load(sys.stdin)["harnesses"] if h["harness"] == "fake"][0]))') $(harnesses | grep '^claude ')"
}

t_fa_not_utf8() {
  # Given: a fake harness whose finder prints bytes that are not UTF-8, and a Claude session
  fa_home
  fa_fake 'import sys
sys.stdout.buffer.write(b"caf\xe9\n")'
  # When
  run python3 "$T/sessions/find_all.py" --root /p/app
  # Then
  eq result '0 {"harness": "fake", "label": "Fake", "installed": true, "error": "fake finder failed: output is not UTF-8"} claude True s1' "$code $(printf '%s' "$out" | python3 -c 'import json,sys; print(json.dumps([h for h in json.load(sys.stdin)["harnesses"] if h["harness"] == "fake"][0]))') $(harnesses | grep '^claude ')"
}

t_fa_other_io_encoding() {
  # Given: a Claude session whose prompt has an é and an emoji, a Codex rollout, and a Latin-1 PYTHONIOENCODING
  fa_home
  printf '{"type":"user","message":{"role":"user","content":"export café 🚀"},"timestamp":"2026-10-01T10:00:00Z","cwd":"/p/app","sessionId":"s1"}\n' > "$HOME/.claude/projects/-p-app/s1.jsonl"
  # When
  PYTHONIOENCODING=latin-1 run python3 "$S" --root /p/app
  # Then
  eq rows "export café 🚀 codex" "$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1], encoding="latin-1"))["sessions"]; print(s[0]["first_prompt"], s[1]["harness"])' "$T/out")"
}

cases=(
  "find-all lists every harness and its sessions|t_fa_lists_harnesses"
  "find-all keeps to the window|t_fa_window"
  "find-all names a harness with data and no adapter|t_fa_names_no_adapter_harness"
  "find-all runs each harness's finder once|t_fa_finder_runs_once"
  "find-all keeps a failed harness's error and lists the rest|t_fa_failed_harness"
  "find-all fails only the harness whose finder output is not UTF-8|t_fa_not_utf8"
  "find-all reads and writes every character under a Latin-1 PYTHONIOENCODING|t_fa_other_io_encoding"
)
