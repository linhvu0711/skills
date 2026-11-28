# die.sh: the one way a shell script of the shared core, a skill, or scripts/
# stops. Source it; it defines functions and runs nothing. It uses only sh
# words, since shared/serve.sh sources it from sh.
#
# die <why>: `stop: <why>` on stderr, exit 1.
die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

# die_usage <usage> [why]: `stop: <why>` when given, then the usage line, on
# stderr, exit 64. The why is printed from a subshell, so its shift leaves
# the usage in $1 with no variable to set.
die_usage() { [ $# -lt 2 ] || (shift; printf 'stop: %s\n' "$*" >&2); printf '%s\n' "$1" >&2; exit 64; }
