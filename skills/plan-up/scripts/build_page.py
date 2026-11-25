#!/usr/bin/env python3
"""Build a plan page from its Markdown, the only source of the page.

    build_page.py <plan-slug.md>

Prints `page: <html path>` and exits 0. Prints each problem and exits 1
without changing the old page when a block is bad.
"""
import argparse
import json
import os
import sys

import plan_reader
from plan_reader import BLAST


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
        parts = [{"ref": p["ref"], "name": p["name"], "job": p["job"], "change": p["change"], "group": p["group"],
                  "kind": p["kind"], "at": p["at"], "x": p["x"] or 0, "y": p["y"] or 0, "layer": p["layer"]}
                 for p in m["parts"]]
        got.append({"area": m["area"], "parts": parts, "flows": m["flows"]})
    return got


def plain(records):
    return [{k: v for k, v in r.items() if k != "n"} for r in records]


def page_layer(layer, issue):
    review, forks = layer_review(layer["review"])
    proof = [{k: r[k] for k in ("line", "test", "walk", "video", "artifact")} for r in layer["proof"] if r["cells"] == 6]
    gates = layer["gates"]
    page = {"issue": issue, "title": layer["title"], "summary": " ".join(layer["summary"]), "review": review,
            "forks": forks, "seams": layer["seams"], "proof": proof, "slices": plain(layer["slices"]),
            "walks": plain(layer["walks"]), "videos": plain(layer["videos"]),
            "gates": {"slice": gates.get("slice done", ""), "task": gates.get("task done", "")},
            "decided": layer["decided"], "out": layer["out"],
            "files": [{k: f[k] for k in ("path", "from", "change", "generated", "slices", "note")} for f in layer["files"]]}
    if layer["perf"] is not None:
        page["perf"] = layer["perf"]
    return page


def page_data(plan):
    number, title, facts = plan["number"] or 0, plan["title"], plan["facts"]
    issue = {"size": plan["size"]}
    if number:
        issue = {"number": number, "url": f"https://github.com/{facts.get('repo', '')}/issues/{number}", **issue}
    parts = plan["reviews"][0]["parts"] if plan["reviews"] else {}
    proved = [{"fact": p["fact"], "ran": p["ran"], "date": p["date"], "usedBy": p["usedBy"]}
              for p in plan["proved"] if p["fact"] is not None]
    layers = []
    if plan["run"]:
        stack = {int(r["n"]): r for r in plan["stack"] if r["n"].isdecimal()}
        for layer in plan["layers"]:
            row = stack.get(layer["n"], {})
            layer_issue = {"number": layer["issue"],
                           "url": f"https://github.com/{facts.get('repo', '')}/issues/{layer['issue']}",
                           "size": row.get("size") or ""}
            page = page_layer(layer, layer_issue)
            page["review"]["change"] = text(layer["review"].get("Change", []))
            page["targets"] = row.get("base") or ""
            page["points"] = row.get("points") or 0
            layers.append(page)
    else:
        layers.append(page_layer(plan["layers"][0], dict(issue)))
    if plan["kind"]:
        issue["kind"] = plan["kind"]
    data = {"title": title, "issue": issue, "date": plan["date"], "run": plan["run"],
            "review": top_review(parts), "maps": page_maps(plan["maps"]), "facts": facts, "proved": proved, "layers": layers}
    if plan["run"]:
        data["points"] = plan["points"]
    no_map = next((m["none"] for m in plan["maps"] if m["none"]), None)
    if no_map:
        data["noMap"] = no_map
    return data


def strings(node, path=""):
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield from strings(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from strings(v, f"{path}[{i}]")


def tick_problems(data):
    for where, text in strings(data):
        if text.count("`") % 2:
            yield f"{where}: odd number of backticks, one shows raw: {text[:80]}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("plan", help="the plan .md")
    path = ap.parse_args().plan
    plan = plan_reader.read(path)
    if not plan["reviews"]:
        print(f"not a plan-up .md: {os.path.basename(path)}")
        sys.exit(1)
    data = page_data(plan)
    problems = [*plan_reader.problems(plan), *tick_problems(data)]
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    assets = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "assets")
    with open(os.path.join(assets, "shell.html"), encoding="utf-8") as f:
        shell = f.read()
    with open(os.path.join(assets, "layout.js"), encoding="utf-8") as f:
        layout = f.read()
    output = os.path.splitext(path)[0] + ".html"
    tmp = output + ".tmp"
    payload = json.dumps(data, ensure_ascii=False).replace("</", r"<\/")
    try:
        page = (shell.replace("const DATA = {};", "const DATA = " + payload + ";")
                .replace('<script src="layout.js"></script>', "<script>\n" + layout + "</script>"))
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(page)
        os.replace(tmp, output)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print(f"page: {output}")


if __name__ == "__main__":
    main()
