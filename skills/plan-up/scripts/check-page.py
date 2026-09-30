#!/usr/bin/env python3
"""Check a built plan page against its plan, before the person sees it.

    check-page.py <plan-slug.html> <plan-slug.md>

Reads the DATA the page embeds and checks:
- it parses and holds at least one layer;
- its Proof rows, slices, walks, videos and decided items match the .md, summed over layers;
- each slice's `docs` name the same files, in order, as that slice's .md `Docs:` lines;
- its proved lines match the .md `## Proved` block, in order, by date and `Used by`;
- each walk has a `before` that is the same kind as its .md `Before` line: none, as walk n, or steps;
  no `Before` is blank, and `as walk n` names an earlier walk of the same layer whose `Before` names steps;
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


def before_kind(value):
    v = value.strip().strip("`").strip().lower()
    if not v:
        return "blank"
    if v.startswith("none"):
        return "none"
    m = re.match(r"as walk (\d+)\b", v)
    return f"as walk {m.group(1)}" if m else "steps"


def first_code(s):
    m = re.search(r"`([^`]+)`", s or "")
    return m.group(1) if m else (s or "").strip()


def proved_key(date, used_by):
    return (str(date or "").strip(), re.sub(r"\s+", " ", str(used_by or "")).strip(" ."))


def md_counts(md_path):
    md = open(md_path, encoding="utf-8").read()
    counts = {"proof": 0, "slices": 0, "walks": 0, "videos": 0, "decided": 0, "docs": 0, "proved": 0}
    walks = []
    docs = []  # per slice, in order over layers: the file each Docs line names
    proved = []  # the text of each P line, wrapped lines joined
    layer = 1
    block = None
    for line in md.splitlines():
        if line.startswith("## "):
            block = line[3:].strip().lower()
            if block.startswith("layer ") and walks:
                layer += 1
            continue
        if block == "proof" and re.match(r"\|\s*\d+\s*\|", line):
            counts["proof"] += 1
        elif block == "slices" and re.match(r"Slice \d+", line):
            counts["slices"] += 1
            docs.append([])
        elif block == "slices" and docs and (m := re.match(r"\s+Docs:\s*(.*)", line)):
            counts["docs"] += 1
            docs[-1].append(first_code(m.group(1)))
        elif block == "proved" and re.match(r"- P\d+", line):
            counts["proved"] += 1
            proved.append(line)
        elif block == "proved" and proved and line.startswith("  "):
            proved[-1] += " " + line.strip()
        elif block == "ui walks" and (m := re.match(r"Walk (\d+)", line)):
            counts["walks"] += 1
            walks.append({"layer": layer, "n": int(m.group(1)), "kind": None})
        elif block == "ui walks" and walks and (m := re.match(r"\s*Before:\s*(.*)", line)):
            walks[-1]["kind"] = before_kind(m.group(1))
        elif block == "videos" and re.match(r"Video \d+", line):
            counts["videos"] += 1
        elif block == "decided" and line.startswith("- "):
            counts["decided"] += 1
    keys = []
    for p in proved:
        m = re.search(r"(\d{4}-\d{2}-\d{2})\.?\s*Used by\s+(.*)$", p)
        keys.append(proved_key(m.group(1), m.group(2)) if m else ("?", p))
    return counts, walks, docs, keys


def md_before_problems(walks):
    runs = len({w["layer"] for w in walks}) > 1
    for w in walks:
        name = f"layer {w['layer']} walk {w['n']}" if runs else f"walk {w['n']}"
        kind = w["kind"]
        if kind is None:
            yield f"{name}: the .md has no `Before` line"
        elif kind == "blank":
            yield f"{name}: the .md `Before` line is blank"
        elif kind.startswith("as walk "):
            t = int(kind.split()[-1])
            target = next((x for x in walks if x["layer"] == w["layer"] and x["n"] == t), None)
            if t >= w["n"] or target is None or target["kind"] != "steps":
                yield f"{name}: `{kind}` must name an earlier walk of its layer whose `Before` names steps"


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

    want, md_walks, md_docs, md_proved = md_counts(sys.argv[2])
    have = {k: sum(len(L.get(k) or []) for L in layers) for k in want}
    have["docs"] = sum(len(s.get("docs") or []) for L in layers for s in L.get("slices") or [])
    have["proved"] = len(data.get("proved") or [])
    for k in want:
        if have[k] != want[k]:
            problems.append(f"{k}: page has {have[k]}, .md has {want[k]}")

    slices = [x for L in layers for x in L.get("slices") or []]
    for i, (want_docs, sl) in enumerate(zip(md_docs, slices), 1):
        have_docs = [first_code(x) for x in sl.get("docs") or []]
        if have_docs != want_docs:
            problems.append(f"slice {i} docs: page names {have_docs}, .md names {want_docs}")
    for i, (want_p, p) in enumerate(zip(md_proved, data.get("proved") or []), 1):
        have_p = proved_key(p.get("date"), p.get("usedBy"))
        if have_p != want_p:
            problems.append(f"P{i}: page has {have_p}, .md has {want_p}")

    problems.extend(md_before_problems(md_walks))
    walks = [w for L in layers for w in L.get("walks") or []]
    for i, (md_walk, walk) in enumerate(zip(md_walks, walks), 1):
        before = walk.get("before")
        if not isinstance(before, str):
            problems.append(f"DATA walk {i}: no `before`")
        elif before_kind(before) == "blank":
            problems.append(f"DATA walk {i}: `before` is blank")
        elif md_walk["kind"] and before_kind(before) != md_walk["kind"]:
            problems.append(f"DATA walk {i}: page says `{before_kind(before)}`, .md says `{md_walk['kind']}`")

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
