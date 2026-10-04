# handoff.sh: the cases for this skill's handoff module, driven through a
# fake adapter. The repo's test.sh sources this file after test-lib.sh and
# runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_adapters: a fake devin and cursor adapter in $T/adapters (T made when
# not set yet), HANDOFF_ADAPTERS pointing there, and HOME in the temp folder,
# so the ledger is $T/home/.config/dispatch/handoff.tsv. cd into T. The fake
# takes its name from its file and its verb from $1, and answers from fixture
# files in $FAKE_AD, by route <name>.<verb>: each route counts its calls in
# <route>.calls and logs the args after the verb in <route>.args, one line per
# call. Call n prints <route>.<n>.fail or <route>.fail to stderr and fails when
# one exists, else prints <route>.<n>.out or <route>.out.
fake_adapters() {
  [ -n "${T:-}" ] || T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/adapters" "$T/ad" "$T/home"
  cat > "$T/adapters/devin.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0" .sh)"; verb="$1"; shift
key="$name.$verb"
n=$(( $(cat "$FAKE_AD/$key.calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_AD/$key.calls"
printf '%s\n' "$*" >> "$FAKE_AD/$key.args"
for f in "$FAKE_AD/$key.$n.fail" "$FAKE_AD/$key.fail"; do
  if [ -f "$f" ]; then cat "$f" >&2; exit 1; fi
done
f="$FAKE_AD/$key.$n.out"; [ -f "$f" ] || f="$FAKE_AD/$key.out"
cat "$f"
EOF
  cp "$T/adapters/devin.sh" "$T/adapters/cursor.sh"
  export HANDOFF_ADAPTERS="$T/adapters" FAKE_AD="$T/ad" HOME="$T/home"
  cd "$T"
}

handoff() { run bash "$here/../scripts/handoff.sh" "$@"; }

# ledger: the ledger's path, its folder made.
ledger() { mkdir -p "$HOME/.config/dispatch"; printf '%s' "$HOME/.config/dispatch/handoff.tsv"; }

issue12="https://github.com/o/r/issues/12"
row_devin12="2026-10-01T10:00:00Z	devin	devin-a	https://app.devin.ai/sessions/a	$issue12	#12 Export"
row_cursor12="2026-10-02T10:00:00Z	cursor	bc-1	https://cursor.com/agents/bc-1	$issue12	#12 Export"

t_start_records_row() {
  fake_adapters
  printf 'devin-abc\thttps://app.devin.ai/sessions/abc\n' > "$FAKE_AD/devin.start.out"
  printf '# Brief\n' > p.md
  handoff start devin p.md --issue "$issue12" --title "#12 Export"
  eq exit 0 "$code"
  eq ledger "devin	devin-abc	https://app.devin.ai/sessions/abc	$issue12	#12 Export" "$(cut -f2- "$(ledger)")"
}

t_start_passes_options() {
  fake_adapters
  printf 'bc-1\thttps://cursor.com/agents/bc-1\n' > "$FAKE_AD/cursor.start.out"
  printf '# Brief\n' > p.md
  handoff start cursor p.md --issue "$issue12" --title "#12 Export" --repo o/r --base main
  eq exit 0 "$code"
  eq "adapter args" "p.md --title #12 Export --repo o/r --base main" "$(cat "$FAKE_AD/cursor.start.args")"
}

t_unknown_executor() {
  fake_adapters
  printf '# Brief\n' > p.md
  handoff start foo p.md --issue "$issue12"
  eq exit 1 "$code"
  eq stderr "handoff.sh: executor must be devin or cursor" "$err"
}

t_failed_start_keeps_ledger() {
  fake_adapters
  row="2026-10-01T10:00:00Z	devin	devin-a	https://app.devin.ai/sessions/a	https://github.com/o/r/issues/11	#11 Old"
  printf '%s\n' "$row" > "$(ledger)"
  printf 'devin.sh: HTTP 400 on POST /sessions: platform must be one of linux, macos\n' > "$FAKE_AD/devin.start.fail"
  printf '# Brief\n' > p.md
  handoff start devin p.md --issue "$issue12" --title "#12 Export" --platform mac
  eq exit 1 "$code"
  eq stderr "devin.sh: HTTP 400 on POST /sessions: platform must be one of linux, macos" "$err"
  eq ledger "$row" "$(cat "$(ledger)")"
}

cases=(
  "start records the session in the ledger|t_start_records_row"
  "start passes adapter options through|t_start_passes_options"
  "unknown executor stops|t_unknown_executor"
  "a failed start leaves the ledger as it was|t_failed_start_keeps_ledger"
)
