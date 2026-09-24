#!/usr/bin/env bash
# kickoff.sh: open a herdr pane and run /plan-up there.
#
# Usage: kickoff.sh [--label L] [--dry-run] [--no-prompt] <issue-url> [#n ...] [on <pr-url>]
#
# <issue-url> #n ...: when the first issue has sub-issues it is the parent and
# the numbers are a run under it. When it has none, it is the first ticket of a
# set: plain issues with no shared parent, planned together in the order given.
#
# Exit 0: the pane is running /plan-up, one report line on stdout.
# Exit 1: something stopped us; the reason is the last line on stderr.
# Nothing is half done: no pane exists until the tree check passed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
map="${KICKOFF_REPO_MAP:-$HOME/.config/kickoff/repos.tsv}"
dev_root="${KICKOFF_DEV_ROOT:-$HOME/development}"

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*" >&2; }

# ---------- args ----------
label=""; dry_run=0; no_prompt=0; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-prompt) no_prompt=1; shift ;;
    *) args+=("$1"); shift ;;
  esac
done
[ "${#args[@]}" -ge 1 ] || die "usage: kickoff.sh <issue-url> [#n ...] [on <pr-url>]  (#n after a plain issue = a set, no parent needed)"

issue_url="${args[0]}"
[[ "$issue_url" =~ ^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)/?$ ]] \
  || die "first argument must be a GitHub issue URL, got: $issue_url"
owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
slug="$owner/$repo"

pr_url=""; tickets=()
i=1
while [ $i -lt "${#args[@]}" ]; do
  a="${args[$i]}"
  if [ "$a" = "on" ]; then
    pr_url="${args[$((i+1))]:-}"
    [[ "$pr_url" =~ ^https://github\.com/$owner/$repo/pull/([0-9]+)/?$ ]] \
      || die "'on' needs a PR URL in $slug, got: ${pr_url:-nothing}"
    pr_number="${BASH_REMATCH[1]}"
    i=$((i+2))
  elif [[ "$a" =~ ^#?([0-9]+)$ ]]; then
    tickets+=("${BASH_REMATCH[1]}"); i=$((i+1))
  else
    die "unexpected argument: $a"
  fi
done
prep_args="${args[*]}"

# ---------- issue ----------
issue_json="$(gh issue view "$number" --repo "$slug" --json number,title,labels,subIssues,state)" \
  || die "gh could not read $issue_url"
title="$(jq -r .title <<<"$issue_json")"
sub_count="$(jq '.subIssues.nodes | length' <<<"$issue_json")"

if [ -n "$pr_url" ]; then form="on"
elif [ "${#tickets[@]}" -gt 0 ]; then
  if [ "$sub_count" -gt 0 ]; then form="run"; else form="set"; fi
elif [ "$sub_count" -gt 0 ]; then form="epic"
else form="issue"; fi

# ---------- effort ----------
# medium only for a single ticket whose size label says XS or S.
is_small=0
if [ "$form" = "issue" ] || [ "$form" = "on" ]; then
  while IFS= read -r lab; do
    norm="$(printf '%s' "$lab" | tr '[:upper:]' '[:lower:]' | sed -E 's/(size|scope|effort)//g; s/[^a-z]//g')"
    case "$norm" in xs|s|small|extrasmall|xsmall) is_small=1 ;; esac
  done < <(jq -r '.labels[].name' <<<"$issue_json")
fi
if [ "$is_small" -eq 1 ]; then effort="medium"; rule="size XS/S"
else effort="high"; case "$form" in run) rule="run" ;; set) rule="set of tickets" ;; epic) rule="whole epic" ;; *) rule="size above S or no size label" ;; esac; fi

# ---------- base ----------
if [ -n "$pr_url" ]; then
  base="$(gh pr view "$pr_number" --repo "$slug" --json headRefName -q .headRefName)" || die "gh could not read $pr_url"
else
  base="$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name)" || die "gh could not read repo $slug"
fi

