"""Read a plan .md once, into the values build-page.py and prune.py use, and
judge it against every line shape and limit of references/plan.md.

    plan = plan_reader.read(path)
    for line in plan_reader.problems(plan): ...

The plan is one dict of text, lists of text, key-value dicts, table rows as
cell lists, and records, in the shape of references/plan.md. Any text reads
without an error: a missing block reads as empty. `problems` names each bad
line, every one, in the order the builder prints them.
"""
import re
from pathlib import Path


FACTS = "Repo Base Test Typecheck Lint Build Run UI Open Screen Platform Standards".split()
PERF = ["Metric", "Command", "Before", "Pass rule"]
PART = re.compile(r"(Change|Approach|Blast radius|Choices|Risks|Works when|In|Out):\s*(.*)$")
BLAST = ["Touches", "Dependency", "Schema", "API", "Config", "CI"]
CHANGES = {"new", "changed", "removed", "same"}
FLOW = re.compile(r"-\s*(M\d+)\s*(?:→|->)\s*(M\d+):\s*(.*?)\s*(?:\(([^)]*)\))?\s*$")
LAYER = re.compile(r"Layer (\d+) · #(\d+) (.+)$")
# A list of numbers as English writes it: `1, 2`, `1 and 2`, or `1, 2, and 3`.
JOIN = r"(?:,\s*(?:and\s+)?|\s+and\s+)"
REFS = rf"#\d+(?:{JOIN}#\d+)*"
RECORD = {
    "slice": re.compile(rf"Slice \d+, (?:proves ({REFS})|(deletes dead code)):\s*(.+)"),
    "walk": re.compile(rf"Walk \d+, proves ({REFS})"),
    "video": re.compile(rf"Video \d+, (Setup of walk (\d+)), shows walks? (\d+(?:{JOIN}\d+)*)"),
}
KINDS = {"part", "store", "outside"}
NEEDS = {
    "single": ["Change", "Approach", "Blast radius", "Choices", "Risks", "Works when", "In", "Out"],
    "stack": ["Change", "Approach", "Blast radius", "Risks", "In", "Out"],
    "layer": ["Change", "Choices", "Works when"],
}
PROVED = re.compile(r"P\d+ (.*): (.*), (\d{4}-\d{2}-\d{2})\. Used by (.+)\.$")
# The longest text that fits a map box or a flow label in shell.html.
NAME_MAX, JOB_MAX, LABEL_MAX = 20, 30, 20
# The most lines a Review part, a run layer's Change, and a layer's Summary hold.
LINES_MAX, LAYER_CHANGE_MAX, SUMMARY_MAX = 4, 2, 3
# The most Decided lines in Choices, Risks, maps, and parts in one map.
DECIDED_MAX, RISKS_MAX, MAPS_MAX, PARTS_MAX = 3, 3, 2, 12


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


def reviews(named, run):
    got, layer = [], 0
    for name, body in named:
        if LAYER.fullmatch(name):
            layer += 1
        if name.lower() != "review":
            continue
        kind = "single" if not run else ("stack" if layer == 0 else "layer")
        rv = {"kind": kind, "layer": layer, "parts": {}}
        got.append(rv)
        part, last = None, None
        for line in body:
            if not line.strip():
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
        rv["parts"] = {name: review_part(name, raw) for name, raw in rv["parts"].items()}
    return got


def listed(raw):
    # A lone `- none` says the part was checked and holds nothing.
    return [] if [x.lower() for x in raw["items"]] == ["none"] else raw["items"]


def choice(line):
    ref, _, text = line.partition(": ")
    fork = None
    if ref == "Fork":
        question, _, pick = text.partition(" → ")
        fork = {"question": question, "pick": pick.removesuffix(" (user)")}
    return {"line": line, "ref": None if ref == "Fork" else ref, "text": text, "fork": fork}


def risk(line):
    belief, _, rest = line.partition(" If wrong:")
    wrong, _, proved = rest.partition(" Proved:")
    return {"line": line, "belief": belief, "ifWrong": wrong.strip().removesuffix("."), "proved": proved.strip()}


