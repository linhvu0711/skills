#!/usr/bin/env bash
# check.sh: find leaks before they reach the public repo.
#
#   check.sh               scan every tracked file (the Repo check on GitHub)
#   check.sh <path>...     scan every file under these paths, tracked or not
#   check.sh --staged      scan only the lines and paths the index adds (the pre-commit hook)
#   check.sh --commit-msg <file>
#                          the README check only, on the index and that message (the commit-msg hook)
#
# Checks: an absolute home path, an email address unless it is on the allow
# list below, and each pattern in the owner's private word list,
# ${PRIVATE_WORDS:-<git common dir>/info/private-words}: one word or regex per
# line, case-insensitive, blank and `#` lines skipped. The list is local and
# never tracked; without it that check is skipped. Private words are matched
# against file paths too. Last, a relative path in a `.md`, `.sh`, or `.py` file
# under skills/ or shared-skill-core/ must point to a file: a path in a skill
# starts at the skill's folder, a path in the shared core at the file's own
# folder, and `$here/` in a script at the script's folder. A path is read when
# it starts with `../` or its first folder exists there; a path that starts
# with `./`, holds `<`, `{`, `*`, or `$`, or is on the allow list below is
# skipped.
#
# In tree and --staged mode, two whole-repo checks read the index, so the hook
# sees what the commit holds. Each `copy` or `heavy adaptation` row in
# THIRD_PARTY_NOTICES.md needs its upstream's license next to it:
# `skills/<name>/LICENSE` for a skill, `shared-skill-core/LICENSE-<owner>` for a
# shared core file, <owner> from the section's `## <owner>/<repo>` heading.
# Each skill with a SKILL.md needs a README.md with the headings `## Use it
# when`, `## What you get`, `## Needs`, and `## Fits with`, plus `## Credits`
# when THIRD_PARTY_NOTICES.md lists it or a file inside it. Each SKILL.md needs
# a frontmatter (a `---` first line and a closing `---` line), a `name` equal to
# its folder, and a `description` that is not empty.
#
# The README check runs only with --commit-msg: a commit that changes a file
# under `skills/<name>/` needs `skills/<name>/README.md` in it too, unless a line
# of the message is `Readme: unchanged`. A change to a shared core file asks for
# the README of each skill that reads it. A skill reads a core file when one of
# its files names it or a folder that holds it, when it reads another file in
# the same core subfolder, or when a core file it reads names or includes it. A
# merge commit is skipped. The change is the index against HEAD, and git tells
# a hook nothing about an amend, so an amend is judged by what it adds to the
# commit it replaces.
#
# Exit 0: `check: clean` on stdout.
# Exit 1: one `<file>:<line>: <kind>: <match>` line per problem on stderr (or
# `<path>: <problem>` for a check of a whole file or folder),
# then `check: <n> problem(s) found`.
set -euo pipefail

die() { printf 'stop: %s\n' "$*" >&2; exit 1; }

# report: print the problems and exit 1, or print `check: clean` and exit 0.
report() {
  if [ ${#problems[@]} -eq 0 ]; then
    echo "check: clean"
    exit 0
  fi
  printf '%s\n' "${problems[@]}" >&2
  printf 'check: %d problem(s) found\n' "${#problems[@]}" >&2
  exit 1
}

# A home path is not part of a longer name: it does not follow a letter or a
# digit, so example.com/home/x is not one. The char before it is cut from the match.
home_re='(^|[^A-Za-z0-9._-])/(Users|home)/[A-Za-z0-9._-]+'
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# Public addresses the skills name on purpose, one per line.
allowed_emails='cursoragent@cursor.com'
# Paths a skill names in the user's repo, not in its own folder, as
# `<skill folder> <path>`, one per line.
allowed_paths='skills/embed-source scripts/sync-repos.sh'

staged=0; msg=""; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --staged) staged=1; shift ;;
    --commit-msg) [ $# -ge 2 ] || die "--commit-msg takes a file"; msg="$2"; shift 2 ;;
    -*) die "unknown flag $1" ;;
    *) paths+=("$1"); shift ;;
  esac
