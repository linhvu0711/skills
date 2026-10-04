#!/usr/bin/env python3
"""Build a plan page from its Markdown, the only source of the page.

    build-page.py <plan-slug.md>

Prints `page: <html path>` and exits 0. Prints each problem and exits 1
without changing the old page when a block is bad.
"""
import json
import os
import re
import sys
from pathlib import Path


FACTS = "Repo Base Test Typecheck Lint Build Run UI Open Screen Platform Standards".split()
PART = re.compile(r"(Change|Approach|Blast radius|Choices|Risks|Works when|In|Out):\s*(.*)$")
BLAST = ["Touches", "Dependency", "Schema", "API", "Config", "CI"]
CHANGES = {"new", "changed", "removed", "same"}
KINDS = {"part", "store", "outside"}
NEEDS = {
    "single": ["Change", "Approach", "Blast radius", "Choices", "Risks", "Works when", "In", "Out"],
    "stack": ["Change", "Approach", "Blast radius", "Risks", "In", "Out"],
    "layer": ["Change", "Choices", "Works when"],
}
# The longest text that fits a map box or a flow label in shell.html. plan.md points here.
NAME_MAX, JOB_MAX, LABEL_MAX = 20, 30, 20
PROVED = re.compile(r"P\d+ (.*): (.*), (\d{4}-\d{2}-\d{2})\. Used by (.+)\.$")
FLOW = re.compile(r"-\s*(M\d+)\s*(?:→|->)\s*(M\d+):\s*(.*?)\s*(?:\(([^)]*)\))?\s*$")
LAYER = re.compile(r"Layer (\d+) · #(\d+) (.+)$")
REFS = r"#\d+(?:,\s*#\d+)*"
RECORD = {
    "slice": re.compile(rf"Slice \d+, proves ({REFS}):\s*(.+)"),
    "walk": re.compile(rf"Walk \d+, proves ({REFS})"),
    "video": re.compile(r"Video \d+, (Setup of walk (\d+)), shows walks (\d+(?:,\s*\d+)*)"),
}


def blocks(lines):
    got = [("head", [])]
    for line in lines:
        if line.startswith("## "):
            got.append((line[3:].strip(), []))
        else:
            got[-1][1].append(line)
    return got


def sections(lines):
    top, layers, current = {}, [], None
    for name, body in blocks(lines):
        if (m := LAYER.fullmatch(name)):
            current = {}
            layers.append((m, current))
        elif current is None:
            top[name] = body
        else:
            current[name] = body
    return top, layers


def text(lines):
    return " ".join(line.strip() for line in lines if line.strip())


def key_values(lines, keys):
    pattern = re.compile(r"(?:^|\s{2,})(" + "|".join(keys) + r"):\s*")
    values, last, indent = {}, None, 0
    for line in lines:
        pairs = list(pattern.finditer(line))
        if pairs:
            indent = len(line) - len(line.lstrip())
            for i, pair in enumerate(pairs):
                last = pair.group(1).lower()
                end = pairs[i + 1].start() if i + 1 < len(pairs) else len(line)
                values[last] = line[pair.end():end].strip()
        elif last and line.strip() and len(line) - len(line.lstrip()) > indent:
            values[last] += " " + line.strip()
    return values


def list_items(lines):
    got = []
    for line in lines:
        if line.startswith("- "):
            got.append(line[2:].strip())
        elif got and line[:1].isspace() and line.strip():
            got[-1] += " " + line.strip()
    return got


def table_rows(lines):
    for line in lines:
        if line.strip().startswith("|"):
            yield [c.strip().replace(r"\|", "|") for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]


def stack_rows(lines):
    return [r for r in table_rows(lines) if r and r[0] != "Layer" and not re.fullmatch(r":?-+:?", r[0])]


