"""Read a plan .md once, into the values build-page.py and prune.py use.

    plan = plan_reader.read(path)

The plan is one dict of text, lists of text, key-value dicts, table rows as
cell lists, and records, in the shape of references/plan.md. Any text reads
without an error: a missing block reads as empty.
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
REFS = r"#\d+(?:(?:,\s*|\s+and\s+)#\d+)*"
RECORD = {
    "slice": re.compile(rf"Slice \d+, (?:proves ({REFS})|(deletes dead code)):\s*(.+)"),
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
    return got


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
        elif (m := re.match(r"(Change|Docs|Given|When|Then|Red|Setup|Where|Steps|See|Must not|Before|Shows):\s*(.*)", t)):
            key, value = m.group(1).lower().replace("must not", "mustNot"), m.group(2)
            target = current["tests"][-1] if key in ("given", "when", "then", "red") and current.get("tests") else current
            if key in ("change", "docs", "steps"):
                target[key].append(value)
                last = (target[key], len(target[key]) - 1)
            else:
                target[key] = value
                last = (target, key)
        elif last and line[:1].isspace():
            last[0][last[1]] += " " + t
    return got


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
        "proof": [r for r in table_rows(section.get("Proof", [])) if r and r[0].isdigit()],
        "seams": list_items(section.get("Seams", [])),
        "decided": list_items(section.get("Decided", [])),
        "out": list_items(section.get("Out of scope", [])),
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
    plan = {
        "title": h1.group(2) if h1 else "",
        "number": int(h1.group(1)) if h1 and h1.group(1) else None,
        "size": head.get("size", ""),
        "date": head.get("date", ""),
        "run": run,
        # A chat plan has no issue: its `# Plan:` line has a title and no `#<n>`.
        "chat": not run and bool(h1) and not h1.group(1) and h1.group(2)[:1] not in ("", "#"),
        "facts": key_values(top.get("Facts", []), FACTS),
        "stack": stack_rows(top.get("Stack", [])),
        "points": key_values(top.get("Stack", []), ["Points"]).get("points", ""),
        "reviews": got,
        "maps": maps(named),
        "proved": list_items(top.get("Proved", [])),
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
