#!/usr/bin/env bash
# check.sh: find leaks before they reach the public repo.
#
#   check.sh               scan every tracked file (the Repo check on GitHub)
#   check.sh <path>...     scan every file under these paths, tracked or not
#   check.sh --staged      scan only the lines and paths the index adds (the pre-commit hook)
#
# Checks: an absolute home path, an email address unless it is on the allow
# list below, and each pattern in the owner's private word list,
# ${PRIVATE_WORDS:-<git common dir>/info/private-words}: one word or regex per
# line, case-insensitive, blank and `#` lines skipped. The list is local and
# never tracked; without it that check is skipped. Private words are matched
# against file paths too.
#
# Exit 0: `check: clean` on stdout.
# Exit 1: one `<file>:<line>: <kind>: <match>` line per problem on stderr,
# then `check: <n> problem(s) found`.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

# A home path is not part of a longer name: it does not follow a letter or a
# digit, so example.com/home/x is not one. The char before it is cut from the match.
home_re='(^|[^A-Za-z0-9._-])/(Users|home)/[A-Za-z0-9._-]+'
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Public addresses the skills name on purpose, one per line.
allowed_emails='cursoragent@cursor.com'

staged=0; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --staged) staged=1; shift ;;
    -*) die "unknown flag $1" ;;
    *) paths+=("$1"); shift ;;
  esac
done
[ "$staged" = 0 ] || [ ${#paths[@]} -eq 0 ] || die "--staged takes no paths"
cd "$(git rev-parse --show-toplevel)" || die "not inside a git repo"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# root: the folder the scanned files are read from. files: the files to scan,
# relative to root. names: the file paths to match private words against.
root="."; files=(); names=()
if [ "$staged" = 1 ]; then
  # Each staged file is copied to $tmp/staged with every line it does not add
  # blanked, so a hit keeps its real line number.
  root="$tmp/staged"
  git -c core.quotePath=false diff --cached -U0 --no-color --diff-filter=ACMR | awk '
    /^diff --git /     { hdr = 1; next }
    hdr && /^\+\+\+ /  { f = substr($0, 7); next }
    /^@@ /             { hdr = 0; sub(/^\+/, "", $3); n = split($3, p, ",")
                         c = p[1] + 0; d = (n > 1 ? p[2] + 0 : 1)
                         for (i = c; i < c + d; i++) print f "\t" i }
  ' > "$tmp/added"
  while IFS= read -r f; do
    mkdir -p "$root/$(dirname "$f")"
    git show ":$f" | awk -F '\t' -v f="$f" '
      NR == FNR { if ($1 == f) keep[$2] = 1; next }
      { print ((FNR in keep) ? $0 : "") }
    ' "$tmp/added" - > "$root/$f"
    files+=("$f")
  done < <(cut -f1 "$tmp/added" | sort -u)
  while IFS= read -r f; do names+=("$f"); done < <(git -c core.quotePath=false diff --cached --name-only --diff-filter=ACR)
elif [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done < <(git -c core.quotePath=false ls-files)
  names=(${files[@]+"${files[@]}"})
else
  while IFS= read -r f; do files+=("$f"); done < <(find "${paths[@]}" -type f -not -path '*/.git/*')
  names=(${files[@]+"${files[@]}"})
fi

words_file="${PRIVATE_WORDS:-$(git rev-parse --path-format=absolute --git-common-dir)/info/private-words}"
words=""
if [ -f "$words_file" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$words_file" > "$tmp/words" || true
  [ -s "$tmp/words" ] && words="$tmp/words"
fi

problems=()

# scan <kind> <allowed> <grep args>...: add every hit in the files as
# `<file>:<line>: <kind>: <match>`, except a match listed in <allowed>.
scan() {
  local kind="$1" allowed="$2" hit; shift 2
  [ ${#files[@]} -gt 0 ] || return 0
  local file line match
  while IFS= read -r hit; do
    file="${hit%%:*}"; line="${hit#*:}"; line="${line%%:*}"; match="${hit#*:*:}"
    case "$kind:$match" in "home path:/"[Uh]*) ;; "home path:"*) match="${match:1}" ;; esac
    [ -n "$allowed" ] && printf '%s\n' "$allowed" | grep -qxF -e "$match" && continue
    problems+=("$file:$line: $kind: $match")
  done < <(cd "$root" && grep -nHIo "$@" -- "${files[@]}" || true)
}

scan "home path" "" -E -e "$home_re"
scan "email" "$allowed_emails" -E -e "$email_re"
if [ -n "$words" ]; then
  scan "private word" "" -iE -f "$words"
  if [ ${#names[@]} -gt 0 ]; then
    while IFS= read -r hit; do
      problems+=("${names[${hit%%:*} - 1]}: private word in path: ${hit#*:}")
    done < <(printf '%s\n' "${names[@]}" | grep -noiE -f "$words" || true)
  fi
fi

if [ ${#problems[@]} -eq 0 ]; then
  echo "check: clean"
  exit 0
fi
printf '%s\n' "${problems[@]}" >&2
printf 'check: %d problem(s) found\n' "${#problems[@]}" >&2
exit 1