def md_reviews(lines):
    is_run = any(l == "## Stack" for l in lines)
    reviews, proof_rows = [], [0]
    block, rv, part, layer, last = None, None, None, 0, None
    for line in lines:
        if line.startswith("## "):
            block = line[3:].strip().lower()
            if block.startswith("layer "):
                layer += 1
                proof_rows.append(0)
            rv, part, last = None, None, None
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
            last = None
            if m.group(2).strip():
                part["text"].append(m.group(2).strip())
        elif part is not None and line[:1].isspace():
            t = line.strip()
            if t.startswith("- "):
                part["items"].append(t[2:].strip())
                last = (part["items"], len(part["items"]) - 1)
            elif (k := re.match(r"(" + "|".join(BLAST) + r"):\s*(.*)$", t)):
                part["keys"][k.group(1)] = k.group(2).strip()
                last = (part["keys"], k.group(1))
            elif last:
                last[0][last[1]] += " " + t
            else:
                part["text"].append(t)
    return reviews, proof_rows


def items(part):
    got = part["items"] if part else []
    return [] if [x.lower() for x in got] == ["none"] else got


def top_review(parts):
    rv = {k: text(parts.get(p, {}).get("text", [])) for k, p in
          [("change", "Change"), ("approach", "Approach"), ("in", "In"), ("out", "Out")]}
    blast = parts.get("Blast radius", {}).get("keys", {})
    rv["blast"] = {k.lower(): blast.get(k, "") for k in BLAST if k != "Touches"}
    rv["blast"]["touches"] = blast.get("Touches", "").split(", ")
    rv["risks"] = []
    for risk in items(parts.get("Risks")):
        belief, _, rest = risk.partition(" If wrong:")
        wrong, _, proved = rest.partition(" Proved:")
        rv["risks"].append({"belief": belief, "ifWrong": wrong.strip().removesuffix("."), "proved": proved.strip()})
    return rv


def layer_review(parts):
    choices = []
    forks = []
    for item in items(parts.get("Choices")):
        ref, _, value = item.partition(": ")
        choices.append({"ref": None if ref == "Fork" else ref, "text": value})
        if ref == "Fork":
            question, _, pick = value.partition(" → ")
            forks.append({"question": question, "pick": pick.removesuffix(" (user)")})
    return {"choices": choices, "works": [re.sub(r"^#\d+\s+", "", x) for x in items(parts.get("Works when"))]}, forks


def md_maps(lines):
    got, cur, header, in_flows = [], None, None, False
    for line in lines:
        if line.startswith("## "):
            head = line[3:].strip()
            cur = None
            if head.lower().startswith("change map"):
                area = head.split("·", 1)[1].strip() if "·" in head else ""
                cur = {"area": area, "none": False, "parts": [], "flows": []}
                got.append(cur)
                header, in_flows = None, False
            continue
        if cur is None or not line.strip():
            continue
        t = line.strip()
        if t.lower().startswith("none:"):
            cur["none"] = t
        elif t.startswith("|"):
            cells = next(table_rows([t]))
            if cells and cells[0] == "Ref":
                header = cells
            elif header and cells and re.match(r"M\d+$", cells[0]):
                cur["parts"].append(dict(zip(header, cells)))
        elif t.lower().startswith("flows:"):
            in_flows = True
        elif in_flows and t.startswith("-"):
            m = FLOW.match(t)
            if not m:
                cur["flows"].append({"bad": t})
                continue
            tags = [x.strip() for x in (m.group(4) or "").split(",") if x.strip()]
            cur["flows"].append({"from": m.group(1), "to": m.group(2), "label": m.group(3),
                                 "change": next((x for x in tags if x in CHANGES), "same"),
                                 "layer": next((x for x in tags if re.match(r"L\d+$", x)), None)})
    return got


def grid(cell):
    m = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*", cell or "")
    return tuple(float(x) for x in m.groups()) if m else None


def page_maps(maps):
    got = []
    for m in maps:
        if m["none"]:
            continue
        parts = []
        for p in m["parts"]:
            at = p.get("At", "")
            xy = grid(p.get("Grid")) or (0.0, 0.0)
            parts.append({"ref": p.get("Ref"), "name": p.get("Part"), "job": p.get("Job"),
                          "change": p.get("Change"), "group": p.get("Group", ""), "kind": p.get("Kind"),
                          "at": [re.sub(r"^`(.*)`$", r"\1", entry.strip()) for entry in at.split(",") if entry.strip()],
                          "x": int(xy[0]) if xy[0].is_integer() else xy[0],
                          "y": int(xy[1]) if xy[1].is_integer() else xy[1], "layer": p.get("Layer") or None})
        got.append({"area": m["area"], "parts": parts, "flows": [f for f in m["flows"] if "bad" not in f]})
    return got


