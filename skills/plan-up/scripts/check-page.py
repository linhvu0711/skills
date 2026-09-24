#!/usr/bin/env python3
"""Check a built plan page against its plan, before the person sees it.

    check-page.py <plan-slug.html> <plan-slug.md>

Reads the DATA the page embeds and checks:
- it parses and holds at least one layer;
- its Proof rows, slices, walks, videos and decided items match the .md, summed over layers;
- no string holds `[object`;
- no string holds an odd number of backticks, which the page would show raw.

Prints one line on pass and exits 0. Prints each problem and exits 1 otherwise.
"""
import json
import re
import sys


def load_data(html_path):
    html = open(html_path, encoding="utf-8").read()
    start = html.find("const DATA = ")
    if start < 0:
        sys.exit(f"{html_path}: no `const DATA = ` found")
    data, _ = json.JSONDecoder().raw_decode(html, start + len("const DATA = "))
    return data


def md_counts(md_path):
    md = open(md_path, encoding="utf-8").read()
    counts = {"proof": 0, "slices": 0, "walks": 0, "videos": 0, "decided": 0}
    block = None
    for line in md.splitlines():
        if line.startswith("## "):
            block = line[3:].strip().lower()
            continue
        if block == "proof" and re.match(r"\|\s*\d+\s*\|", line):
            counts["proof"] += 1
        elif block == "slices" and re.match(r"Slice \d+", line):
            counts["slices"] += 1
        elif block == "ui walks" and re.match(r"Walk \d+", line):
            counts["walks"] += 1
        elif block == "videos" and re.match(r"Video \d+", line):
            counts["videos"] += 1
        elif block == "decided" and line.startswith("- "):
            counts["decided"] += 1
    return counts


def strings(node, path="DATA"):
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield from strings(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from strings(v, f"{path}[{i}]")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    data = load_data(sys.argv[1])
    layers = data.get("layers") or []
    problems = []
    if not layers:
        problems.append("DATA.layers is empty")

    want = md_counts(sys.argv[2])
    have = {k: sum(len(L.get(k) or []) for L in layers) for k in want}
    for k in want:
        if have[k] != want[k]:
            problems.append(f"{k}: page has {have[k]}, .md has {want[k]}")

    for path, s in strings(data):
        if "[object" in s:
            problems.append(f"{path}: holds `[object`")
        if s.count("`") % 2:
            problems.append(f"{path}: odd number of backticks, one shows raw: {s[:80]}")

    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("page ok: " + " · ".join(f"{have[k]} {k}" for k in have))


if __name__ == "__main__":
    main()