# ---------- repo path ----------
origin_slug() {  # prints owner/repo of a checkout's origin, or nothing
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 0
  printf '%s' "$url" | sed -E 's#^(git@|https://|ssh://git@)github\.com[:/]##; s#\.git$##; s#/$##'
}
is_main_checkout() { [ -d "$1/.git" ]; }  # a .git file is a worktree

path=""; path_from=""
# 1. the map
if [ -f "$map" ]; then
  cand="$(awk -F'\t' -v s="$slug" '$1==s {print $2; exit}' "$map")"
  if [ -n "$cand" ]; then
    if is_main_checkout "$cand" && [ "$(origin_slug "$cand")" = "$slug" ]; then
      path="$cand"; path_from="map"
    else
      say "map entry for $slug is stale ($cand), dropping it"
      tmp="$(mktemp)"; awk -F'\t' -v s="$slug" '$1!=s' "$map" >"$tmp"; mv "$tmp" "$map"
    fi
  fi
fi
# 2. the pane's cwd
if [ -z "$path" ] && is_main_checkout "$PWD" && [ "$(origin_slug "$PWD")" = "$slug" ]; then
  path="$PWD"; path_from="cwd"
fi
# 3. search ~/development
if [ -z "$path" ]; then
  matches=()
  while IFS= read -r gitdir; do
    d="${gitdir%/.git}"
    [ "$(origin_slug "$d")" = "$slug" ] && matches+=("$d")
  done < <(find "$dev_root" -maxdepth 6 -type d -name .git -not -path '*/node_modules/*' 2>/dev/null)
  case "${#matches[@]}" in
    0) die "no checkout of $slug under $dev_root. Clone it, or add a line to $map: $slug<TAB>/path" ;;
    1) path="${matches[0]}"; path_from="search" ;;
    *) die "several checkouts of $slug: ${matches[*]}. Add the right one to $map: $slug<TAB>/path" ;;
  esac
fi
if [ "$path_from" != "map" ]; then
  mkdir -p "$(dirname "$map")"
  printf '%s\t%s\n' "$slug" "$path" >>"$map"
fi

# ---------- tree ----------
dirty="$(git -C "$path" status --porcelain)"
[ -z "$dirty" ] || die "dirty tree in $path:"$'\n'"$dirty"$'\n'"Commit or stash, then run /kickoff again."
tree_note="tree clean on $base"
current="$(git -C "$path" branch --show-current)"
if [ "$current" != "$base" ]; then
  git -C "$path" fetch --quiet origin "$base" 2>/dev/null || true
  git -C "$path" checkout --quiet "$base" || die "could not check out $base in $path"
  tree_note="switched $current -> $base"
fi
git -C "$path" pull --quiet --ff-only || die "git pull --ff-only failed in $path on $base"

# ---------- label ----------
if [ -z "$label" ]; then
  label="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/ /g' \
    | awk '{n=0; for(i=1;i<=NF;i++){ if($i ~ /^[0-9]+$/) continue; if(n>0) printf "-"; printf "%s",$i; n++; if(n==4) break } }')"
  case "$form" in
    run|epic|set) label="${label}-run" ;;
    on) label="${label}-on-${pr_number}" ;;
  esac
fi
label="$(printf '%s' "$label" | sed -E 's/^[^a-z]+//; s/[^a-z0-9_-]//g' | cut -c1-32)"
[ -n "$label" ] || label="prep-$number"

# ---------- herdr ----------
[ "${HERDR_ENV:-}" = 1 ] || die "not inside herdr"
ws="${HERDR_WORKSPACE_ID:?}"; my_tab="${HERDR_TAB_ID:?}"

# unique agent name
live="$(herdr agent list | jq -r '.result.agents[].name // empty')"
if grep -qx "$label" <<<"$live"; then
  n=2; while grep -qx "${label}-${n}" <<<"$live"; do n=$((n+1)); done
  label="${label}-${n}"
fi

panes_json="$(herdr pane list --workspace "$ws")"
tab_ids="$(herdr tab list --workspace "$ws" | jq -r '.result.tabs[].tab_id')"