def proves(value):
    return [int(x) for x in re.findall(r"#(\d+)", value)]


def records(lines, kind):
    got, current, last = [], None, None
    for line in lines:
        t = line.strip()
        if kind == "slice" and (m := RECORD[kind].fullmatch(t)):
            current = {"seam": m.group(2), "proves": proves(m.group(1)), "change": [], "docs": [], "tests": []}
            got.append(current)
            last = None
        elif kind == "walk" and (m := RECORD[kind].fullmatch(t)):
            current = {"proves": proves(m.group(1)), "steps": []}
            got.append(current)
            last = None
        elif kind == "video" and (m := RECORD[kind].fullmatch(t)):
            current = {"title": m.group(1), "setup": "walk " + m.group(2),
                       "walks": [int(x) for x in re.findall(r"\d+", m.group(3))], "steps": []}
            got.append(current)
            last = None
        elif current is None or not t:
            continue
        elif kind == "slice" and (m := re.match(r'Test `([^`]+)` "(.*)"$', t)):
            current["tests"].append({"file": m.group(1), "name": m.group(2)})
            last = None
        elif kind == "video" and (m := re.match(r"\d+\.\s*(.*)", t)):
            current["steps"].append(m.group(1))
            last = (current["steps"], len(current["steps"]) - 1)
        elif (m := re.match(r"(Change|Docs|Given|When|Then|Setup|Where|Steps|See|Must not|Before|Shows):\s*(.*)", t)):
            key, value = m.group(1).lower().replace("must not", "mustNot"), m.group(2)
            target = current["tests"][-1] if key in ("given", "when", "then") and current.get("tests") else current
            if key in ("change", "docs", "steps"):
                target[key].append(value)
                last = (target[key], len(target[key]) - 1)
            else:
                target[key] = value
                last = (target, key)
        elif last and line[:1].isspace():
            last[0][last[1]] += " " + t
    return got


def page_layer(section, issue, title, parts):
    review, forks = layer_review(parts)
    rows = [r for r in table_rows(section.get("Proof", [])) if r and r[0].isdigit()]
    proof = []
    for r in rows:
        if len(r) != 6:
            continue
        w = re.search(r"walk (\d+)", r[3])
        proof.append({"line": r[1], "test": None if r[2] == "none" else r[2],
                      "walk": int(w.group(1)) if w else None, "video": None if r[4] == "none" else r[4], "artifact": r[5]})
    seams = []
    for item in list_items(section.get("Seams", [])):
        m = re.match(r"(.*?):\s*(?:`([^`]+)`|(layer \d+, slice \d+))\s*,\s*(.*)", item)
        if m:
            seams.append({"name": m.group(1), "at": m.group(2) or m.group(3), "why": m.group(4)})
    decided = []
    for item in list_items(section.get("Decided", [])):
        what, _, why = re.sub(r"^D\d+ ", "", item).partition(": ")
        decided.append({"what": what, "why": why})
    gates = key_values(section.get("Gates", []), ["Slice done", "Task done"])
    return {"issue": issue, "title": title, "summary": text(section.get("Summary", [])), "review": review,
            "forks": forks, "seams": seams, "proof": proof, "slices": records(section.get("Slices", []), "slice"),
            "walks": records(section.get("UI walks", []), "walk"), "videos": records(section.get("Videos", []), "video"),
            "gates": {"slice": gates.get("slice done", ""), "task": gates.get("task done", "")},
            "decided": decided, "out": [re.sub(r"^O\d+ ", "", x) for x in list_items(section.get("Out of scope", []))]}


