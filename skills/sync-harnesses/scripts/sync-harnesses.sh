#!/usr/bin/env bash
# sync-harnesses.sh: check that Claude Code, Codex, and Antigravity on this
# Mac have the repo's skills and subagents and the owner's rules and gates,
# and that Devin in T3 answers on its home models.
#
#   sync-harnesses.sh
#
# First it runs the repo's link.sh, which remakes every missing link, then
# `link.sh --status`, which names each link and file and where it is. Then
# it prints one line per harness with its counts, one line for Devin in T3,
# one `fixed:` line per link link.sh made, one `problem:` line per thing
# still missing or a model no list offers, and one `skip:` line per check it
# could not run. Exit 1 when a problem line printed, else 0. Every install
# path comes from link.sh's status lines, so its env settings hold; the
# rules files and the model lists come from HOME.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../../.." && pwd -P)"

shared_rules="$HOME/.agents/rules/shared.md"
claude_md="$HOME/.claude/CLAUDE.md"
codex_md="$HOME/.codex/AGENTS.md"
gemini_md="$HOME/.gemini/GEMINI.md"

# The owner's personal gates, wired in every harness, and the repo's
# subagent gate. Antigravity also runs session-rules, since T3 starts its
# chats without the rules file.
personal_gates="write-for-agents-gate unslop-gate unslop-commit-gate question-gate plain-style"

problems=(); fixed=(); link_problems=()

# tilde <text>: the text with $HOME/ written as ~/. The ~/ sits in a
# variable, since Bash 3.2 keeps the backslash of a literal \~/.
tilde() { local t='~/'; printf '%s' "${1//"$HOME"\//$t}"; }

problem() { problems+=("problem: $(tilde "$1")"); }

agents=()
for f in "$root"/skills/*/agents/*.md "$root"/shared/agents/*.md; do
  [ -f "$f" ] && agents+=("${f#"$root"/}")
done

# link.sh is the one writer of links, and the one that knows where each
# goes. Its stdout names each change; --status names each target's state.
lout="$(mktemp)"; lerr="$(mktemp)"; trap 'rm -f "$lout" "$lerr"' EXIT
targets=()
if bash "$root/scripts/link.sh" >"$lout" 2>"$lerr"; then
  while IFS= read -r l; do fixed+=("fixed: $(tilde "$l")"); done < "$lout"
  if bash "$root/scripts/link.sh" --status >"$lout" 2>"$lerr"; then
    while IFS= read -r l; do targets+=("$l"); done < "$lout"
  else
    link_problems+=("problem: link.sh failed: $(tilde "$(tail -n 1 "$lerr")")")
  fi
else
  link_problems+=("problem: link.sh failed: $(tilde "$(tail -n 1 "$lerr")")")
fi

# Each count_* sets `got` rather than print it, so its problem lines land in
# this shell, not in a subshell's copy of the list.

# count_targets <harness> <kind> <noun> [<status harness>]: how many of
# link.sh's targets of that kind and status harness, the harness when not
# given, are ok. A target with no why gets a problem line here; one with a
# why gets its own below.
count_targets() {
  local n=0 total=0 t st kind h name path folder why
  for t in ${targets[@]+"${targets[@]}"}; do
    IFS=$'\t' read -r st kind h name path folder why <<< "$t"
    [ "$kind" = "$2" ] && [ "$h" = "${4:-$1}" ] || continue
    total=$((total + 1))
    if [ "$st" = ok ]; then n=$((n + 1))
    elif [ -z "$why" ]; then problem "$1 has no $3 $name at $path"; fi
  done
  got="$n/$total"
}

# target <kind> <harness>: set path, folder, and why to those of the first
# target of that kind and harness, or empty.
target() {
  local t st kind h name
  path=""; folder=""; why=""
  for t in ${targets[@]+"${targets[@]}"}; do
    IFS=$'\t' read -r st kind h name path folder why <<< "$t"
    [ "$kind" = "$1" ] && [ "$h" = "$2" ] && return 0
  done
  path=""; folder=""; why=""
}

# commands <file>...: every hook command in the files, one per line.
commands() {
  local f
  for f in "$@"; do
    [ -f "$f" ] && jq -r '.. | objects | .command? // empty | strings' "$f" 2>/dev/null || true
  done
}

# wired <gate>: whether a command on stdin has a word that is the gate's
# name, or ends in /<gate>.sh, quotes taken off.
wired() {
  awk -v g="$1" '{ gsub(/["\047]/, "")
    for (i = 1; i <= NF; i++) if ($i == g || substr($i, length($i) - length(g) - 3) == "/" g ".sh") f = 1 }
    END { exit !f }'
}

# count_gates <harness> <where> <commands> <unread> <gate>...: how many gates
# the hook commands wire. A hook file link.sh could not read, <unread> not
# empty, already has its problem line, so its gates get none.
count_gates() {
  local h="$1" where="$2" cmds="$3" unread="$4" n=0 total=0 g; shift 4
  for g in "$@"; do
    total=$((total + 1))
    if printf '%s\n' "$cmds" | wired "$g"; then n=$((n + 1))
    elif [ -n "$unread" ]; then :
    else problem "$h gate $g is not wired in $where"; fi
  done
  got="$n/$total"
}

# imports_rules <file>: whether the shared rules file has text and a line of
# the file starts with @ and names it.
imports_rules() { [ -s "$shared_rules" ] && [ -f "$1" ] && grep -q '^@.*\.agents/rules/shared\.md' "$1"; }

line() { printf '%-12s %s\n' "$1" "$2"; }

# check_<harness>: set `got` to the harness's counts.
check_claude() {
  count_targets claude skill skill; s="$got"
  count_targets claude agent subagent; a="$got"
  target gate claude
  count_gates claude "$path" "$(commands "$path")" "$why" $personal_gates subagent-gate; g="$got"
  r=0
  if imports_rules "$claude_md"; then r=1; else problem "claude rules: $claude_md does not import $shared_rules"; fi
  got="skills $s · subagents $a · gates $g · rules $r/1"
}

check_codex() {
  count_targets codex skill skill shared; s="$got"
  count_targets codex agent subagent; a="$got"
  target gate codex
  count_gates codex "$path" "$(commands "$path")" "$why" $personal_gates subagent-gate; g="$got"
  r=0
  if [ -f "$codex_md" ] && [ -s "$shared_rules" ] && case "$(cat "$codex_md")" in *"$(cat "$shared_rules")"*) true ;; *) false ;; esac; then r=1
  else problem "codex rules: $codex_md does not hold $shared_rules: start Codex once to rebuild it"; fi
  got="skills $s · subagents $a · gates $g · rules $r/1"
}

# Antigravity, and each private folder T3 runs it from. Antigravity reads the
# hooks.json of every plugin in its plugins folder, and link.sh's status
# line names that folder and each T3 folder.
check_antigravity() {
  local t st kind h name
  count_targets antigravity skill skill; s="$got"
  count_targets antigravity agent subagent; a="$got"
  target gate antigravity; plugins="$folder"
  # The gates sit in many plugins' hooks.json, so one file link.sh could not
  # read hides no gate's line.
  count_gates antigravity "$plugins" "$(commands "$plugins"/*/hooks.json)" "" $personal_gates subagent-gate session-rules; g="$got"
  r=0; rt=1
  if imports_rules "$gemini_md"; then r=1; else problem "antigravity rules: $gemini_md does not include $shared_rules"; fi
  for t in ${targets[@]+"${targets[@]}"}; do
    IFS=$'\t' read -r st kind h name path folder why <<< "$t"
    [ "$kind" = plugins ] || continue
    d="$folder"; rt=$((rt + 1))
    # A T3 link loads the rules only through GEMINI.md, whose problem is named above.
    if [ -L "$d/GEMINI.md" ] && [ "$(readlink "$d/GEMINI.md")" = "$gemini_md" ]; then
      if imports_rules "$gemini_md"; then r=$((r + 1)); fi
    else problem "antigravity rules: $d has no GEMINI.md link: T3 makes it at the next Antigravity chat"; fi
  done
  got="skills $s · subagents $a · gates $g · rules $r/$rt"
}

