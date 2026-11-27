# labels.sh: the label rule, the allow-lists, and the analysis row that the
# Router, decide.sh, and the orchestrator's script share. Source it; it
# defines values and functions and runs nothing.
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

# one_of <list> <word>: true when <word> is on the |-list.
one_of() { [[ "$2" =~ ^($1)$ ]]; }

# spelled <list>: the |-list as words for a message, as `a, b, or c`.
spelled() { printf '%s' "$1" | sed -E 's/\|([^|]*)$/, or \1/; s/\|/, /g'; }