def page_data(lines):
    section, layer_sections = sections(lines)
    head = key_values(section["head"], ["Size", "Date"])
    m = next((re.match(r"# Plan: #(\d+) (.*)", l) for l in lines if l.startswith("# Plan: #")), None)
    number, title = (int(m.group(1)), m.group(2)) if m else (0, "")
    facts = key_values(section.get("Facts", []), FACTS)
    issue = {"number": number, "url": f"https://github.com/{facts.get('repo', '')}/issues/{number}", "size": head.get("size", "")}
    reviews, _ = md_reviews(lines)
    parts = reviews[0]["parts"] if reviews else {}
    proved = []
    for item in list_items(section.get("Proved", [])):
        m = PROVED.fullmatch(item)
        if m:
            proved.append(dict(zip(["fact", "ran", "date", "usedBy"], m.groups())))
    is_run = "Stack" in section
    layers = []
    if is_run:
        stack = {int(r[0]): r for r in stack_rows(section["Stack"]) if r[0].isdecimal()}
        for i, (heading, body) in enumerate(layer_sections, 1):
            row = stack.get(int(heading.group(1)), [])
            layer_issue = {"number": int(heading.group(2)),
                           "url": f"https://github.com/{facts.get('repo', '')}/issues/{heading.group(2)}",
                           "size": row[3] if len(row) > 3 else ""}
            review = next((r["parts"] for r in reviews if r["kind"] == "layer" and r["layer"] == i), {})
            layer = page_layer(body, layer_issue, heading.group(3), review)
            layer["review"]["change"] = text(review.get("Change", {}).get("text", []))
            layer["targets"] = row[2] if len(row) > 2 else ""
            layer["points"] = int(row[4]) if len(row) > 4 and row[4].isdecimal() else 0
            layers.append(layer)
    else:
        layers.append(page_layer(section, dict(issue), title, parts))
    kind = re.match(r"\[([^]]+)\]", title)
    if kind:
        issue["kind"] = kind.group(1)
    data = {"title": title, "issue": issue, "date": head.get("date", ""), "run": is_run,
            "review": top_review(parts), "maps": page_maps(md_maps(lines)), "facts": facts, "proved": proved, "layers": layers}
    if is_run:
        data["points"] = key_values(section["Stack"], ["Points"]).get("points", "")
    no_map = next((m["none"] for m in md_maps(lines) if m["none"]), None)
    if no_map:
        data["noMap"] = no_map
    return data


def review_problems(reviews, proof_rows, is_run, layer_count):
    run_name = f"run of {layer_count} layer{'s' if layer_count != 1 else ''}"
    want = ["single"] if not is_run else ["stack"] + ["layer"] * layer_count
    have = [r["kind"] for r in reviews]
    if have != want:
        yield f"review: the .md has {len(reviews)} `## Review` block(s), a {run_name if is_run else 'ticket'} needs {len(want)}"
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