def works(line):
    m = re.match(r"#(\d+)\s", line)
    return {"line": line, "n": int(m.group(1)) if m else None, "text": re.sub(r"^#\d+\s+", "", line)}


def review_part(name, raw):
    """One Review part as its parts: text lines, the Blast radius keys, or a list of cut lines."""
    if name == "Blast radius":
        keys = dict(raw["keys"])
        if "Touches" in keys:
            keys["Touches"] = keys["Touches"].split(", ") if keys["Touches"] else []
        return keys
    cut = {"Choices": choice, "Risks": risk, "Works when": works}.get(name)
    return [cut(x) for x in listed(raw)] if cut else raw["text"]


def maps(named):
    got = []
    for name, body in named:
        if not name.lower().startswith("change map"):
            continue
        area = name.split("·", 1)[1].strip() if "·" in name else ""
        cur = {"area": area, "none": False, "parts": [], "flows": []}
        got.append(cur)
        header, in_flows = None, False
        for line in body:
            t = line.strip()
            if not t:
                continue
            if t.lower().startswith("none:"):
                cur["none"] = t
            elif t.startswith("|"):
                cells = next(table_rows([t]))
                if cells and cells[0] == "Ref":
                    header = cells
                elif header and cells and re.match(r"M\d+$", cells[0]):
                    cur["parts"].append(map_part(dict(zip(header, cells))))
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


def map_part(row):
    """One Change map row as its parts: `at` the files, each backtick span whole; `cell` the Grid text."""
    at = [re.sub(r"^`(.*)`$", r"\1", entry.strip())
          for entry in re.findall(r"(?:`[^`]*`|[^,])+", row.get("At", "")) if entry.strip()]
    xy = grid(row.get("Grid"))
    x, y = (int(v) if v.is_integer() else v for v in xy) if xy else (None, None)
    return {"ref": row.get("Ref"), "name": row.get("Part"), "job": row.get("Job"), "change": row.get("Change"),
            "group": row.get("Group", ""), "kind": row.get("Kind"), "at": at, "cell": row.get("Grid"),
            "x": x, "y": y, "layer": row.get("Layer") or None}


def proves(value):
    return [int(x) for x in re.findall(r"#(\d+)", value)]


