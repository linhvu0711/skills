#!/usr/bin/env bash
# mac.sh <dir>: a fake Mac in <dir> for the sync-harnesses cases and walks.
#
#   <dir>/repo   a fresh git repo with this checkout's scripts/, shared/gate/,
#                and skills/sync-harnesses/, plus a skill `demo` with one
#                agent `helper`
#   <dir>/home   a home where every harness is installed and wired, as the
#                owner's Mac is when all is well
#   <dir>/sync   runs the check on that home
#
# Both link.sh and the check run under `env -i`, so no path the test runner
# exports reaches them and both follow the fake HOME.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: mac.sh <dir>" >&2; exit 2; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
src="$(cd "$here/../../../.." && pwd -P)"
rm -rf "$1"; mkdir -p "$1"
dir="$(cd "$1" && pwd -P)"
r="$dir/repo"; h="$dir/home"

mkdir -p "$r/shared" "$r/skills/demo/agents"
cp -R "$src/scripts" "$r/scripts"
cp -R "$src/shared/gate" "$r/shared/gate"
cp -R "$src/skills/sync-harnesses" "$r/skills/sync-harnesses"
printf -- '---\nname: demo\ndescription: demo\n---\n' > "$r/skills/demo/SKILL.md"
cat > "$r/skills/demo/agents/helper.md" <<'AGENT'
---
name: helper
description: Helps.
home:
  claude: devin swe-2-high high
  codex: claude claude-haiku-5-5 high
  antigravity: antigravity gemini-4-neon high
backup:
  claude: claude-haiku-5-5 high
  codex: gpt-6-luna high
  antigravity: inherit
---
You help.
AGENT
git -C "$r" init -q
git -C "$r" config core.hooksPath .no-hooks

mkdir -p "$h/bin" "$h/.agents/rules" "$h/.claude" "$h/.codex" "$h/.t3/caches" \
  "$h/.gemini/config/plugins/personal" "$h/.t3/userdata/providers/antigravity/p1"

# The tools the check needs, found where this host keeps them. A wrapper
# carries the library and git paths a Sandbox's unpacked git needs, which
# `env -i` would drop.
for t in bash jq git; do
  {
    printf '#!/bin/sh\n'
    for v in LD_LIBRARY_PATH GIT_EXEC_PATH GIT_TEMPLATE_DIR; do
      eval "x=\${$v:-}"
      [ -z "$x" ] || printf "export %s='%s'\n" "$v" "$x"
    done
    printf "exec '%s' \"\$@\"\n" "$(command -v "$t")"
  } > "$h/bin/$t"
  chmod 755 "$h/bin/$t"
done
for t in claude codex agy; do printf '#!/bin/sh\nexit 0\n' > "$h/bin/$t"; chmod 755 "$h/bin/$t"; done
cat > "$h/bin/devin" <<DEVIN
#!/bin/sh
printf '%s\n' "\$*" >> '$dir/devin.calls'
m=""; prev=""
for a in "\$@"; do [ "\$prev" != --model ] || m="\$a"; prev="\$a"; done
if [ "\$m" = swe-2-high ] && [ ! -e '$h/.devin-refuse' ]; then echo ok; exit 0; fi
echo "Error: Unknown model: '\$m'"; exit 1
DEVIN
chmod 755 "$h/bin/devin"

printf 'Rule one.\n' > "$h/.agents/rules/shared.md"
printf '@~/.agents/rules/shared.md\n' > "$h/.claude/CLAUDE.md"
printf '<!-- built -->\nRule one.\n' > "$h/.codex/AGENTS.md"
printf '@[shared rules](%s/.agents/rules/shared.md)\n' "$h" > "$h/.gemini/GEMINI.md"
ln -s "$h/.gemini/GEMINI.md" "$h/.t3/userdata/providers/antigravity/p1/GEMINI.md"

gates=(write-for-agents-gate unslop-gate unslop-commit-gate question-gate plain-style)
# hooks <harness>: one UserPromptSubmit command per personal gate.
hooks() {
  jq -n --arg h "$h" --arg x "$1" --arg q "'" \
    '{hooks: {UserPromptSubmit: [{hooks: [$ARGS.positional[]
      | {type: "command", command: ("bash " + $q + $h + "/.agents/hooks/" + . + ".sh" + $q + " " + $x)}]}]}}' \
    --args "${gates[@]}"
}
hooks claude > "$h/.claude/settings.json"
hooks codex > "$h/.codex/hooks.json"
jq -n '{personal: {SessionStart: [{hooks: [{type: "command", command: "./gate.sh session-rules"}]}],
  PreToolUse: [{hooks: [$ARGS.positional[] | {type: "command", command: ("./gate.sh " + .)}]}]}}' \
  --args "${gates[@]}" > "$h/.gemini/config/plugins/personal/hooks.json"

# One provider per line, so a walk can turn one off with sed.
cat > "$h/.t3/userdata/settings.json" <<'T3'
{"providerInstances": {
"claudeAgent": {"driver": "claudeAgent"},
"codex": {"driver": "codex", "enabled": true},
"antigravity": {"driver": "antigravity", "displayName": "Antigravity", "enabled": true},
"acpRegistry_devin": {"driver": "acpRegistry", "displayName": "Devin", "enabled": true}
}}
T3
printf '{"models":[{"slug":"claude-haiku-5-5"}]}\n' > "$h/.t3/caches/claudeAgent.json"
printf '{"models":[]}\n' > "$h/.t3/caches/codex.json"
printf '{"models":[{"slug":"gemini-4-neon"}]}\n' > "$h/.t3/caches/antigravity.json"
printf '{"models":[{"slug":"swe-2-high"}]}\n' > "$h/.t3/caches/acpRegistry_devin.json"
printf '{"models":[{"slug":"gpt-6-luna"}]}\n' > "$h/.codex/models_cache.json"

env -i HOME="$h" PATH="$h/bin:/usr/bin:/bin" bash "$r/scripts/link.sh" >/dev/null

cat > "$dir/sync" <<SYNC
#!/bin/sh
exec env -i HOME='$h' PATH='$h/bin:/usr/bin:/bin' bash '$r/skills/sync-harnesses/scripts/sync-harnesses.sh' "\$@"
SYNC
chmod 755 "$dir/sync"
