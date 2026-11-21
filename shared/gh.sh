# gh.sh: the one way a shell script of the shared core or a skill runs gh.
# Source it; it defines functions and runs nothing.
#
# gh prints hints on stderr beside a good answer, and jq cannot read them, so
# stderr stays out of the answer. On a failure the error is gh's last line;
# the first is often a hint, such as `A new release of gh is available`.
#
# gh_out <args>: runs `gh <args>`. Exit 0: its stdout in `out`, return 0.
# Else the last non-empty line of its stderr in `err` (`gh exited <n>` when it
# printed none), return 1.
gh_out() {
  local f rc=0
  f="$(mktemp)"
  out="$(gh "$@" 2>"$f")" || rc=$?
  if [ "$rc" -eq 0 ]; then rm -f "$f"; return 0; fi
  err="$(awk 'NF {l = $0} END {print l}' "$f")"
  rm -f "$f"
  [ -n "$err" ] || err="gh exited $rc"
  return 1
}

# gh_or_stop <args>: gh_out, and on a failure `stop: gh failed: <err>` on
# stderr and exit 1.
gh_or_stop() {
  gh_out "$@" || { printf 'stop: gh failed: %s\n' "$err" >&2; exit 1; }
}
