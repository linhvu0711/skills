# placement.sh: the cases for this skill's placement.py, on layouts with no
# herdr: where a new pane goes, and the resize that evens a tab's columns.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# pl <python>: run <python> with placement imported and lay(panes, splits)
# in scope. lay builds a layout 200 wide from "id:x:width" panes and
# "x:width" splits to the right, each a space list.
pl() {
  T="$(mktemp -d)"
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import placement
def lay(panes, splits=""):
    ps = [p.rsplit(":", 2) for p in panes.split()]
    ss = [s.split(":") for s in splits.split()]
    return {"area": {"width": 200},
            "panes": [{"pane_id": i, "rect": {"x": int(x), "width": int(w)}} for i, x, w in ps],
            "splits": [{"direction": "right", "rect": {"x": int(x), "width": int(w)}} for x, w in ss]}
def step(r):
    print("None" if r is None else f"{r[0]} {r[1]} {r[2]:.4f}")
exec(sys.argv[2])' "$here/../scripts" "$1"
}

t_pl_imports() {
  # Given: the scripts folder
  T="$(mktemp -d)"
  # When
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import placement' "$here/../scripts"
  # Then
  eq exit 0 "$code"
  eq stdout "" "$out"
  eq stderr "" "$err"
}

t_pl_shrinks() {
  # Given: the first column is 100 wide of three, the split owns x0 w200
  # When
  pl 'step(placement.next_resize(lay("w1:p1:0:100 w1:p3:100:50 w1:p2:150:50", "0:200 100:100")))'
  # Then
  eq stdout "w1:p3 left 0.1667" "$out"
}

t_pl_grows() {
  # Given: the first column is 50 wide of two
  # When
  pl 'step(placement.next_resize(lay("w1:p1:0:50 w1:p2:50:150", "0:200")))'
  # Then
  eq stdout "w1:p1 right 0.2500" "$out"
}

t_pl_widest_left_to_right() {
  # Given: panes out of order, two stacked at x0, the widest 60
  # When
  pl 'step(placement.next_resize(lay("w1:p3:60:140 w1:p4:0:50 w1:p1:0:60", "0:200")))'
  # Then
  eq stdout "w1:p1 right 0.2000" "$out"
}

t_pl_even() {
  # Given: three columns within 2 of 66.7
  # When
  pl 'step(placement.next_resize(lay("w1:p1:0:67 w1:p3:67:67 w1:p2:134:66", "0:200 67:133")))'
  # Then
  eq stdout "None" "$out"
}

t_pl_one_column() {
  # Given: one pane, no split
  # When
  pl 'step(placement.next_resize(lay("w1:p1:0:200")))'
  # Then
  eq stdout "None" "$out"
}

t_pl_pick_two_columns() {
  # Given: this tab w1:t1 holds two columns
  # When
  pl 'print(placement.pick("w1:t1", [("w1:t1", lay("w1:p1:0:100 w1:p3:100:100", "0:200"))]))'
  # Then
  eq stdout "('w1:t1', 'w1:p3')" "$out"
}

t_pl_pick_fewest() {
  # Given: this tab w1:t1 holds three columns, w1:t3 two, w1:t4 one
  # When
  pl 'print(placement.pick("w1:t1", [("w1:t1", lay("w1:p1:0:66 w1:p8:66:67 w1:p9:133:67")), ("w1:t3", lay("w1:p5:0:100 w1:p6:100:100")), ("w1:t4", lay("w1:p7:0:200"))]))'
  # Then
  eq stdout "('w1:t4', 'w1:p7')" "$out"
}

t_pl_pick_full() {
  # Given: this tab w1:t1 holds three columns, and there is no other tab
  # When
  pl 'print(placement.pick("w1:t1", [("w1:t1", lay("w1:p1:0:66 w1:p8:66:67 w1:p9:133:67"))]))'
  # Then
  eq stdout "None" "$out"
}

t_pl_pick_stacked() {
  # Given: this tab w1:t1's last column holds two stacked panes, w1:p4
  # 60 wide listed before w1:p3 100 wide
  # When
  pl 'print(placement.pick("w1:t1", [("w1:t1", lay("w1:p1:0:100 w1:p4:100:60 w1:p3:100:100", "0:200"))]))'
  # Then
  eq stdout "('w1:t1', 'w1:p3')" "$out"
}

cases=(
  "placement imports without running|t_pl_imports"
  "next_resize shrinks a column that is too wide|t_pl_shrinks"
  "next_resize grows a column that is too narrow|t_pl_grows"
  "next_resize reads a column by its widest pane, left to right|t_pl_widest_left_to_right"
  "next_resize gives nothing for even columns|t_pl_even"
  "next_resize gives nothing for one column|t_pl_one_column"
  "pick keeps a tab of 2 columns and its right pane|t_pl_pick_two_columns"
  "pick passes a full tab for the tab with fewest columns|t_pl_pick_fewest"
  "pick gives nothing when every tab is full|t_pl_pick_full"
  "pick splits the widest pane of a stacked column|t_pl_pick_stacked"
)
