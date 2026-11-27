# labels.sh: the label rule, the allow-lists, and the analysis row that the
# Router, decide.sh, and the orchestrator's script share. Source it; it
# defines values and functions and runs nothing.

route_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

#
# size_of <label>: XS, S, M, L, XL, or XXL when the label names a size, matched
# loosely (`size/S`, `Size: Medium`, `effort-large`), else nothing.
size_of() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/(size|scope|effort)//g; s/[^a-z]//g')" in
    xs|xsmall|extrasmall) echo XS ;;
    s|small) echo S ;;
    m|med|medium) echo M ;;
    l|large) echo L ;;
    xl|xlarge|extralarge) echo XL ;;
    xxl|xxlarge|extraextralarge) echo XXL ;;
  esac
}

# The allow-lists, each a |-list. The _list names keep clear of decide.sh's
# own sizes array.
effort_list='low|medium|high|xhigh|max'
ship_mode_list='review|ready|merge'
# A guess is never XXL: XXL work is cut into tickets (shared/size.md).
size_list='XS|S|M|L|XL'
# The words a proposal and an answer name a step by.
route_list='grill|triage|ship|ready-pr|task|close|xxl'

# The analysis row: the model and effort the Router and decide.sh give
# /grill and /triage, and the orchestrator gives the retro.
analysis_model=opus
analysis_effort=high

# answer_label <owner/repo> <answer> [<size>]: the label an answer to a
# proposal writes on the issue, so no skill guesses it again: bug for
# triage, seed for grill, manual for task, and for ship the repo's own size
# label, or size/<size> when the repo has none saved. Nothing for the rest.
# Returns 1, with `stop:` on stderr, when python3 or jq is not installed.
answer_label() {
  local conv c
  case "$2" in
    triage) echo bug ;;
    grill) echo seed ;;
    task) echo manual ;;
    ship)
      for c in python3 jq; do
        command -v "$c" >/dev/null || { printf 'stop: %s is not installed\n' "$c" >&2; return 1; }
      done
      if conv="$(python3 "$route_dir/../issue_conventions.py" get "$1" 2>/dev/null)"; then
        jq -r --arg z "$3" '.size[$z] // "size/\($z)"' <<<"$conv"
      else
        echo "size/$3"
      fi ;;
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