done
[ "$staged" = 0 ] || [ ${#paths[@]} -eq 0 ] || die "--staged takes no paths"
[ -z "$msg" ] || { [ "$staged" = 0 ] && [ ${#paths[@]} -eq 0 ]; } || die "--commit-msg takes no other flag or path"
if [ -n "$msg" ]; then
  [ -f "$msg" ] || die "no such file: $msg"
  case "$msg" in /*) ;; *) msg="$PWD/$msg" ;; esac
fi
# Paths are given from the caller's folder; the scan runs from the repo root.
prefix="$(git rev-parse --show-prefix)" || die "not inside a git repo"
for i in ${paths[@]+"${!paths[@]}"}; do
  [ -e "${paths[$i]}" ] || die "no such path: ${paths[$i]}"
  case "${paths[$i]}" in /*) ;; *) paths[$i]="$prefix${paths[$i]}" ;; esac
done
cd "$(git rev-parse --show-toplevel)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
problems=()

# in_index <path>: the path is in the index, so the commit holds it.
in_index() { git cat-file -e ":$1" 2>/dev/null; }

# skill_dirs: each `skills/<name>` folder whose SKILL.md is in the index.
skill_dirs() { git ls-files -- 'skills/*/SKILL.md' | awk -F/ 'NF == 3 { print $1 "/" $2 }'; }

# refs <file> <text>: each relative path that <file> names, read from the file
# <text>, as `<line>\t<path>\t<from>/<path>`, by the rules in the header. Prints
# nothing for a file outside skills/ and shared-skill-core/, or not `.md`, `.sh`,
# or `.py`.
refs() {
  local f="$1" text="$2" base line tok p from nl=$'\n'
  case "$f" in
    skills/*/*) base="${f#skills/}"; base="skills/${base%%/*}" ;;
    shared-skill-core/*) base="$(dirname "$f")" ;;
    *) return 0 ;;
  esac
  case "$f" in *.md|*.sh|*.py) ;; *) return 0 ;; esac
  while IFS=$'\t' read -r line tok; do
    case "$tok" in
      '$here/'*) case "$f" in *.sh) ;; *) continue ;; esac
                 p="${tok#\$here/}"; from="$(dirname "$f")" ;;
      /*|./*) continue ;;
      ../*) p="$tok"; from="$base" ;;
      *) [ -d "$base/${tok%%/*}" ] || continue; p="$tok"; from="$base" ;;
    esac
    case "$p" in *[\<\>{}*\$~]*) continue ;; esac
    while [ "${p%.}" != "$p" ]; do p="${p%.}"; done
    case "$nl$allowed_paths$nl" in *"$nl$base $p$nl"*) continue ;; esac
    printf '%s\t%s\t%s\n' "$line" "$p" "$from/$p"
  done < <(awk '{ s = $0; gsub(/[^A-Za-z0-9_.\/<>{}*$~-]/, " ", s); n = split(s, w, " ")
                  for (i = 1; i <= n; i++) if (w[i] ~ /\//) print FNR "\t" w[i] }' "$text")
}

# core_refs: the shared core paths that the index files named on stdin name,
# one per line, `.` and `..` folded. A path inside a core subfolder becomes that
# subfolder, since the files of one subfolder work as one unit.
core_refs() {
  local f
  while IFS= read -r f; do refs "$f" <(git show ":$f"); done | cut -f3 | awk -F/ '
    { n = 0; for (i = 1; i <= NF; i++) { if ($i == "" || $i == ".") continue
                                         if ($i == "..") { if (n) n--; continue }
                                         p[++n] = $i }
      if (n == 0 || p[1] != "shared-skill-core") next
      print (n >= 2 ? p[1] "/" p[2] : p[1]) }' | sort -u
}

# under <reads> <paths>: print each line of the file <paths> that is a line of
# the file <reads>, or inside one.
under() {
  awk -F '\t' 'NR == FNR { r[$0] = 1; next }
                { for (k in r) if ($1 == k || index($1, k "/") == 1) { print; next } }' "$1" "$2"
}

# --commit-msg: the README check alone; the pre-commit hook ran the rest. Each
# skill the commit changes needs its README in the commit too, unless a message
# line is `Readme: unchanged`. A merge is skipped: each side's commits passed.
if [ -n "$msg" ]; then
  if grep -qE '^Readme: unchanged[[:space:]]*$' "$msg" || git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    report
  fi
  git -c core.quotePath=false diff --cached --name-only --no-renames > "$tmp/changed"
  awk -F/ '$1 == "skills" && NF >= 3 { print $1 "/" $2 }' "$tmp/changed" > "$tmp/asked"
  # A changed shared core file asks each skill that reads it: one of the
  # skill's files names it or its subfolder, or a core file the skill reads does.
  grep '^shared-skill-core/' "$tmp/changed" > "$tmp/core" || true
  if [ -s "$tmp/core" ]; then
    while IFS= read -r f; do
      printf '%s\n' "$f" | core_refs | awk -v f="$f" '{ print f "\t" $0 }'
    done < <(git ls-files -- shared-skill-core) > "$tmp/edges"
    while IFS= read -r skill; do
      git ls-files -- "$skill/" | core_refs > "$tmp/reads"
      while :; do
        { cat "$tmp/reads"; under "$tmp/reads" "$tmp/edges" | cut -f2; } | sort -u > "$tmp/next"
        cmp -s "$tmp/next" "$tmp/reads" && break
        mv "$tmp/next" "$tmp/reads"
      done
      [ -z "$(under "$tmp/reads" "$tmp/core")" ] || echo "$skill" >> "$tmp/asked"
    done < <(skill_dirs)
  fi
  sort -u -o "$tmp/asked" "$tmp/asked"
  while IFS= read -r skill; do
    grep -qxF "$skill/README.md" "$tmp/changed" \
      || problems+=("$skill: changed without its README; add \"Readme: unchanged\" to the message to skip")
  done < "$tmp/asked"
  report
fi

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

# Each relative path must exist in the work tree. The text is read from root,
# so --staged reads only the added lines; the files they name are looked up
# from the repo top, where this script now runs.
for f in ${files[@]+"${files[@]}"}; do
  while IFS=$'\t' read -r line p path; do
    [ -e "$path" ] || problems+=("$f:$line: missing path: $p")
  done < <(refs "$f" "$root/$f")
done

if [ ${#paths[@]} -eq 0 ]; then
  # rows: `<line>\t<owner>\t<path>\t<level>` for each table row of
  # THIRD_PARTY_NOTICES.md whose first cell is one backticked path.
  rows=""
  if in_index THIRD_PARTY_NOTICES.md; then
    rows="$(git show :THIRD_PARTY_NOTICES.md | awk '
      /^## / { split($2, o, "/"); owner = o[1]; next }
      /^\|/  { n = split($0, c, "|"); p = c[2]; lv = c[n - 1]
               gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", lv)
               if (p !~ /^`[^`]+`$/) next
               gsub(/`/, "", p); print FNR "\t" owner "\t" p "\t" lv }')"
  fi
  while IFS=$'\t' read -r line owner p level; do
    case "$level" in copy*|"heavy adaptation"*) ;; *) continue ;; esac
    case "$p" in
      skills/*) p="${p#skills/}"; lic="skills/${p%%/*}/LICENSE" ;;
      shared-skill-core/*) lic="shared-skill-core/LICENSE-$owner" ;;
      *) continue ;;
    esac
    in_index "$lic" || problems+=("THIRD_PARTY_NOTICES.md:$line: missing license: $lic")
  done <<< "$rows"

  while IFS= read -r skill; do
    if ! in_index "$skill/README.md"; then
      problems+=("$skill: missing file: README.md"); continue
    fi
    headings=("Use it when" "What you get" "Needs" "Fits with")
    # A row for the skill, or for a file inside it, asks for Credits.
    printf '%s\n' "$rows" | awk -F '\t' -v s="$skill" '$3 == s || index($3, s "/") == 1 { f = 1 } END { exit !f }' \
      && headings+=("Credits")
    readme="$(git show ":$skill/README.md")"
    for h in "${headings[@]}"; do
      printf '%s\n' "$readme" | grep -qxF -e "## $h" || problems+=("$skill/README.md: missing heading: ## $h")
    done
  done < <(skill_dirs)

  # Each SKILL.md opens with a frontmatter whose `name` is the folder and whose
  # `description` is not empty. A quoted value is what the quotes hold, with
  # `''` read as `'` and a `\`-escaped char kept; an
  # unquoted one loses its `#` comment, and `null` or `~` is empty. A block
  # scalar counts when its first line that is not blank is indented.
  while IFS= read -r skill; do
    while IFS= read -r p; do problems+=("$skill/SKILL.md: $p"); done < <(git show ":$skill/SKILL.md" | awk -v want="${skill#skills/}" -v q="'" '
      function val(s,  c, i, ch, v) { sub(/^[^:]*:[ \t]*/, "", s); c = substr(s, 1, 1)
        if (c == "\"" || c == q) {
          for (i = 2; i <= length(s); i++) { ch = substr(s, i, 1)
            if (c == q && ch == q && substr(s, i + 1, 1) == q) { v = v q; i++; continue }
            if (c == "\"" && ch == "\\") { v = v substr(s, i, 2); i++; continue }
            if (ch == c) return v
            v = v ch }
          return s }
        sub(/(^|[ \t]+)#.*$/, "", s); sub(/[ \t]+$/, "", s)
        return (s == "~" || tolower(s) == "null") ? "" : s }
      NR == 1          { if ($0 != "---") exit; next }
      blk && /^[ \t]*$/ { next }
      blk              { blk = 0; if ($0 ~ /^[ \t]+[^ \t]/) desc = "block" }
      $0 == "---"      { closed = 1; exit }
      /^name:/         { name = val($0) }
      /^description:/  { desc = val($0); if (desc ~ /^[|>][-+]?$/) { desc = ""; blk = 1 } }
      END { if (!closed) { print "missing frontmatter"; exit }
            if (name != want) print "name does not match folder: " (name == "" ? "(none)" : name)
            if (desc == "") print "empty description" }')
  done < <(skill_dirs)
fi
if [ -n "$words" ]; then
  scan "private word" "" -iE -f "$words"
  if [ ${#names[@]} -gt 0 ]; then
    while IFS= read -r hit; do
      problems+=("${names[${hit%%:*} - 1]}: private word in path: ${hit#*:}")
    done < <(printf '%s\n' "${names[@]}" | grep -noiE -f "$words" || true)
  fi
fi

report