columns_of() {  # prints "<count> <rightmost pane id>" for a tab
  local any
  any="$(jq -r --arg t "$1" '[.result.panes[] | select(.tab_id==$t)][0].pane_id // empty' <<<"$panes_json")"
  [ -n "$any" ] || { echo "0 "; return; }
  herdr pane layout --pane "$any" | jq -r '.result.layout.panes
    | ([.[].rect.x] | unique | length) as $n
    | (max_by(.rect.x).pane_id) as $r
    | "\($n) \($r)"'
}

target_tab=""; split_pane=""
read -r n r <<<"$(columns_of "$my_tab")"
if [ "$n" -gt 0 ] && [ "$n" -lt 3 ]; then target_tab="$my_tab"; split_pane="$r"; fi
if [ -z "$target_tab" ]; then
  best=9
  for t in $tab_ids; do
    [ "$t" = "$my_tab" ] && continue
    read -r n r <<<"$(columns_of "$t")"
    if [ "$n" -gt 0 ] && [ "$n" -lt 3 ] && [ "$n" -lt "$best" ]; then best=$n; target_tab="$t"; split_pane="$r"; fi
  done
fi

if [ "$dry_run" -eq 1 ]; then
  place="new tab"; [ -n "$target_tab" ] && place="split $split_pane in $target_tab"
  printf 'dry-run: #%s %s · form %s · effort %s (%s) · base %s · repo %s (%s) · %s · label %s · %s · prep args: %s\n' \
    "$number" "$title" "$form" "$effort" "$rule" "$base" "$path" "$path_from" "$tree_note" "$label" "$place" "$prep_args"
  exit 0
fi

if [ -n "$target_tab" ]; then
  new_pane="$(herdr pane split --pane "$split_pane" --direction right --ratio 0.5 --cwd "$path" --no-focus | jq -r .result.pane.pane_id)"
  python3 "$here/equalize_columns.py" "$new_pane" >/dev/null
  placed="split in $target_tab"
else
  created="$(herdr tab create --workspace "$ws" --cwd "$path" --label "$label" --no-focus)"
  new_pane="$(jq -r .result.root_pane.pane_id <<<"$created")"
  target_tab="$(jq -r .result.tab.tab_id <<<"$created")"
  placed="new tab $target_tab"
fi
herdr pane rename "$new_pane" "$label" >/dev/null

# A fresh pane's shell takes a moment to reach its prompt; herdr answers
# agent_pane_busy until then. Retry on that one error only.
started=0
for _ in $(seq 1 20); do
  if err="$(herdr agent start "$label" --kind claude --pane "$new_pane" --timeout 60000 \
      -- --effort "$effort" --permission-mode auto 2>&1 >/dev/null)"; then
    started=1; break
  fi
  grep -q agent_pane_busy <<<"$err" || { say "$err"; break; }
  sleep 1
done
[ "$started" -eq 1 ] || die "claude did not come up in $new_pane; the pane is left as is"

if [ "$no_prompt" -eq 1 ]; then
  printf '#%s %s → %s/%s/%s · effort %s (%s) · %s · %s · no prompt sent\n' \
    "$number" "$title" "$ws" "$target_tab" "$new_pane" "$effort" "$rule" "$tree_note" "$placed"
  exit 0
fi

herdr agent prompt "$label" "/plan-up $prep_args" >/dev/null
status="idle"
for _ in $(seq 1 30); do
  status="$(herdr agent get "$label" | jq -r .result.agent.agent_status)"
  [ "$status" = "working" ] && break
  sleep 0.5
done
if [ "$status" != "working" ]; then
  herdr agent read "$label" --source visible --lines 40 >&2 || true
  die "/plan-up did not start in $new_pane (status $status); the pane is left as is"
fi

printf '#%s %s → %s/%s/%s · effort %s (%s) · %s · %s\n' \
  "$number" "$title" "$ws" "$target_tab" "$new_pane" "$effort" "$rule" "$tree_note" "$placed"
