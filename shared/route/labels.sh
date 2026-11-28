# labels.sh: the label rule, the allow-lists, and the analysis row that the
# Router, run-in-t3's kickoff.sh, and the orchestrator's script share. Source it; it
# defines values and functions and runs nothing.

route_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$route_dir/../gh.sh"

#
# size_of <label>: XS, S, M, L, XL, or XXL when the label names a size, matched
# loosely (`size/S`, `Size: Medium`, `effort-large`, `Size: S (10-29)`),
# else nothing. Only a line range such as `10-29` drops; every other digit
# stays, so a severity label such as `S1` or `S-1` names no size.
size_of() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/(size|scope|effort)//g; s/[0-9]+ *- *[0-9]+//g; s/[^a-z0-9]//g')" in
    xs|xsmall|extrasmall) echo XS ;;
    s|small) echo S ;;
    m|med|medium) echo M ;;
    l|large) echo L ;;
    xl|xlarge|extralarge) echo XL ;;
    xxl|xxlarge|extraextralarge) echo XXL ;;
  esac
}

# The allow-lists, each a |-list.
effort_list='low|medium|high|xhigh|max'
ship_mode_list='review|ready|merge'
# The steps a user may pick by name, as "triage it", over the labels.
pick_list='triage|grill|ready-pr'
# A guess is never XXL: XXL work is cut into tickets (shared/size.md).
size_list='XS|S|M|L|XL'
# The words a proposal and an answer name a step by.
route_list='grill|triage|ship|ready-pr|task|close|xxl'

# The analysis row: the model and effort the Router gives /grill and /triage.
analysis_model=opus
analysis_effort=high

# answer_label <owner/repo> <answer> [<size>]: the label an answer to a
# proposal writes on the issue, so no skill guesses it again: bug for
# triage, seed for grill, manual for task, and for ship the repo's saved size
# label. With no saved map, the first of the repo's GitHub labels that names
# the size, or size/<size> when none does. Nothing for the rest.
# Returns 1, with `stop:` on stderr, when python3, jq, or gh is not
# installed, when the saved size labels cannot be read, or when the repo's
# labels cannot be read.
answer_label() {
  local conv c rc l out err status
  case "$2" in
    triage) echo bug ;;
    grill) echo seed ;;
    task) echo manual ;;
    ship)
      for c in python3 jq gh; do
        command -v "$c" >/dev/null || { printf 'stop: %s is not installed\n' "$c" >&2; return 1; }
      done
      rc=0; conv="$(python3 "$route_dir/../issue_conventions.py" get "$1")" || rc=$?
      case "$rc" in
        0) jq -r --arg z "$3" '.size[$z] // "size/\($z)"' <<<"$conv" ;;
        3)  # MISS: the repo has no size labels saved
          gh_out label list --repo "$1" --limit 200 --json name -q '.[].name' \
            || { printf 'stop: could not read the labels of %s: %s\n' "$1" "$err" >&2; return 1; }
          while IFS= read -r l; do
            if [ "$(size_of "$l")" = "$3" ]; then echo "$l"; return 0; fi
          done <<<"$out"
          echo "size/$3" ;;
        *) printf 'stop: could not read the saved size labels of %s (exit %s)\n' "$1" "$rc" >&2; return 1 ;;
      esac ;;
  esac
}

# label_spec <label>: the color, then the description, one per line, that
# an answer label the repo lacks is made with, per ../issue-rules.md
# § Repo convention and capture's seed and bug. A size label of any name
# gets its size's row. Nothing for another label.
label_spec() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    manual) printf '%s\n' 6E7781 "Work in a platform outside the repo; /complete-task drives it" ;;
    seed) printf '%s\n' C5DEF5 "Captured idea. Not triaged. May be dropped." ;;
    bug) printf '%s\n' 8250DF "Seen broken. Not triaged. Becomes a fix ticket through file-issue." ;;
    *)
      case "$(size_of "$1")" in
        XS) printf '%s\n' BFDADC "0-9 changed lines" ;;
        S) printf '%s\n' 7FC8CC "10-29 changed lines" ;;
        M) printf '%s\n' 3FA9B0 "30-99 changed lines" ;;
        L) printf '%s\n' 1B7A82 "100-499 changed lines" ;;
        XL) printf '%s\n' 0F5C62 "500-999 changed lines" ;;
      esac ;;
  esac
}

# one_of <list> <word>: true when <word> is on the |-list.
one_of() { [[ "$2" =~ ^($1)$ ]]; }

# spelled <list>: the |-list as words for a message, as `a, b, or c`.
spelled() { printf '%s' "$1" | sed -E 's/\|([^|]*)$/, or \1/; s/\|/, /g'; }
