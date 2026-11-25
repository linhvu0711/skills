#!/usr/bin/env bash
# kickoff.sh: get /ship ready to start in a new T3 Code thread.
#
# Usage: kickoff.sh [--label L] [--model M] [--effort E]
#                   [--command ship|triage|grill|ready-pr|complete-task] [--mode review|ready|merge]
#                   [--size n=SIZE ...] <issue-url> [#n ...] [on <pr-url>]
#
# The target and the flags are the shared decide script's, which picks the
# model, effort, and command. This script checks it runs inside T3 Code and
# makes the repo's checkout a T3 project when it is not one yet. The agent
# starts the thread with T3's t3_thread_launch tool: `t3 thread start` takes
# no effort, and a script cannot call T3's tools.
#
# Exit 0: one JSON line on stdout, the decide line (its message is the
# thread's first prompt) plus thread_title and project
# (`found` or `added`).
# Exit 1: something stopped us; the reason is the last line on stderr, and
# stdout is empty. A project this run added stays added.
# Exit 2 or 64, from decide.sh: gh could not read GitHub, or a wrong command
# line, with its `stop:` line on stderr.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ---------- T3 ----------
# The shared T3 lookup names the chat's t3 command, or stops outside T3.
bash "$here/../../../shared/t3-cli.sh" >/dev/null || exit 1

# ---------- decide ----------
# The shared decide script reads the target and flags; its stop line is ours.
decided="$(bash "$here/../../../shared/kickoff/decide.sh" "$@")" || exit
path="$(jq -r .path <<<"$decided")"

# ---------- project ----------
project="$(bash "$here/../../../shared/kickoff/project.sh" "$path")" || exit 1

jq -c --arg project "$project" \
  '. + {thread_title: "\(.heading) \(.title)", project: $project}' \
  <<<"$decided"
