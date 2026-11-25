#!/usr/bin/env python3
"""Check a diagram page's DATA before the page is shown.

    check-data.py <page .html>

Prints `ok: <type>, <counts>` and exits 0 when DATA is sound. Prints each
problem and exits 1 when it is not: a type the catalog does not list, an
id that points at nothing, an id used twice or left out, a step number
that is not a step, a label left out, or more than the type's node budget,
read from references/catalog.md.
"""
import json
import re
import sys
from pathlib import Path

MARK = re.compile(r"const DATA\s*=\s*")
CATALOG = Path(__file__).resolve().parent.parent / "references" / "catalog.md"


def budgets():
    """Per catalog type, its limits as (what, max) pairs, from the Node budget table."""
    text = CATALOG.read_text(encoding="utf-8")
    table = text.split("## Node budget", 1)[1].split("\n\n", 2)[1]
    found = {}
    for row in table.splitlines()[2:]:
        kinds, nodes, edges = [cell.strip() for cell in row.strip("|").split("|")]
        if "participants" in nodes:
            limits = [("participants", int(re.findall(r"(\d+) participants", nodes)[0])),
                      ("steps", int(re.findall(r"(\d+) steps", nodes)[0]))]
        else:
            limits = [("nodes", int(re.findall(r"\d+", nodes)[-1])), ("edges", int(edges))]
        for kind in kinds.split(", "):
            found[kind.lower().replace(" ", "-")] = limits
    return found


def budget_problems(data, limits):
    for what, most in limits:
        count = len(data.get(what, []))
        if count > most:
            yield f'{data["type"]}: {count} {what}, budget {most}'


def read_data(text, path):
    found = MARK.search(text)
    if not found:
        return None, f'no "const DATA =" in {path}'
    try:
        data, _ = json.JSONDecoder().raw_decode(text, found.end())
    except json.JSONDecodeError as e:
        return None, f"DATA is not JSON: {e.msg}, line {e.lineno} column {e.colno}"
    return data, None


def id_problems(kind, items, seen):
    for i, item in enumerate(items):
        if "id" not in item:
            yield f'{kind}[{i}]: no id'
        elif item["id"] in seen:
            yield f'{kind}[{i}]: id "{item["id"]}" is used twice'
        else:
            seen.add(item["id"])


def graph_problems(data):
    seen = set()
    yield from id_problems("nodes", data.get("nodes", []), seen)
    yield from id_problems("groups", data.get("groups", []), seen)
    nodes = {n["id"] for n in data.get("nodes", []) if "id" in n}
    for node in data.get("nodes", []):
        if "label" not in node:
            yield f'node "{node.get("id")}": no label'
    for group in data.get("groups", []):
        if "label" not in group:
            yield f'group "{group.get("id")}": no label'
    groups = {g["id"] for g in data.get("groups", []) if "id" in g}
    for i, edge in enumerate(data.get("edges", [])):
        for end in ("from", "to"):
            if edge.get(end) not in nodes:
                yield f'edges[{i}]: {end} "{edge.get(end)}" is not a node'
    for group in data.get("groups", []):
        for member in group.get("members", []):
            if member not in nodes | groups:
                yield f'group "{group.get("id")}": member "{member}" is not a node or group'


def sequence_problems(data):
    yield from id_problems("participants", data.get("participants", []), set())
    count = len(data.get("steps", []))

    def is_step(value):
        return type(value) is int and 0 <= value < count

    people = {p["id"] for p in data.get("participants", []) if "id" in p}
    for person in data.get("participants", []):
        if "label" not in person:
            yield f'participant "{person.get("id")}": no label'
    for i, step in enumerate(data.get("steps", [])):
        for end in ("from", "to"):
            if step.get(end) not in people:
                yield f'steps[{i}]: {end} "{step.get(end)}" is not a participant'
        if "label" not in step:
            yield f'steps[{i}]: no label'
    for i, frame in enumerate(data.get("frames", [])):
        if "label" not in frame:
            yield f'frames[{i}]: no label'
        for end in ("from", "to"):
            if not is_step(frame.get(end)):
                yield f'frames[{i}]: {end} {json.dumps(frame.get(end))} is not a step'
        for p in frame.get("participants", []):
            if p not in people:
                yield f'frames[{i}]: participant "{p}" is not a participant'
    for i, note in enumerate(data.get("notes", [])):
        if note.get("at") not in people:
            yield f'notes[{i}]: at "{note.get("at")}" is not a participant'
        if "text" not in note:
            yield f'notes[{i}]: no text'
        if "after" in note and not is_step(note["after"]):
            yield f'notes[{i}]: after {json.dumps(note["after"])} is not a step'


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = sys.argv[1]
    data, error = read_data(Path(path).read_text(encoding="utf-8"), path)
    if error:
        print(error)
        sys.exit(1)
    limits = budgets().get(data.get("type"))
    if limits is None:
        print(f'type "{data.get("type", "")}" is not a catalog type')
        sys.exit(1)
    sequence = data["type"] == "sequence"
    found = list(sequence_problems(data) if sequence else graph_problems(data))
    found += budget_problems(data, limits)
    if found:
        print("\n".join(found))
        sys.exit(1)
    if sequence:
        print(f'ok: sequence, {len(data.get("participants", []))} participants, {len(data.get("steps", []))} steps')
    else:
        print(f'ok: {data.get("type")}, {len(data.get("nodes", []))} nodes, {len(data.get("edges", []))} edges')


if __name__ == "__main__":
    main()
