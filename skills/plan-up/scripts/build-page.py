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
FLOW = re.compile(r"-\s*(M\d+)\s*(?:→|->)\s*(M\d+):\s*(.*?)\s*(?:\(([^)]*)\))?\s*$")
LAYER = re.compile(r"Layer (\d+) · #(\d+) (.+)$")


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
            cur["none"] = True
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
        parts = []
        for p in m["parts"]:
            at = p.get("At", "")
            xy = grid(p.get("Grid")) or (0, 0)
            parts.append({"ref": p.get("Ref"), "name": p.get("Part"), "job": p.get("Job"),
                          "change": p.get("Change"), "group": p.get("Group", ""), "kind": p.get("Kind"),
                          "at": re.findall(r"`([^`]+)`", at) or at or [],
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
        if kind == "slice" and (m := re.match(r"Slice \d+, proves (.*?):\s*(.*)", t)):
            current = {"seam": m.group(2), "proves": proves(m.group(1)), "change": [], "docs": [], "tests": []}
            got.append(current)
            last = None
        elif kind == "walk" and (m := re.match(r"Walk \d+, proves (.*)", t)):
            current = {"proves": proves(m.group(1)), "steps": []}
            got.append(current)
            last = None
        elif kind == "video" and (m := re.match(r"Video \d+, (Setup of walk (\d+)), shows walks (.*)", t)):
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
        w = re.search(r"walk (\d+)", r[3])
        proof.append({"line": r[1], "test": None if r[2] == "none" else r[2],
                      "walk": int(w.group(1)) if w else None, "video": None if r[4] == "none" else r[4], "artifact": r[5]})
    seams = []
    for item in list_items(section.get("Seams", [])):
        m = re.match(r"(.*?):\s*`([^`]+)`\s*,\s*(.*)", item)
        if m:
            seams.append({"name": m.group(1), "at": m.group(2), "why": m.group(3)})
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
        m = re.match(r"P\d+ (.*): (.*), (\d{4}-\d{2}-\d{2})\. Used by (.+)\.$", item)
        if m:
            proved.append(dict(zip(["fact", "ran", "date", "usedBy"], m.groups())))
    is_run = "Stack" in section
    layers = []
    if is_run:
        stack = {int(r[0]): r for r in table_rows(section["Stack"]) if r and r[0].isdigit()}
        for i, (heading, body) in enumerate(layer_sections, 1):
            row = stack.get(int(heading.group(1)), [])
            layer_issue = {"number": int(heading.group(2)),
                           "url": f"https://github.com/{facts.get('repo', '')}/issues/{heading.group(2)}",
                           "size": row[3] if len(row) > 3 else ""}
            review = next((r["parts"] for r in reviews if r["kind"] == "layer" and r["layer"] == i), {})
            layer = page_layer(body, layer_issue, heading.group(3), review)
            layer["review"]["change"] = text(review.get("Change", {}).get("text", []))
            layer["targets"] = row[2] if len(row) > 2 else ""
            layer["points"] = int(row[4]) if len(row) > 4 and row[4].isdigit() else 0
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
    return data


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = Path(sys.argv[1])
    data = page_data(path.read_text(encoding="utf-8").splitlines())
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
