#!/usr/bin/env bash
# t3-cli.sh: name the t3 command of the T3 Code chat this runs in. T3 Code
# sets T3CODE_CLI_PATH to its own t3 in every chat, so that is the t3 to run,
# whether or not one is on PATH. Shared by orchestrate.sh and kickoff-t3's
# kickoff.sh.
#
#   t3-cli.sh
#
# Exit 0: the path, one line. Exit 1: `stop: not inside T3 Code` on stderr.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

t3="${T3CODE_CLI_PATH:-}"
[ -n "$t3" ] && [ -x "$t3" ] || die "not inside T3 Code"
printf '%s\n' "$t3"
