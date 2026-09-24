#!/usr/bin/env python3
"""Equalize column widths in a herdr tab. Usage: equalize_columns.py <any_pane_id_in_tab>

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


def layout(pane_id):
    out = subprocess.run(
        ["herdr", "pane", "layout", "--pane", pane_id],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)["result"]["layout"]


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


def main():
    pane_id = sys.argv[1]
    tolerance = 2
    for attempt in range(12):
        lay = layout(pane_id)
        cols = columns(lay)
        n = len(cols)
        if n < 2:
            print("single column; nothing to equalize")
            return
        target = lay["area"]["width"] / n
        widths = [c["rect"]["width"] for c in cols]
        if all(abs(w - target) <= tolerance for w in widths):
            print(f"balanced: widths={widths} target={target:.1f}")
            return
        # Fix the leftmost boundary that is off; later boundaries settle after it.
        for i in range(n - 1):
            delta = target - cols[i]["rect"]["width"]
            if abs(delta) <= tolerance:
                continue
            split = boundary_split(lay, cols[i], cols[i + 1])
            if split is None:
                print(f"no split owns boundary {i}")
                return
            amount = abs(delta) / split["rect"]["width"]
            if delta > 0:
                pane, direction = cols[i]["pane_id"], "right"
            else:
                pane, direction = cols[i + 1]["pane_id"], "left"
            subprocess.run(
                ["herdr", "pane", "resize", "--pane", pane,
                 "--direction", direction, "--amount", f"{amount:.4f}"],
                capture_output=True, text=True, check=True,
            )
            print(f"pass {attempt}: widths={widths} -> {pane} {direction} {amount:.4f}")
            break
        else:
            break
    final = [c["rect"]["width"] for c in columns(layout(pane_id))]
    print(f"final widths={final}")


main()