def map_problems(blocks, is_run):
    if not blocks:
        yield "change map: the .md has no `## Change map` block; write a map, or `None: no part or flow changes.`"
        return
    if any(b["none"] for b in blocks):
        if len(blocks) > 1 or blocks[0]["parts"] or blocks[0]["flows"]:
            yield "change map: a `None:` line stands alone, with no map beside it"
        return
    if len(blocks) > 2:
        yield f"change map: {len(blocks)} maps, the limit is 2"
    seen = set()
    for n, b in enumerate(blocks, 1):
        name = f"change map {n}" if len(blocks) > 1 else "change map"
        parts = b["parts"]
        if not parts:
            yield f"{name}: no parts"
        if len(parts) > 12:
            yield f"{name}: {len(parts)} parts, the limit is 12; merge the `same` ones first"
        refs, cells = {}, {}
        for p in parts:
            ref = p.get("Ref", "?")
            if ref in seen:
                yield f"{name}: {ref} is used twice"
            seen.add(ref)
            refs[ref] = p
            if not p.get("Part") or not p.get("Job"):
                yield f"{name}: {ref} needs a part name and a job"
            if len(p.get("Part") or "") > NAME_MAX:
                yield f"{name}: {ref} part name is {len(p['Part'])} characters, the limit is {NAME_MAX}"
            if len(p.get("Job") or "") > JOB_MAX:
                yield f"{name}: {ref} job is {len(p['Job'])} characters, the limit is {JOB_MAX}"
            if p.get("Change") not in CHANGES:
                yield f"{name}: {ref} change `{p.get('Change')}` is not new, changed, removed, or same"
            if p.get("Kind") not in KINDS:
                yield f"{name}: {ref} kind `{p.get('Kind')}` is not part, store, or outside"
            if p.get("Kind") != "outside" and not (p.get("At") or "").strip():
                yield f"{name}: {ref} has no files and no slice in `At`"
            g = grid(p.get("Grid"))
            if g is None:
                yield f"{name}: {ref} grid `{p.get('Grid')}` is not `column,row` with both 0 or more"
            elif g in cells:
                yield f"{name}: {ref} and {cells[g]} share the grid cell {p.get('Grid')}"
            else:
                cells[g] = ref
            if is_run and p.get("Change") != "same" and not re.match(r"L\d+$", p.get("Layer") or ""):
                yield f"{name}: {ref} is {p.get('Change')} but names no layer"
        # A group's gray area spans its cells; a part of no such group inside it misstates the map.
        groups = {}
        for p in parts:
            if p.get("Group") and grid(p.get("Grid")):
                groups.setdefault(p["Group"], []).append(grid(p["Grid"]))
        for gname, gcells in groups.items():
            xs, ys = [c[0] for c in gcells], [c[1] for c in gcells]
            for c, ref in cells.items():
                if refs[ref].get("Group") != gname and min(xs) <= c[0] <= max(xs) and min(ys) <= c[1] <= max(ys):
                    yield f"{name}: {ref} sits inside the area of group `{gname}`; put the group's parts in cells next to each other"
        touched = set()
        for f in b["flows"]:
            if "bad" in f:
                yield f"{name}: a flow line is not `- M1 → M2: what moves (change)`: {f['bad'][:60]}"
                continue
            for end in (f["from"], f["to"]):
                if end not in refs:
                    yield f"{name}: flow {f['from']} → {f['to']} names {end}, which is not a part of this map"
            if not f["label"] or re.fullmatch(r"imports?", f["label"].strip(), re.I):
                yield f"{name}: flow {f['from']} → {f['to']} must name what moves, not `{f['label']}`"
            elif len(f["label"].strip()) > LABEL_MAX:
                yield f"{name}: flow {f['from']} → {f['to']} label is {len(f['label'].strip())} characters, the limit is {LABEL_MAX}"
            if f["change"] != "same":
                touched.update((f["from"], f["to"]))
                if is_run and not f["layer"]:
                    yield f"{name}: flow {f['from']} → {f['to']} is {f['change']} but names no layer"
        for ref, p in refs.items():
            if p.get("Change") == "same" and ref not in touched:
                yield f"{name}: {ref} has no change and no changed flow touches it; leave it out"


def before_kind(value):
    v = value.strip().strip("`").strip().lower()
    if not v:
        return "blank"
    if v.startswith("none"):
        return "none"
    m = re.match(r"as walk (\d+)\b", v)
    return f"as walk {m.group(1)}" if m else "steps"


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


def stack_problems(lines, layers):
    rows = stack_rows(lines)
    if len(rows) != len(layers):
        yield f"stack: {len(rows)} rows, {len(layers)} `## Layer` headings"
        return
    for n, (row, (heading, _)) in enumerate(zip(rows, layers), 1):
        if int(heading.group(1)) != n:
            yield f"stack: layer heading {heading.group(1)} is not layer {n}"
        if len(row) != 5:
            yield f"stack: row {n} has {len(row)} cells, needs 5"
            continue
        if row[0] != str(n):
            yield f"stack: row {n} names layer {row[0]}, needs {n}"
        issue = f"#{heading.group(2)} {heading.group(3)}"
        if row[1] != issue:
            yield f"stack: row {n} issue `{row[1]}` is not `{issue}`"
        if not row[2]:
            yield f"stack: row {n} has no base"
        if not re.fullmatch(r"XS|S|M|L|XL", row[3]):
            yield f"stack: row {n} size `{row[3]}` is not XS, S, M, L, or XL"
        if not row[4].isdecimal():
            yield f"stack: row {n} points `{row[4]}` is not an integer"


