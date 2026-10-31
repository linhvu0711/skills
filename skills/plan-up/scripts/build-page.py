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

import plan_reader
from plan_reader import BLAST, CHANGES, PERF


KINDS = {"part", "store", "outside"}
NEEDS = {
    "single": ["Change", "Approach", "Blast radius", "Choices", "Risks", "Works when", "In", "Out"],
    "stack": ["Change", "Approach", "Blast radius", "Risks", "In", "Out"],
    "layer": ["Change", "Choices", "Works when"],
}
# The longest text that fits a map box or a flow label in shell.html. plan.md points here.
NAME_MAX, JOB_MAX, LABEL_MAX = 20, 30, 20
PROVED = re.compile(r"P\d+ (.*): (.*), (\d{4}-\d{2}-\d{2})\. Used by (.+)\.$")


def text(values):
    return " ".join(v.strip() for v in values if v.strip())


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
                          "at": [re.sub(r"^`(.*)`$", r"\1", entry.strip())
                                 for entry in re.findall(r"(?:`[^`]*`|[^,])+", at) if entry.strip()],
                          "x": int(xy[0]) if xy[0].is_integer() else xy[0],
                          "y": int(xy[1]) if xy[1].is_integer() else xy[1], "layer": p.get("Layer") or None})
        got.append({"area": m["area"], "parts": parts, "flows": [f for f in m["flows"] if "bad" not in f]})
    return got


def plain(records):
    return [{k: v for k, v in r.items() if k != "n"} for r in records]


def page_layer(layer, issue):
    review, forks = layer_review(layer["review"])
    proof = []
    for r in layer["proof"]:
        if len(r) != 6:
            continue
        w = re.search(r"walk (\d+)", r[3])
        proof.append({"line": r[1], "test": None if r[2] == "none" else r[2],
                      "walk": int(w.group(1)) if w else None, "video": None if r[4] == "none" else r[4], "artifact": r[5]})
    seams = []
    for item in layer["seams"]:
        m = re.match(r"(.*?):\s*(?:`([^`]+)`|(layer \d+, slice \d+))\s*,\s*(.*)", item)
        if m:
            seams.append({"name": m.group(1), "at": m.group(2) or m.group(3), "why": m.group(4)})
    decided = []
    for item in layer["decided"]:
        what, _, why = re.sub(r"^D\d+ ", "", item).partition(": ")
        decided.append({"what": what, "why": why})
    gates = layer["gates"]
    page = {"issue": issue, "title": layer["title"], "summary": " ".join(layer["summary"]), "review": review,
            "forks": forks, "seams": seams, "proof": proof, "slices": plain(layer["slices"]),
            "walks": plain(layer["walks"]), "videos": plain(layer["videos"]),
            "gates": {"slice": gates.get("slice done", ""), "task": gates.get("task done", "")},
            "decided": decided, "out": [re.sub(r"^O\d+ ", "", x) for x in layer["out"]]}
    if layer["perf"] is not None:
        page["perf"] = layer["perf"]
    return page


def page_data(plan):
    number, title, facts = plan["number"] or 0, plan["title"], plan["facts"]
    issue = {"size": plan["size"]}
    if number:
        issue = {"number": number, "url": f"https://github.com/{facts.get('repo', '')}/issues/{number}", **issue}
    parts = plan["reviews"][0]["parts"] if plan["reviews"] else {}
    proved = []
    for item in plan["proved"]:
        m = PROVED.fullmatch(item)
        if m:
            proved.append(dict(zip(["fact", "ran", "date", "usedBy"], m.groups())))
    layers = []
    if plan["run"]:
        stack = {int(r[0]): r for r in plan["stack"] if r[0].isdecimal()}
        for layer in plan["layers"]:
            row = stack.get(layer["n"], [])
            layer_issue = {"number": layer["issue"],
                           "url": f"https://github.com/{facts.get('repo', '')}/issues/{layer['issue']}",
                           "size": row[3] if len(row) > 3 else ""}
            page = page_layer(layer, layer_issue)
            page["review"]["change"] = text(layer["review"].get("Change", {}).get("text", []))
            page["targets"] = row[2] if len(row) > 2 else ""
            page["points"] = int(row[4]) if len(row) > 4 and row[4].isdecimal() else 0
            layers.append(page)
    else:
        layers.append(page_layer(plan["layers"][0], dict(issue)))
    kind = re.match(r"\[([^]]+)\]", title)
    if kind:
        issue["kind"] = kind.group(1)
    data = {"title": title, "issue": issue, "date": plan["date"], "run": plan["run"],
            "review": top_review(parts), "maps": page_maps(plan["maps"]), "facts": facts, "proved": proved, "layers": layers}
    if plan["run"]:
        data["points"] = plan["points"]
    no_map = next((m["none"] for m in plan["maps"] if m["none"]), None)
    if no_map:
        data["noMap"] = no_map
    return data


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


def strings(node, path="DATA"):
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield from strings(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from strings(v, f"{path}[{i}]")


def stack_problems(rows, layers):
    if len(rows) != len(layers):
        yield f"stack: {len(rows)} rows, {len(layers)} `## Layer` headings"
        return
    for n, (row, layer) in enumerate(zip(rows, layers), 1):
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


def plan_problems(plan):
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
            if len(row) != 6:
                yield f"proof: layer {n} row {row[0]} has {len(row)} cells, needs 6"
        if not layer["summary"]:
            yield f"summary: layer {n} has no `## Summary` block"
        elif len(layer["summary"]) > 3:
            yield f"summary: layer {n} has {len(layer['summary'])} lines, the limit is 3"
        if re.sub(r"^#\d+ ", "", layer["title"]).startswith("[perf]") and layer["perf"] is None:
            yield f"perf: layer {n} is a `[perf]` ticket with no `## Perf` block"
        if layer["perf"] is not None:
            for key in PERF:
                if not layer["perf"].get(key.lower()):
                    yield f"perf: layer {n} has no `{key}:` line"
    for item in plan["proved"]:
        if not PROVED.fullmatch(item):
            ref = item.split()[0]
            yield f"proved: {ref} needs `, <YYYY-MM-DD>. Used by <refs>.` at its end"
    walks = [{"layer": n, "n": walk["n"], "kind": before_kind(walk["before"]) if "before" in walk else None}
             for n, layer in enumerate(layers, 1) for walk in layer["walks"]]
    yield from md_before_problems(walks)
    yield from step_problems(layers, plan["facts"].get("ui") == "terminal")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = Path(sys.argv[1])
    plan = plan_reader.read(path)
    if not plan["reviews"]:
        print(f"not a plan-up .md: {path.name}")
        sys.exit(1)
    problems = list(plan_problems(plan))
    data = page_data(plan)
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
