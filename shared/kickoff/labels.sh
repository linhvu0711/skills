# labels.sh: the size rule shared by decide.sh and the factory's check.
# Source it; it defines functions and runs nothing.
#
# size_of <label>: XS, S, M, L, or XL when the label names a size, matched
# loosely (`size/S`, `Size: Medium`, `effort-large`), else nothing.
size_of() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/(size|scope|effort)//g; s/[^a-z]//g')" in
    xs|xsmall|extrasmall) echo XS ;;
    s|small) echo S ;;
    m|med|medium) echo M ;;
    l|large) echo L ;;
    xl|xlarge|extralarge) echo XL ;;
  esac
}
