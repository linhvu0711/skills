# adopt.sh: the cases for scripts/adopt.sh. tests/run.sh sources this file
# after lib.sh and runs its cases.

# skills_home <skill-text>: repo with an empty skills/, and a local skills
# folder at $T/home holding demo/SKILL.md with that text.
skills_home() {
  repo; mkdir skills; mkdir -p "$T/home/demo"
  printf '%s\n' "$1" > "$T/home/demo/SKILL.md"
}

t_adopt_moves_links_checks() {
  skills_home "# demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh demo
  eq exit 0 "$code"
  eq stdout "$(printf 'adopted demo\ncheck: clean')" "$out"
  [ -f skills/demo/SKILL.md ] || eq "skills/demo/SKILL.md" "a file" "missing"
  eq link "$R/skills/demo" "$(readlink "$T/home/demo")"
}

t_adopt_stops_on_bad_name() {
  skills_home "# demo"
  run env SKILLS_HOME="$T/home" bash scripts/adopt.sh ..
  eq exit 64 "$code"
  eq stderr "stop: not a skill name: ..
usage: adopt.sh <name>" "$err"
  eq "ls home" demo "$(ls "$T/home")"
  eq "ls skills" "" "$(ls skills)"
}

cases=(
  "adopt moves, links, and checks a skill|t_adopt_moves_links_checks"
  "adopt stops on a name that is not a skill name|t_adopt_stops_on_bad_name"
)
