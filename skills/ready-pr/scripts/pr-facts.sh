#!/usr/bin/env bash
# pr-facts.sh: the facts of one PR, one KEY=value per line.
#
#   pr-facts.sh [<number|url|branch>] [--repo owner/repo]
#
# No argument: the PR of the current branch. Keys: REPO NUMBER URL TITLE
# STATE DRAFT FORK BASE HEAD SHA AUTHOR MERGEABLE MERGE_STATE REVIEW_DECISION
# DEVIN CHECKS_RED CHECKS_PENDING CHECKS_GREEN REQUIRED_MISSING. DRAFT is
# true or false. REVIEW_DECISION is APPROVED, CHANGES_REQUESTED,
# REVIEW_REQUIRED, or empty when the repo asks for no review. DEVIN is the
# `Devin Review` state on the head commit (SUCCESS, PENDING, FAILURE, ERROR)
# or `none`. The CHECKS_* counts cover every other status and check run on
# the head commit. REQUIRED_MISSING lists, comma separated, the checks that
# the base branch requires (branch protection and rulesets) and the head
# does not have at all; empty when none is missing.
set -euo pipefail

ref=""; repo=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=(--repo "${2:-}"); shift 2 ;;
    -*) printf 'stop: unknown flag %s\n' "$1" >&2; exit 1 ;;
    *) ref="$1"; shift ;;
  esac
done

json="$(gh pr view ${ref:+"$ref"} "${repo[@]}" --json number,url,title,state,isDraft,isCrossRepository,baseRefName,headRefName,headRefOid,author,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup 2>&1)" \
  || { printf 'stop: %s\n' "$json" >&2; exit 1; }

# The checks the base requires, from branch protection and from rulesets.
# Both read with plain read access; a repo with neither gives [].
r="$(jq -r '.url | capture("github\\.com/(?<r>[^/]+/[^/]+)/pull").r' <<<"$json")"
base="$(jq -r .baseRefName <<<"$json")"
prot="$(gh api "repos/$r/branches/$base" -q '.protection.required_status_checks.contexts // []' 2>&1)" \
  || { printf 'stop: %s\n' "$prot" >&2; exit 1; }
rules="$(gh api "repos/$r/rules/branches/$base" -q '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' 2>&1)" \
  || { printf 'stop: %s\n' "$rules" >&2; exit 1; }

jq -r --argjson prot "$prot" --argjson rules "$rules" '
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
  "DRAFT=\(.isDraft)",
  "FORK=\(.isCrossRepository)",
  "BASE=\(.baseRefName)",
  "HEAD=\(.headRefName)",
  "SHA=\(.headRefOid)",
  "AUTHOR=\(.author.login)",
  "MERGEABLE=\(.mergeable)",
  "MERGE_STATE=\(.mergeStateStatus)",
  "REVIEW_DECISION=\(.reviewDecision // "")",
  "DEVIN=" + (([.statusCheckRollup[]? | select(is_devin) | st] | first) // "none"),
  "CHECKS_RED=" + ([others[] | select(st as $s | red | index($s))] | length | tostring),
  "CHECKS_PENDING=" + ([others[] | select(st as $s | (red + green) | index($s) | not)] | length | tostring),
  "CHECKS_GREEN=" + ([others[] | select(st as $s | green | index($s))] | length | tostring),
  "REQUIRED_MISSING=" + ([.statusCheckRollup[]? | .context // .name] as $have
    | ($prot + $rules) | unique | map(select(. as $c | $have | index($c) | not)) | join(","))
' <<<"$json"
