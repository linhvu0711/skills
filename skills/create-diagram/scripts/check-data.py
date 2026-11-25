#!/usr/bin/env python3
"""Check a diagram page's DATA before the page is shown.

    check-data.py <page .html>

Prints `ok: <type>, <counts>` and exits 0 when DATA is sound. Prints each
problem and exits 1 when it is not: an id that points at nothing.
"""
import json
import sys
from pathlib import Path

MARK = "const DATA = "


def read_data(text, path):
    at = text.find(MARK)
    if at < 0:
        return None, f'no "{MARK}" in {path}'
    try:
        data, _ = json.JSONDecoder().raw_decode(text, at + len(MARK))
    except json.JSONDecodeError as e:
        return None, f"DATA is not JSON: {e.msg}, line {e.lineno} column {e.colno}"
    return data, None


def graph_problems(data):
    nodes = {n.get("id") for n in data.get("nodes", [])}
    groups = {g.get("id") for g in data.get("groups", [])}
    for i, edge in enumerate(data.get("edges", [])):
        for end in ("from", "to"):
            if edge.get(end) not in nodes:
                yield f'edges[{i}]: {end} "{edge.get(end)}" is not a node'
    for group in data.get("groups", []):
        for member in group.get("members", []):
            if member not in nodes | groups:
                yield f'group "{group.get("id")}": member "{member}" is not a node or group'


def sequence_problems(data):
    people = {p.get("id") for p in data.get("participants", [])}
    for i, step in enumerate(data.get("steps", [])):
        for end in ("from", "to"):
            if step.get(end) not in people:
                yield f'steps[{i}]: {end} "{step.get(end)}" is not a participant'
    for i, frame in enumerate(data.get("frames", [])):
        for p in frame.get("participants", []):
            if p not in people:
                yield f'frames[{i}]: participant "{p}" is not a participant'
    for i, note in enumerate(data.get("notes", [])):
        if note.get("at") not in people:
            yield f'notes[{i}]: at "{note.get("at")}" is not a participant'


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = sys.argv[1]
    data, error = read_data(Path(path).read_text(encoding="utf-8"), path)
    if error:
        print(error)
        sys.exit(1)
    sequence = data.get("type") == "sequence"
    found = list(sequence_problems(data) if sequence else graph_problems(data))
    if found:
        print("\n".join(found))
        sys.exit(1)
    if sequence:
        print(f'ok: sequence, {len(data.get("participants", []))} participants, {len(data.get("steps", []))} steps')
    else:
        print(f'ok: {data.get("type")}, {len(data.get("nodes", []))} nodes, {len(data.get("edges", []))} edges')


if __name__ == "__main__":
    main()
