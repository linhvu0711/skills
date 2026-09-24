#!/usr/bin/env bash
# pr-facts.sh: the facts of one PR, one KEY=value per line.
#
#   pr-facts.sh [<number|url|branch>] [--repo owner/repo]
#
# No argument: the PR of the current branch. Keys: REPO NUMBER URL TITLE
# STATE FORK BASE HEAD SHA AUTHOR MERGEABLE MERGE_STATE DEVIN CHECKS_RED
# CHECKS_PENDING CHECKS_GREEN. DEVIN is the `Devin Review` state on the
# head commit (SUCCESS, PENDING, FAILURE, ERROR) or `none`. The CHECKS_*
# counts cover every other status and check run on the head commit.
set -euo pipefail

ref=""; repo=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=(--repo "${2:-}"); shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 1 ;;
    *) ref="$1"; shift ;;
  esac
done

json="$(gh pr view ${ref:+"$ref"} "${repo[@]}" --json number,url,title,state,isCrossRepository,baseRefName,headRefName,headRefOid,author,mergeable,mergeStateStatus,statusCheckRollup 2>&1)" \
  || { printf 'stop: %s\n' "$json" >&2; exit 1; }

jq -r '
  def st: (.state // .conclusion // .status // "UNKNOWN") | ascii_upcase;
  def is_devin: ((.context // .name // "") == "Devin Review");
  def others: [.statusCheckRollup[]? | select(is_devin | not)];
  def red: ["FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"];
  def green: ["SUCCESS","NEUTRAL","SKIPPED"];
  "REPO=" + (.url | capture("github\\.com/(?<r>[^/]+/[^/]+)/pull").r),
  "NUMBER=\(.number)",
  "URL=\(.url)",
  "TITLE=\(.title)",
  "STATE=\(.state)",
  "FORK=\(.isCrossRepository)",
  "BASE=\(.baseRefName)",
  "HEAD=\(.headRefName)",
  "SHA=\(.headRefOid)",
  "AUTHOR=\(.author.login)",
  "MERGEABLE=\(.mergeable)",
  "MERGE_STATE=\(.mergeStateStatus)",
  "DEVIN=" + (([.statusCheckRollup[]? | select(is_devin) | st] | first) // "none"),
  "CHECKS_RED=" + ([others[] | select(st as $s | red | index($s))] | length | tostring),
  "CHECKS_PENDING=" + ([others[] | select(st as $s | (red + green) | index($s) | not)] | length | tostring),
  "CHECKS_GREEN=" + ([others[] | select(st as $s | green | index($s))] | length | tostring)
' <<<"$json"
