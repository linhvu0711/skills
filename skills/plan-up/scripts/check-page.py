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
- each Review block in the .md has its parts, each in its limit, and the page's `review` fields
  match it: one block for a ticket; a run has the stack's block and one small block per layer;
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


PART = re.compile(r"(Change|Approach|Blast radius|Choices|Risks|Works when|In|Out):\s*(.*)$")
BLAST = ["Touches", "Dependency", "Schema", "API", "Config", "CI"]
NEEDS = {
    "single": ["Change", "Approach", "Blast radius", "Choices", "Risks", "Works when", "In", "Out"],
    "stack": ["Change", "Approach", "Blast radius", "Risks", "In", "Out"],
    "layer": ["Change", "Choices", "Works when"],
}


def md_reviews(md_path):
    """Each `## Review` block, with its kind, its parts, and the Proof rows of its layer."""
    lines = open(md_path, encoding="utf-8").read().splitlines()
    is_run = any(l.startswith("## Layer ") or l.startswith("## Stack") for l in lines)
    reviews, proof_rows = [], [0]
    block, rv, part, layer = None, None, None, 0
    for line in lines:
        if line.startswith("## "):
            block = line[3:].strip().lower()
            if block.startswith("layer "):
                layer += 1
                proof_rows.append(0)
            rv = None
            if block == "review":
                kind = "single" if not is_run else ("stack" if layer == 0 else "layer")
                rv = {"kind": kind, "layer": layer, "parts": {}}
                reviews.append(rv)
            continue
        if block == "proof" and re.match(r"\|\s*\d+\s*\|", line):
            proof_rows[layer] += 1
        if rv is None or not line.strip():
            continue
        if (m := PART.match(line)):
            part = rv["parts"].setdefault(m.group(1), {"text": [], "items": [], "keys": {}})
            if m.group(2).strip():
                part["text"].append(m.group(2).strip())
        elif part is not None and line[:1].isspace():
            t = line.strip()
            if t.startswith("- "):
                part["items"].append(t[2:].strip())
            elif (k := re.match(r"(" + "|".join(BLAST) + r"):\s*(.*)$", t)):
                part["keys"][k.group(1)] = k.group(2).strip()
            else:
                part["text"].append(t)
    return reviews, proof_rows


def items(part):
    got = part["items"] if part else []
    return [] if [x.lower() for x in got] == ["none"] else got


def review_problems(reviews, proof_rows, data, layers):
    is_run = len(layers) > 1
    want = ["single"] if not is_run else ["stack"] + ["layer"] * len(layers)
    have = [r["kind"] for r in reviews]
    if have != want:
        yield f"review: the .md has {len(reviews)} `## Review` block(s), a {'run of ' + str(len(layers)) + ' layers' if is_run else 'ticket'} needs {len(want)}"
        return
    for r in reviews:
        name = "review" if r["kind"] == "single" else ("stack review" if r["kind"] == "stack" else f"layer {r['layer']} review")
        parts = r["parts"]
        for p in NEEDS[r["kind"]]:
            if p not in parts:
                yield f"{name}: no `{p}` part"
        for p, cap in [("Change", 2 if r["kind"] == "layer" else 4), ("Approach", 4), ("In", 4), ("Out", 4)]:
            if p in parts and len(parts[p]["text"]) > cap:
                yield f"{name}: `{p}` has {len(parts[p]['text'])} lines, the limit is {cap}"
            if p in parts and not parts[p]["text"]:
                yield f"{name}: `{p}` is empty"
        if "Blast radius" in parts:
            keys = parts["Blast radius"]["keys"]
            for k in BLAST:
                if not keys.get(k):
                    yield f"{name}: `Blast radius` has no `{k}` line"
        if "Choices" in parts:
            got = items(parts["Choices"])
            odd = [x for x in got if not re.match(r"(Fork|D\d+):", x)]
            if odd:
                yield f"{name}: each `Choices` line starts `Fork:` or `D<n>:`, not: {odd[0][:60]}"
            decided = [x for x in got if re.match(r"D\d+:", x)]
            if len(decided) > 3:
                yield f"{name}: `Choices` has {len(decided)} `Decided` lines, the limit is 3"
        if "Risks" in parts:
            got = items(parts["Risks"])
            if len(got) > 3:
                yield f"{name}: `Risks` has {len(got)} lines, the limit is 3"
            for x in got:
                if "If wrong:" not in x or "Proved:" not in x:
                    yield f"{name}: a risk needs `If wrong:` and `Proved:`: {x[:60]}"
        if "Works when" in parts:
            got = items(parts["Works when"])
            rows = proof_rows[r["layer"]]
            if len(got) != rows:
                yield f"{name}: `Works when` has {len(got)} lines, its Proof has {rows} rows"
            for j, x in enumerate(got, 1):
                if not x.startswith(f"#{j} "):
                    yield f"{name}: `Works when` line {j} must start `#{j} `"

    # The page against the .md.
    top = reviews[0]["parts"]
    rv = data.get("review") or {}
    for field, p in [("change", "Change"), ("approach", "Approach"), ("in", "In"), ("out", "Out")]:
        if p in top and not str(rv.get(field) or "").strip():
            yield f"DATA.review.{field} is empty"
    blast = rv.get("blast") or {}
    if not blast.get("touches"):
        yield "DATA.review.blast.touches is empty"
    for k in ["dependency", "schema", "api", "config", "ci"]:
        if not str(blast.get(k) or "").strip():
            yield f"DATA.review.blast.{k} is empty"
    md_risks = [re.search(r"Proved:\s*(P\d+|not proved)", x) for x in items(top.get("Risks"))]
    page_risks = rv.get("risks") or []
    if len(page_risks) != len(md_risks):
        yield f"review risks: page has {len(page_risks)}, .md has {len(md_risks)}"
    for j, (m, x) in enumerate(zip(md_risks, page_risks), 1):
        if m and str(x.get("proved") or "").strip() != m.group(1):
            yield f"review risk {j}: page says `{x.get('proved')}`, .md says `{m.group(1)}`"
    layer_reviews = reviews if not is_run else reviews[1:]
    for i, (r, L) in enumerate(zip(layer_reviews, layers), 1):
        lr = L.get("review") or {}
        name = "DATA.layers[%d].review" % (i - 1)
        if is_run and not str(lr.get("change") or "").strip():
            yield f"{name}.change is empty"
        md_refs = [(re.match(r"(D\d+):", x).group(1) if re.match(r"D\d+:", x) else None) for x in items(r["parts"].get("Choices"))]
        page_refs = [c.get("ref") or None for c in lr.get("choices") or []]
        if page_refs != md_refs:
            yield f"{name}.choices: page refs {page_refs}, .md refs {md_refs}"
        md_works = len(items(r["parts"].get("Works when")))
        if len(lr.get("works") or []) != md_works:
            yield f"{name}.works: page has {len(lr.get('works') or [])}, .md has {md_works}"


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
    reviews, proof_rows = md_reviews(sys.argv[2])
    problems.extend(review_problems(reviews, proof_rows, data, layers))
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
    print("page ok: " + " · ".join(f"{have[k]} {k}" for k in have) + f" · {len(reviews)} review")


if __name__ == "__main__":
    main()
