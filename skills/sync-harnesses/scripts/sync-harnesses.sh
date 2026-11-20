#!/usr/bin/env bash
# sync-harnesses.sh: check that Claude Code, Codex, and Antigravity on this
# Mac have the repo's skills and subagents and the owner's rules and gates,
# and that Devin in T3 answers on its home models.
#
#   sync-harnesses.sh
#
# Prints one line per harness with its counts, one line for Devin in T3,
# then one `problem:` line per thing missing. Exit 1 when a problem line
# printed, else 0. Every path comes from HOME.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/../../.." && pwd -P)"

shared_rules="$HOME/.agents/rules/shared.md"
claude_md="$HOME/.claude/CLAUDE.md"
codex_md="$HOME/.codex/AGENTS.md"
gemini_md="$HOME/.gemini/GEMINI.md"
plugins="$HOME/.gemini/config/plugins"
t3_antigravity="$HOME/.t3/userdata/providers/antigravity"

# The owner's personal gates, wired in every harness, and the repo's
# subagent gate. Antigravity also runs session-rules, since T3 starts its
# chats without the rules file.
personal_gates="write-for-agents-gate unslop-gate unslop-commit-gate question-gate plain-style"

problems=()

# tilde <text>: the text with $HOME/ written as ~/.
tilde() { printf '%s' "${1//"$HOME"\//\~/}"; }

problem() { problems+=("problem: $(tilde "$1")"); }

skills=()
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] && skills+=("$(basename "$(dirname "$f")")")
done
agents=()
for f in "$root"/skills/*/agents/*.md "$root"/shared/agents/*.md; do
  [ -f "$f" ] && agents+=("${f#"$root"/}")
done

# Each count_* sets `got` rather than print it, so its problem lines land in
# this shell, not in a subshell's copy of the list.

# count_skills <harness> <folder>: how many repo skills the folder links to.
count_skills() {
  local n=0 s
  for s in ${skills[@]+"${skills[@]}"}; do
    if [ "$(realpath "$2/$s" 2>/dev/null)" = "$root/skills/$s" ]; then n=$((n + 1))
    else problem "$1 has no skill $s at $2/$s"; fi
  done
  got="$n/${#skills[@]}"
}

# count_agents <harness> <folder> <extension>: how many repo agents have
# their file in the folder.
count_agents() {
  local n=0 a f
  for a in ${agents[@]+"${agents[@]}"}; do
    f="$2/$(basename "$a" .md).$3"
    if [ -f "$f" ]; then n=$((n + 1))
    else problem "$1 has no subagent $(basename "$a" .md) at $f"; fi
  done
  got="$n/${#agents[@]}"
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

# count_gates <harness> <where> <commands> <gate>...: how many gates the
# hook commands wire.
count_gates() {
  local h="$1" where="$2" cmds="$3" n=0 total=0 g; shift 3
  for g in "$@"; do
    total=$((total + 1))
    if printf '%s\n' "$cmds" | wired "$g"; then n=$((n + 1))
    else problem "$h gate $g is not wired in $where"; fi
  done
  got="$n/$total"
}

# imports_rules <file>: whether a line of the file starts with @ and names
# the shared rules file.
imports_rules() { [ -f "$1" ] && grep -q '^@.*\.agents/rules/shared\.md' "$1"; }

line() { printf '%-12s %s\n' "$1" "$2"; }

# Claude Code
count_skills claude "$HOME/.claude/skills"; s="$got"
count_agents claude "$HOME/.claude/agents" md; a="$got"
count_gates claude "$HOME/.claude/settings.json" "$(commands "$HOME/.claude/settings.json")" $personal_gates subagent-gate; g="$got"
r=0
if imports_rules "$claude_md"; then r=1; else problem "claude rules: $claude_md does not import $shared_rules"; fi
out_claude="skills $s · subagents $a · gates $g · rules $r/1"

# Codex
count_skills codex "$HOME/.agents/skills"; s="$got"
count_agents codex "$HOME/.codex/agents" toml; a="$got"
count_gates codex "$HOME/.codex/hooks.json" "$(commands "$HOME/.codex/hooks.json")" $personal_gates subagent-gate; g="$got"
r=0
if [ -f "$codex_md" ] && [ -f "$shared_rules" ] && case "$(cat "$codex_md")" in *"$(cat "$shared_rules")"*) true ;; *) false ;; esac; then r=1
else problem "codex rules: $codex_md does not hold $shared_rules: start Codex once to rebuild it"; fi
out_codex="skills $s · subagents $a · gates $g · rules $r/1"

# Antigravity, and each private folder T3 runs it from
count_skills antigravity "$HOME/.gemini/config/skills"; s="$got"
count_agents antigravity "$plugins/skills/agents" md; a="$got"
count_gates antigravity "$plugins" "$(commands "$plugins"/*/hooks.json)" $personal_gates subagent-gate session-rules; g="$got"
r=0; rt=1
if imports_rules "$gemini_md"; then r=1; else problem "antigravity rules: $gemini_md does not include $shared_rules"; fi
for d in "$t3_antigravity"/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"; rt=$((rt + 1))
  if [ -L "$d/GEMINI.md" ] && [ "$(readlink "$d/GEMINI.md")" = "$gemini_md" ]; then r=$((r + 1))
  else problem "antigravity rules: $d has no GEMINI.md link: T3 makes it at the next Antigravity chat"; fi
done
out_antigravity="skills $s · subagents $a · gates $g · rules $r/$rt"

# Devin: one live call per model a home starts on in Devin.
devin_models=()
for a in ${agents[@]+"${agents[@]}"}; do
  while read -r map h place model; do
    [ "$map" = home ] && [ "$place" = devin ] && devin_models+=("$model")
  done < <(bash "$root/scripts/agents.sh" models < "$root/$a")
done
devin="on"
for m in $(printf '%s\n' ${devin_models[@]+"${devin_models[@]}"} | sort -u); do
  if (cd "$root" && perl -e 'alarm 60; exec @ARGV' devin --model "$m" --print "Reply with exactly the word: ok") >/dev/null 2>&1; then
    devin="$devin · $m answers"
  else
    devin="$devin · $m refused"
  fi
done

line claude "$out_claude"
line codex "$out_codex"
line antigravity "$out_antigravity"
line "devin in T3" "$devin"
for p in ${problems[@]+"${problems[@]}"}; do printf '%s\n' "$p"; done
[ ${#problems[@]} -eq 0 ]
