#!/usr/bin/env bash
# project.sh: make a checkout a T3 project when it is not one yet. Shared by
# kickoff-t3's kickoff.sh and orchestrate.sh.
#
#   project.sh <path>
#
# Exit 0: `found` or `added`, one line. Exit 1: something stopped us; the
# reason is the last line on stderr. A project it added stays added.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
path="$1"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

t3="$(bash "$here/../t3-cli.sh")" || exit 1

# `t3 thread list --project` fails for a folder that is no T3 project, so it
# checks before the add, and a second run adds nothing.
is_project() { "$t3" thread list --project "$path" --json >/dev/null 2>&1; }
if is_project; then echo found; exit 0; fi
err="$("$t3" project add "$path" 2>&1 >/dev/null)" || die "could not add $path as a T3 project: $(tail -1 <<<"$err")"
is_project || die "could not add $path as a T3 project: t3 still finds no project there"
echo added
