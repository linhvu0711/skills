#!/usr/bin/env bash
# kickoff.sh: get /ship-ready, /ship-full, or /plan-up ready to start in a new
# T3 Code thread.
#
# Usage: kickoff.sh [--label L] [--model M] [--effort E] [--command ship-ready|ship-full|plan-up]
#                   [--size n=SIZE ...] <issue-url> [#n ...] [on <pr-url>]
#
# The target and the flags are the shared decide script's, which picks the
# model, effort, and command. This script checks it runs inside T3 Code and
# makes the repo's checkout a T3 project when it is not one yet. The agent
# starts the thread with T3's t3_thread_launch tool: `t3 thread start` takes
# no effort and no runtime mode, and a script cannot call T3's tools.
#
# Exit 0: one JSON line on stdout, the decide line plus message, thread_title,
# runtime_mode, and project (`found` or `added`).
# Exit 1: something stopped us; the reason is the last line on stderr, and
# stdout is empty. A project this run added stays added.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

# ---------- T3 ----------
[ -n "${T3CODE_CLI_PATH:-}" ] && command -v t3 >/dev/null || die "not inside T3 Code"

# ---------- decide ----------
# The shared decide script reads the target and flags; its stop line is ours.
decided="$(bash "$here/../../../shared/kickoff/decide.sh" "$@")" || exit 1
path="$(jq -r .path <<<"$decided")"

# ---------- project ----------
# `t3 thread list --project` fails for a folder that is no T3 project, so it
# checks before the add, and a second run adds nothing.
is_project() { t3 thread list --project "$path" --json >/dev/null 2>&1; }
project=found
if ! is_project; then
  err="$(t3 project add "$path" 2>&1 >/dev/null)" || die "could not add $path as a T3 project: $(tail -1 <<<"$err")"
  is_project || die "could not add $path as a T3 project: t3 still finds no project there"
  project=added
fi

jq -c --arg project "$project" \
  '. + {message: "/\(.command) \(.args)", thread_title: "\(.label) \(.title)", runtime_mode: "auto", project: $project}' \
  <<<"$decided"