# harness <name> <cli>: the harness's report line, or skipped when its CLI is
# not on PATH, since a harness the Mac lacks is no failure.
report=(); absent=()
harness() {
  if command -v "$2" >/dev/null 2>&1; then "check_$1"
  else got="skipped: not installed"; absent+=("$1"); fi
  report+=("$(line "$1" "$got")")
}
harness claude claude
harness codex codex
harness antigravity agy

is_absent() {
  local x
  for x in ${absent[@]+"${absent[@]}"}; do [ "$x" = "$1" ] && return 0; done
  return 1
}

# Each target link.sh could not own is a problem, unless it belongs to a
# harness this Mac does not have. No harness owns the shared skills folder.
# An agent link.sh cannot render gives the same why for each harness, so a
# why already named is not named again.
for t in ${targets[@]+"${targets[@]}"}; do
  IFS=$'\t' read -r st kind h name path folder why <<< "$t"
  [ -n "$why" ] && ! is_absent "$h" || continue
  l="problem: $(tilde "$why")"
  for x in ${link_problems[@]+"${link_problems[@]}"}; do [ "$x" = "$l" ] && continue 2; done
  link_problems+=("$l")
done

# Every agent's models, one row each: <agent file> <map> <harness> <place>
# <model>, as agents.sh's models mode lists them.
rows=()
for a in ${agents[@]+"${agents[@]}"}; do
  while read -r r; do rows+=("$a $r"); done < <(bash "$root/scripts/agents.sh" models < "$root/$a")
done

notes=()
# note <line>: add a skip line once.
note() {
  local n
  for n in ${notes[@]+"${notes[@]}"}; do [ "$n" = "$1" ] && return 0; done
  notes+=("$1")
}

# t3_id <place>: the T3 provider of a place, and its name in the report.
t3_id() {
  case "$1" in
    claude) id=claudeAgent; name=Claude ;;
    codex) id=codex; name=Codex ;;
    antigravity) id=antigravity; name=Antigravity ;;
    devin) id=acpRegistry_devin; name=Devin ;;
    *) id=""; name="" ;;
  esac
}

