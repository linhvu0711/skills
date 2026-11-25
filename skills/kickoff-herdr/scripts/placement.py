#!/usr/bin/env python3
"""Where kickoff puts a new herdr pane, and the resizes that even its columns.
Usage: placement.py pick <workspace_id> <my_tab_id>
       placement.py even <pane_id>

pick prints "<tab_id> <pane_id>" to split, or nothing for a new tab.

herdr resize semantics (measured): `--direction left|right` moves the divider on
that side of the pane, preferring the left divider for `left` and the right divider
for `right`, falling back to the only divider a border pane has. So to move the
boundary between column i and i+1: grow column i with `right` on column i's pane,
shrink column i with `left` on column i+1's pane. `--amount` is a ratio delta of the
split that owns that boundary; the sign comes from the direction (negatives are
absoluted). One resize per fresh layout read — a resize shifts every pane to its
right, so widths read before it are stale.
"""
import json
import subprocess
import sys


# A tab takes a new pane while it has fewer columns than this.
MAX_COLUMNS = 3


def herdr(*args):
    out = subprocess.run(
        ["herdr", *args], capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)["result"]


def layout(pane_id):
    return herdr("pane", "layout", "--pane", pane_id)["layout"]


def columns(lay):
    by_x = {}
    for p in lay["panes"]:
        x = p["rect"]["x"]
        if x not in by_x or p["rect"]["width"] > by_x[x]["rect"]["width"]:
            by_x[x] = p
    return [by_x[x] for x in sorted(by_x)]


def boundary_split(lay, left_col, right_col):
    """Smallest horizontal split whose rect covers both columns — it owns their divider."""
    lr = left_col["rect"]
    rr = right_col["rect"]
    cands = [
        s for s in lay["splits"]
        if s["direction"] == "right"
        and s["rect"]["x"] <= lr["x"]
        and s["rect"]["x"] + s["rect"]["width"] >= rr["x"] + rr["width"]
    ]
    return min(cands, key=lambda s: s["rect"]["width"]) if cands else None


def room(lay):
    """The columns of a tab that can take one more, else None."""
    if lay is None:
        return None
    cols = columns(lay)
    return cols if 0 < len(cols) < MAX_COLUMNS else None


def pick(my_tab, layouts):
    """Where to split, as (tab_id, pane_id): my_tab when it has room, else the
    first other tab with the fewest columns that has room, else None. layouts
    is [(tab_id, layout or None)] in herdr's tab order. The pane is the last
    column's."""
    mine = room(dict(layouts).get(my_tab))
    if mine:
        return my_tab, mine[-1]["pane_id"]
    best = None
    for tab, lay in layouts:
        cols = None if tab == my_tab else room(lay)
        if cols and (best is None or len(cols) < len(best[1])):
            best = (tab, cols)
    return (best[0], best[1][-1]["pane_id"]) if best else None


def tab_layouts(workspace, my_tab):
    """Each tab's layout, my_tab first, read through its first listed pane."""
    first = {}
    for p in herdr("pane", "list", "--workspace", workspace)["panes"]:
        first.setdefault(p["tab_id"], p["pane_id"])
    tabs = [t["tab_id"] for t in herdr("tab", "list", "--workspace", workspace)["tabs"]]
    order = [my_tab] + [t for t in tabs if t != my_tab]
    return [(t, layout(first[t]) if t in first else None) for t in order]


def next_resize(lay, tolerance=2):
    """The one resize that fixes the leftmost column off its even width, as
    (pane_id, direction, amount); None when the columns are even within
    tolerance, there is one column, or no split owns that boundary."""
    cols = columns(lay)
    n = len(cols)
    if n < 2:
        return None
    target = lay["area"]["width"] / n
    for i in range(n - 1):
        delta = target - cols[i]["rect"]["width"]
        if abs(delta) <= tolerance:
            continue
        split = boundary_split(lay, cols[i], cols[i + 1])
        if split is None:
            return None
        amount = abs(delta) / split["rect"]["width"]
        if delta > 0:
            return cols[i]["pane_id"], "right", amount
        return cols[i + 1]["pane_id"], "left", amount
    return None


def even(pane_id):
    for attempt in range(12):
        lay = layout(pane_id)
        step = next_resize(lay)
        if step is None:
            print(f"even: widths={[c['rect']['width'] for c in columns(lay)]}")
            return
        pane, direction, amount = step
        subprocess.run(
            ["herdr", "pane", "resize", "--pane", pane,
             "--direction", direction, "--amount", f"{amount:.4f}"],
            capture_output=True, text=True, check=True,
        )
        widths = [c["rect"]["width"] for c in columns(lay)]
        print(f"pass {attempt}: widths={widths} -> {pane} {direction} {amount:.4f}")
    final = [c["rect"]["width"] for c in columns(layout(pane_id))]
    print(f"final widths={final}")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "pick":
        where = pick(sys.argv[3], tab_layouts(sys.argv[2], sys.argv[3]))
        if where:
            print(*where)
    elif len(sys.argv) == 3 and sys.argv[1] == "even":
        even(sys.argv[2])
    else:
        sys.exit("usage: placement.py pick <workspace_id> <my_tab_id> | even <pane_id>")
