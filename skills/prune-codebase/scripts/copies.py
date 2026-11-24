#!/usr/bin/env python3
"""Print each group of the same code in two or more places.

    copies.py < <paths>

Reads file paths on stdin, one per line, from the repo root. A path that
is not a file or not UTF-8 text is skipped. Lines are compared with their
whitespace collapsed; a blank line, and a line with no letter or digit
(a lone `}` or `);`), is skipped. Six compared lines in a row that come
back at another place, not overlapping in one file, are a copy, and the
lines that go on together at every place join it. One line per group,
sorted by its first place:

    <n> lines: <path>:<start>-<end> <path>:<start>-<end>

`<n>` counts the compared lines; `<start>` and `<end>` are the file's own
line numbers. Exits 0, with no line when there is no copy.
"""
import sys
from collections import defaultdict

# Fewer lines match boilerplate, such as a run of imports.
MIN = 6


def compared(path):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError):
        return []
    lines = []
    for number, line in enumerate(text.splitlines(), 1):
        norm = " ".join(line.split())
        if any(ch.isalnum() for ch in norm):
            lines.append((number, norm))
    return lines


def main():
    files = {}
    for raw in sys.stdin:
        path = raw.strip()
        if path and path not in files:
            files[path] = compared(path)

    windows = defaultdict(list)
    for path, lines in files.items():
        for i in range(len(lines) - MIN + 1):
            windows[tuple(norm for _, norm in lines[i:i + MIN])].append((path, i))

    groups = set()
    for places in windows.values():
        kept, last = [], {}
        for path, i in places:
            if path in last and i - last[path] < MIN:
                continue
            kept.append((path, i))
            last[path] = i
        if len(kept) > 1:
            groups.add(tuple(sorted(kept)))

    def shift(group, by):
        return tuple((path, i + by) for path, i in group)

    found = []
    for group in groups:
        if shift(group, -1) in groups:
            continue
        starts = defaultdict(list)
        for path, i in group:
            starts[path].append(i)
        gap = min((b - a for s in starts.values() for a, b in zip(s, s[1:])), default=float("inf"))
        length = 1
        while MIN + length <= gap and shift(group, length) in groups:
            length += 1
        n = MIN + length - 1
        spans = [f"{path}:{files[path][i][0]}-{files[path][i + n - 1][0]}" for path, i in group]
        found.append((group[0][0], files[group[0][0]][group[0][1]][0], f"{n} lines: {' '.join(spans)}"))

    for _, _, line in sorted(found):
        print(line)


if __name__ == "__main__":
    main()