# t3_on <id>: whether T3 has the provider and it is on. No `enabled` key
# means on.
t3_on() {
  [ "$(jq -r --arg id "$1" '.providerInstances[$id] | if . != null and .enabled != false then "on" else "off" end' \
    "$HOME/.t3/userdata/settings.json" 2>/dev/null)" = on ]
}

# offers <list file> <model>: whether the list holds the model.
offers() { jq -e --arg m "$2" 'any(.models[]?; .slug == $m)' "$1" >/dev/null 2>&1; }

# Models: a home against the T3 list of its place, a Claude Code backup
# against T3's Claude list, a Codex backup against Codex's own list. An
# Antigravity backup names no exact model, so it has no list. A backup of a
# harness the Mac lacks never runs, so it is not checked.
for row in ${rows[@]+"${rows[@]}"}; do
  read -r a map h place model <<< "$row"
  [ "$model" = inherit ] && continue
  label="$map"; case "$map" in home?*) label="home ${map#home}" ;; esac
  if [ "${map#home}" != "$map" ]; then
    t3_id "$place"; [ -n "$id" ] || continue
    if ! t3_on "$id"; then note "skip: $name is off in T3, so its home models are not checked"; continue; fi
    list="$HOME/.t3/caches/$id.json"; source="T3 $name"
  else
    is_absent "$h" && continue
    case "$h" in
      claude) t3_id claude; list="$HOME/.t3/caches/$id.json"; source="Claude Code" ;;
      codex) list="$HOME/.codex/models_cache.json"; source=Codex ;;
      *) continue ;;
    esac
  fi
  if [ ! -f "$list" ]; then note "skip: no model list at $(tilde "$list"), so $source models are not checked"; continue; fi
  offers "$list" "$model" || problem "$a: $label for $h: $source does not offer $model"
done

# The agents whose first home starts them in Devin, one `<agent> <model> <then>`
# line each, <then> being where a Devin failure sends it: next when the entry
# lists another home whose place is on in T3, else backup. A later home on Devin is only a fallback,
# so its loss sends no one on.
devin_homes=()
for row in ${rows[@]+"${rows[@]}"}; do
  read -r a map h place model <<< "$row"
  if [ "$map" = home ] && [ "$place" = devin ]; then
    then=backup
    for r in ${rows[@]+"${rows[@]}"}; do
      read -r ra rmap rh next _ <<< "$r"
      case "$rmap" in home[0-9]*) ;; *) continue ;; esac
      [ "$ra" = "$a" ] && [ "$rh" = "$h" ] || continue
      t3_id "$next"
      if [ -n "$id" ] && t3_on "$id"; then then=next; fi
    done
    devin_homes+=("$(basename "$a" .md) $model $then")
  fi
done

# on_devin <then> [model]: those agents a failure sends to <then>, on the
# model when one is named, sorted, joined by ", ".
on_devin() {
  printf '%s\n' ${devin_homes[@]+"${devin_homes[@]}"} | awk -v t="$1" -v m="${2:-}" 'NF && $3 == t && (m == "" || $2 == m) { print $1 }' \
    | sort -u | paste -sd, - | sed 's/,/, /g'
}

# devin_warn <cause> [model]: a warning per place a Devin failure sends agents.
devin_warn() {
  local b n
  b="$(on_devin backup "${2:-}")"; n="$(on_devin next "${2:-}")"
  [ -z "$b" ] || warns+=("warn: $1, so these run on their backup: $b")
  [ -z "$n" ] || warns+=("warn: $1, so these move to their next home: $n")
}

# Devin: one live call per model a first home starts on in Devin. A helper
# whose home Devin cannot run moves on, so each such case is a warning.
warns=()
t3_id devin
if ! t3_on "$id"; then
  devin="off"
  devin_warn "Devin is off in T3"
else
  devin="on"
  while IFS= read -r m; do
    if ! command -v devin >/dev/null 2>&1; then
      reply="devin not installed"; ok=1
    else
      ok=0
      # The loop's lines are on stdin, so devin gets none.
      reply="$(cd "$root" && perl -e 'alarm 60; exec @ARGV' devin --model "$m" --print "Reply with exactly the word: ok" 2>&1 </dev/null)" || ok=1
    fi
    if [ "$ok" -eq 0 ]; then
      devin="$devin · $m answers"
    else
      devin="$devin · $m refused"
      devin_warn "$m refused ($(printf '%s\n' "$reply" | head -n 1))" "$m"
    fi
  done < <(printf '%s\n' ${devin_homes[@]+"${devin_homes[@]}"} | awk 'NF { print $2 }' | sort -u)
fi

printf '%s\n' "${report[@]}"
line "devin in T3" "$devin"
for p in ${fixed[@]+"${fixed[@]}"} ${problems[@]+"${problems[@]}"} ${link_problems[@]+"${link_problems[@]}"} ${notes[@]+"${notes[@]}"} ${warns[@]+"${warns[@]}"}; do
  printf '%s\n' "$p"
done
[ ${#problems[@]} -eq 0 ] && [ ${#link_problems[@]} -eq 0 ]
