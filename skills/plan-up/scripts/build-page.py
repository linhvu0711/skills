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
from plan_reader import BLAST, PROVED, grid


def text(values):
    return " ".join(v.strip() for v in values if v.strip())


def top_review(parts):
    rv = {k: text(parts.get(p, [])) for k, p in
          [("change", "Change"), ("approach", "Approach"), ("in", "In"), ("out", "Out")]}
    blast = parts.get("Blast radius", {})
    rv["blast"] = {k.lower(): blast.get(k, "") for k in BLAST if k != "Touches"}
    rv["blast"]["touches"] = blast.get("Touches", [])
    rv["risks"] = [{"belief": r["belief"], "ifWrong": r["ifWrong"], "proved": r["proved"]} for r in parts.get("Risks", [])]
    return rv


def layer_review(parts):
    choices = parts.get("Choices", [])
    return ({"choices": [{"ref": c["ref"], "text": c["text"]} for c in choices],
             "works": [w["text"] for w in parts.get("Works when", [])]},
            [c["fork"] for c in choices if c["fork"]])


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
            page["review"]["change"] = text(layer["review"].get("Change", []))
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
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = Path(sys.argv[1])
    plan = plan_reader.read(path)
    if not plan["reviews"]:
        print(f"not a plan-up .md: {path.name}")
        sys.exit(1)
    problems = list(plan_reader.problems(plan))
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