def records(lines, kind):
    got, current, last = [], None, None
    for line in lines:
        t = line.strip()
        if (m := RECORD[kind].fullmatch(t)):
            n = int(re.match(r"\w+ (\d+)", t).group(1))
            if kind == "slice":
                current = {"n": n, "seam": m.group(3), "proves": proves(m.group(1) or ""),
                           "change": [], "docs": [], "tests": []}
                if m.group(2):
                    current["deletes"] = True
            elif kind == "walk":
                current = {"n": n, "proves": proves(m.group(1)), "steps": []}
            else:
                current = {"n": n, "title": m.group(1), "setup": "walk " + m.group(2),
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
        elif (m := re.match(r"(Change|Docs|Given|When|Then|Red|Mutate|Setup|Where|Steps|See|Must not|Before|Shows):\s*(.*)", t)):
            key, value = m.group(1).lower().replace("must not", "mustNot"), m.group(2)
            target = current["tests"][-1] if key in ("given", "when", "then", "red", "mutate") and current.get("tests") else current
            if key in ("change", "docs", "steps"):
                target[key].append(value)
                last = (target[key], len(target[key]) - 1)
            else:
                target[key] = value
                last = (target, key)
        elif last and line[:1].isspace():
            last[0][last[1]] += " " + t
    return got


def stack_row(cells):
    """One Stack row as its parts; `row` keeps the cells as written, for the check that quotes one."""
    cell = lambda i: cells[i] if len(cells) > i else None
    points = cell(4)
    return {"n": cell(0), "issue": cell(1), "base": cell(2), "size": cell(3),
            "points": int(points) if points and points.isdecimal() else None, "row": cells}


def proved(item):
    m = PROVED.fullmatch(item)
    fact, ran, date, used = m.groups() if m else (None,) * 4
    return {"ref": item.split()[0] if item.split() else "", "fact": fact, "ran": ran, "date": date, "usedBy": used}


def proof_row(cells):
    """One Proof row as its parts; a row of any other width than 6 keeps only its first cell and count."""
    row = {"n": cells[0], "cells": len(cells), "line": None, "test": None, "walk": None, "video": None, "artifact": None}
    if len(cells) == 6:
        walk = re.search(r"walk (\d+)", cells[3])
        row.update({"line": cells[1], "test": None if cells[2] == "none" else cells[2],
                    "walk": int(walk.group(1)) if walk else None,
                    "video": None if cells[4] == "none" else cells[4], "artifact": cells[5]})
    return row


def seam(item):
    m = re.match(r"(.*?):\s*(?:`([^`]+)`|(layer \d+, slice \d+))\s*,\s*(.*)", item)
    return {"name": m.group(1), "at": m.group(2) or m.group(3), "why": m.group(4)} if m else None


def decided(item):
    what, _, why = re.sub(r"^D\d+ ", "", item).partition(": ")
    return {"what": what, "why": why}


def unread(section):
    got = []
    for block, kind in [("Slices", "slice"), ("UI walks", "walk"), ("Videos", "video")]:
        for line in section.get(block, []):
            t = line.strip()
            heading = not line[:1].isspace() or re.match(r"(Slice|Walk|Video)\b", t)
            if t and heading and not RECORD[kind].fullmatch(t):
                got.append((block, t))
    return got


def brief(lines):
    if not lines:
        return None
    task = next((m.group(1) for line in lines if (m := re.fullmatch(r"Task:\s*(\S.*)", line.strip()))), "")
    done = next((i for i, line in enumerate(lines) if line.strip() == "Done when:"), None)
    return {"task": task, "done": list_items(lines[done + 1:]) if done is not None else []}


def layer(section, n, issue, title, review):
    return {
        "n": n, "issue": issue, "title": title, "review": review,
        "summary": [line.strip() for line in section.get("Summary", []) if line.strip()],
        "proof": [proof_row(r) for r in table_rows(section.get("Proof", [])) if r and r[0].isdigit()],
        "seams": [s for s in map(seam, list_items(section.get("Seams", []))) if s],
        "decided": [decided(x) for x in list_items(section.get("Decided", []))],
        "out": [re.sub(r"^O\d+ ", "", x) for x in list_items(section.get("Out of scope", []))],
        "gates": key_values(section.get("Gates", []), ["Slice done", "Task done"]),
        "perf": key_values(section["Perf"], PERF) if "Perf" in section else None,
        "slices": records(section.get("Slices", []), "slice"),
        "walks": records(section.get("UI walks", []), "walk"),
        "videos": records(section.get("Videos", []), "video"),
        "unread": unread(section),
    }


def read(path):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    named = blocks(lines)
    top, layer_sections = sections(lines)
    head = key_values(top["head"], ["Size", "Date"])
    h1 = next((re.match(r"# Plan: (?:#(\d+) )?(.*)", l) for l in top["head"] if l.startswith("# Plan: ")), None)
    run = "Stack" in top
    got = reviews(named, run)
    kind = re.match(r"\[([^]]+)\]", h1.group(2)) if h1 else None
    plan = {
        "title": h1.group(2) if h1 else "",
        "kind": kind.group(1) if kind else None,
        "number": int(h1.group(1)) if h1 and h1.group(1) else None,
        "size": head.get("size", ""),
        "date": head.get("date", ""),
        "run": run,
        # A chat plan has no issue: its `# Plan:` line has a title and no `#<n>`.
        "chat": not run and bool(h1) and not h1.group(1) and h1.group(2)[:1] not in ("", "#"),
        "facts": key_values(top.get("Facts", []), FACTS),
        "stack": [stack_row(r) for r in stack_rows(top.get("Stack", []))],
        "stack_issues": [int(m.group(1)) for r in stack_rows(top.get("Stack", []))
                         if len(r) > 1 and r[0].isdecimal() and (m := re.match(r"#(\d+)", r[1]))],
        "points": key_values(top.get("Stack", []), ["Points"]).get("points", ""),
        "reviews": got,
        "maps": maps(named),
        "proved": [proved(x) for x in list_items(top.get("Proved", []))],
        "brief": brief(top.get("Brief", [])),
        # A backtick span quotes code or output as it is, so only the text outside it is prose.
        "prose": [(n, re.sub(r"`[^`]*`", "``", line)) for n, line in enumerate(lines, 1)],
    }
    if run:
        plan["layers"] = [
            layer(body, int(m.group(1)), int(m.group(2)), m.group(3),
                  next((r["parts"] for r in got if r["kind"] == "layer" and r["layer"] == i), {}))
            for i, (m, body) in enumerate(layer_sections, 1)]
    else:
        plan["layers"] = [layer(top, 1, plan["number"], plan["title"], got[0]["parts"] if got else {})]
    return plan


def grid(cell):
    m = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*", cell or "")
    return tuple(float(x) for x in m.groups()) if m else None



def review_problems(plan):
    reviews, is_run, layer_count = plan["reviews"], plan["run"], len(plan["layers"])
    # A review's layer is 0 above the first layer heading; a ticket's Proof sits there.
    proof_rows = [0 if is_run else len(plan["layers"][0]["proof"])] + [len(l["proof"]) for l in plan["layers"]]
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
        for p, cap in [("Change", LAYER_CHANGE_MAX if r["kind"] == "layer" else LINES_MAX), ("Approach", LINES_MAX),
                       ("In", LINES_MAX), ("Out", LINES_MAX)]:
            if p in parts and len(parts[p]) > cap:
                yield f"{name}: `{p}` has {len(parts[p])} lines, the limit is {cap}"
            if p in parts and not parts[p]:
                yield f"{name}: `{p}` is empty"
        if "Blast radius" in parts:
            keys = parts["Blast radius"]
            for k in BLAST:
                if not keys.get(k):
                    yield f"{name}: `Blast radius` has no `{k}` line"
        if "Choices" in parts:
            got = [c["line"] for c in parts["Choices"]]
            odd = [x for x in got if not re.match(r"(Fork|D\d+):", x)]
            if odd:
                yield f"{name}: each `Choices` line starts `Fork:` or `D<n>:`, not: {odd[0][:60]}"
            decided = [x for x in got if re.match(r"D\d+:", x)]
            if len(decided) > DECIDED_MAX:
                yield f"{name}: `Choices` has {len(decided)} `Decided` lines, the limit is {DECIDED_MAX}"
        if "Risks" in parts:
            got = [x["line"] for x in parts["Risks"]]
            if len(got) > RISKS_MAX:
                yield f"{name}: `Risks` has {len(got)} lines, the limit is {RISKS_MAX}"
            for x in got:
                if "If wrong:" not in x or "Proved:" not in x:
                    yield f"{name}: a risk needs `If wrong:` and `Proved:`: {x[:60]}"
        if "Works when" in parts:
            got = [x["line"] for x in parts["Works when"]]
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
    if len(blocks) > MAPS_MAX:
        yield f"change map: {len(blocks)} maps, the limit is {MAPS_MAX}"
    seen = set()
    for n, b in enumerate(blocks, 1):
        name = f"change map {n}" if len(blocks) > 1 else "change map"
        parts = b["parts"]
        if not parts:
            yield f"{name}: no parts"
        if len(parts) > PARTS_MAX:
            yield f"{name}: {len(parts)} parts, the limit is {PARTS_MAX}; merge the `same` ones first"
        refs, cells = {}, {}
        for p in parts:
            ref = p["ref"]
            if ref in seen:
                yield f"{name}: {ref} is used twice"
            seen.add(ref)
            refs[ref] = p
            if not p["name"] or not p["job"]:
                yield f"{name}: {ref} needs a part name and a job"
            if len(p["name"] or "") > NAME_MAX:
                yield f"{name}: {ref} part name is {len(p['name'])} characters, the limit is {NAME_MAX}"
            if len(p["job"] or "") > JOB_MAX:
                yield f"{name}: {ref} job is {len(p['job'])} characters, the limit is {JOB_MAX}"
            if p["change"] not in CHANGES:
                yield f"{name}: {ref} change `{p['change']}` is not new, changed, removed, or same"
            if p["kind"] not in KINDS:
                yield f"{name}: {ref} kind `{p['kind']}` is not part, store, or outside"
            if p["kind"] != "outside" and not p["at"]:
                yield f"{name}: {ref} has no files and no slice in `At`"
            g = None if p["x"] is None else (p["x"], p["y"])
            if g is None:
                yield f"{name}: {ref} grid `{p['cell']}` is not `column,row` with both 0 or more"
            elif g in cells:
                yield f"{name}: {ref} and {cells[g]} share the grid cell {p['cell']}"
            else:
                cells[g] = ref
            if is_run and p["change"] != "same" and not re.match(r"L\d+$", p["layer"] or ""):
                yield f"{name}: {ref} is {p['change']} but names no layer"
        # A group's gray area spans its cells; a part of no such group inside it misstates the map.
        groups = {}
        for p in parts:
            if p["group"] and p["x"] is not None:
                groups.setdefault(p["group"], []).append((p["x"], p["y"]))
        for gname, gcells in groups.items():
            xs, ys = [c[0] for c in gcells], [c[1] for c in gcells]
            for c, ref in cells.items():
                if refs[ref]["group"] != gname and min(xs) <= c[0] <= max(xs) and min(ys) <= c[1] <= max(ys):
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
            if p["change"] == "same" and ref not in touched:
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


TYPED = re.compile(r"\btype\s+`([^`]+)`", re.I)
# `type` that starts a step or a clause, with no backtick span after it.
UNTYPED = re.compile(r"(?:(?:^|[,;])\s*|\b(?:and|then)\s+)type\s+(?=[^\s`])", re.I)


def typed_problems(name, step):
    # Each backtick span is emptied first: a `,` or a `type` inside quoted output is not a clause.
    if UNTYPED.search(re.sub(r"`[^`]*`", "``", step)):
        yield f"{name}: put the text to type in backticks right after `type`"
    # A typed command is the backtick span right after `type`; a See or Before line quotes output in backticks too.
    for cmd in TYPED.findall(step):
        cmd = cmd.strip()
        # An escaped or quoted `;` is part of one command.
        join = re.search(r";|&&", re.sub(r"\\.|'[^']*'|\"(?:\\.|[^\"\\])*\"", "", cmd))
        if join:
            yield f"{name}: `{cmd}` joins commands with `{join.group()}`; type one command per step"
        if re.match(r"clear(?:\s|;|&|$)", cmd):
            yield f"{name}: `{cmd}` starts with `clear`; never clear the screen in a walk"


def step_problems(layers, terminal):
    for layer in layers:
        name = f"layer {layer['n']} " if len(layers) > 1 else ""
        for walk in layer["walks"]:
            for step in walk["steps"]:
                yield from typed_problems(f"{name}walk {walk['n']} steps", step)
            yield from typed_problems(f"{name}walk {walk['n']} before", walk.get("before", ""))
            # A terminal shows stdout and stderr mixed, so a walk can only check text on the screen.
            if terminal and (m := re.search(r"\b(stderr|stdout)\b", walk.get("mustNot", ""), re.I)):
                yield (f"{name}walk {walk['n']} must not: names `{m.group(1)}`; a terminal shows stdout and stderr"
                       " mixed, so name text on the screen, as in `no line starting Error:`")
        for video in layer["videos"]:
            for k, step in enumerate(video["steps"], 1):
                where = f"{name}video {video['n']} step {k}"
                typed = len(TYPED.findall(step))
                if typed > 1:
                    yield f"{where}: types {typed} commands; type one command per step"
                yield from typed_problems(where, step)


def stack_problems(rows, layers):
    if len(rows) != len(layers):
        yield f"stack: {len(rows)} rows, {len(layers)} `## Layer` headings"
        return
    for n, (row, layer) in enumerate(zip((r["row"] for r in rows), layers), 1):
        if layer["n"] != n:
            yield f"stack: layer heading {layer['n']} is not layer {n}"
        if len(row) != 5:
            yield f"stack: row {n} has {len(row)} cells, needs 5"
            continue
        if row[0] != str(n):
            yield f"stack: row {n} names layer {row[0]}, needs {n}"
        issue = f"#{layer['issue']} {layer['title']}"
        if row[1] != issue:
            yield f"stack: row {n} issue `{row[1]}` is not `{issue}`"
        if not row[2]:
            yield f"stack: row {n} has no base"
        if not re.fullmatch(r"XS|S|M|L|XL", row[3]):
            yield f"stack: row {n} size `{row[3]}` is not XS, S, M, L, or XL"
        if not row[4].isdecimal():
            yield f"stack: row {n} points `{row[4]}` is not an integer"


FORMS = {
    "Slices": "Slice <n>, proves #<n>: <seam>` or `Slice 1, deletes dead code: <area>",
    "UI walks": "Walk <n>, proves #<n>",
    "Videos": "Video <n>, Setup of walk <n>, shows walks <n>",
}


def record_problems(layer):
    for block, t in layer["unread"]:
        name = block if block == "UI walks" else block.lower()
        yield f"{name}: {t} is not a `{FORMS[block]}` heading"


def brief_problems(brief):
    if brief is None:
        yield "brief: a chat plan needs a `## Brief` block"
        return
    if not brief["task"]:
        yield "brief: no `Task:` line"
    if not any(brief["done"]):
        yield "brief: no `Done when:` list"


# Marks a plan writes plainly: a long dash and a curly quote, outside backtick spans.
MARKS = [
    (re.compile("[\u2013\u2014]"), "long dash; write a comma, a colon, or two sentences"),
    (re.compile("[\u2018\u2019\u201c\u201d]"), "curly quote; write a straight quote"),
]


def prose_problems(prose):
    for n, line in prose:
        for mark, fix in MARKS:
            if mark.search(line):
                yield f"line {n}: {fix}"


def problems(plan):
    yield from prose_problems(plan["prose"])
    is_run, layers = plan["run"], plan["layers"]
    if is_run and (plan["number"] is None or not plan["title"]):
        yield "head: no `# Plan: #<n>` line"
    if not is_run and not plan["title"]:
        yield "head: no `# Plan:` line"
    if plan["chat"]:
        yield from brief_problems(plan["brief"])
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", plan["date"]):
        yield "head: no `Date: YYYY-MM-DD` line under `# Plan:`"
    if not is_run and not re.fullmatch(r"size/(XS|S|M|L|XL)", plan["size"]):
        yield "head: a ticket needs `Size: size/<x>`"
    if is_run:
        yield from stack_problems(plan["stack"], layers)
    yield from review_problems(plan)
    yield from map_problems(plan["maps"], is_run)
    for n, layer in enumerate(layers, 1):
        yield from record_problems(layer)
        for k, s in enumerate(layer["slices"], 1):
            if s.get("deletes") and k > 1:
                yield f"slices: layer {n} slice {k} deletes dead code; only slice 1 may"
            elif s.get("deletes") and s["n"] != 1:
                yield f"slices: layer {n} delete slice is headed `Slice {s['n']}`; it is `Slice 1`"
        for row in layer["proof"]:
            if row["cells"] != 6:
                yield f"proof: layer {n} row {row['n']} has {row['cells']} cells, needs 6"
        if not layer["summary"]:
            yield f"summary: layer {n} has no `## Summary` block"
        elif len(layer["summary"]) > SUMMARY_MAX:
            yield f"summary: layer {n} has {len(layer['summary'])} lines, the limit is {SUMMARY_MAX}"
        if re.sub(r"^#\d+ ", "", layer["title"]).startswith("[perf]") and layer["perf"] is None:
            yield f"perf: layer {n} is a `[perf]` ticket with no `## Perf` block"
        if layer["perf"] is not None:
            for key in PERF:
                if not layer["perf"].get(key.lower()):
                    yield f"perf: layer {n} has no `{key}:` line"
    for item in plan["proved"]:
        if item["fact"] is None:
            yield f"proved: {item['ref']} needs `, <YYYY-MM-DD>. Used by <refs>.` at its end"
    walks = [{"layer": n, "n": walk["n"], "kind": before_kind(walk["before"]) if "before" in walk else None}
             for n, layer in enumerate(layers, 1) for walk in layer["walks"]]
    yield from md_before_problems(walks)
    yield from step_problems(layers, plan["facts"].get("ui") == "terminal")