def record_problems(section):
    for block, kind, form in [
        ("Slices", "slice", "Slice <n>, proves #<n>: <seam>"),
        ("UI walks", "walk", "Walk <n>, proves #<n>"),
        ("Videos", "video", "Video <n>, Setup of walk <n>, shows walks <n>"),
    ]:
        for line in section.get(block, []):
            t = line.strip()
            heading = not line[:1].isspace() or re.match(r"(Slice|Walk|Video)\b", t)
            if t and heading and not RECORD[kind].fullmatch(t):
                name = block if block == "UI walks" else block.lower()
                yield f"{name}: {t} is not a `{form}` heading"


def plan_problems(lines):
    section, layer_sections = sections(lines)
    is_run = "Stack" in section
    head = key_values(section["head"], ["Size", "Date"])
    if not any(re.fullmatch(r"# Plan: #\d+ .+", l) for l in section["head"]):
        yield "head: no `# Plan: #<n>` line"
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", head.get("date", "")):
        yield "head: no `Date: YYYY-MM-DD` line under `# Plan:`"
    if not is_run and not re.fullmatch(r"size/(XS|S|M|L|XL)", head.get("size", "")):
        yield "head: a ticket needs `Size: size/<x>`"
    layers = [body for _, body in layer_sections] if is_run else [section]
    if is_run:
        yield from stack_problems(section["Stack"], layer_sections)
    reviews, proof_rows = md_reviews(lines)
    yield from review_problems(reviews, proof_rows, is_run, len(layers))
    yield from map_problems(md_maps(lines), is_run)
    for n, body in enumerate(layers, 1):
        yield from record_problems(body)
        for row in table_rows(body.get("Proof", [])):
            if row and row[0].isdigit() and len(row) != 6:
                yield f"proof: layer {n} row {row[0]} has {len(row)} cells, needs 6"
        summary = [l for l in body.get("Summary", []) if l.strip()]
        if not summary:
            yield f"summary: layer {n} has no `## Summary` block"
        elif len(summary) > 3:
            yield f"summary: layer {n} has {len(summary)} lines, the limit is 3"
    for item in list_items(section.get("Proved", [])):
        if not PROVED.fullmatch(item):
            ref = item.split()[0]
            yield f"proved: {ref} needs `, <YYYY-MM-DD>. Used by <refs>.` at its end"
    walks = []
    for n, body in enumerate(layers, 1):
        numbers = [int(l.split()[1].rstrip(",")) for l in body.get("UI walks", []) if RECORD["walk"].fullmatch(l.strip())]
        for number, walk in zip(numbers, records(body.get("UI walks", []), "walk")):
            walks.append({"layer": n, "n": number, "kind": before_kind(walk["before"]) if "before" in walk else None})
    yield from md_before_problems(walks)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = Path(sys.argv[1])
    lines = path.read_text(encoding="utf-8").splitlines()
    if "## Review" not in lines:
        print(f"not a plan-up .md: {path.name}")
        sys.exit(1)
    problems = list(plan_problems(lines))
    data = page_data(lines)
    problems.extend(f"{p}: odd number of backticks, one shows raw: {s[:80]}"
                    for p, s in strings(data) if s.count("`") % 2)
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    shell = (Path(__file__).resolve().parent.parent / "assets/shell.html").read_text(encoding="utf-8")
    output = path.with_suffix(".html")
    tmp = output.with_suffix(".html.tmp")
    payload = json.dumps(data, ensure_ascii=False).replace("</", r"<\/")
    try:
        tmp.write_text(shell.replace("const DATA = {};", "const DATA = " + payload + ";"), encoding="utf-8")
        os.replace(tmp, output)
    finally:
        if tmp.exists():
            tmp.unlink()
    print(f"page: {output}")


if __name__ == "__main__":
    main()
