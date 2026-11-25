#!/usr/bin/env python3
"""Build a clean-codebase report page from its rows file.

    build_report.py <rows .json>

Writes the page next to the rows file, prints `page: <html path>`, and
exits 0. Prints each problem and exits 1 without changing the old page
when the rows file is bad.
"""
import argparse
import json
import os
import re
import sys

KEYS = ["skill", "repo", "commit", "date", "scope", "new", "kinds", "changes", "rows"]
ADVICE = {"fix", "keep-and-mark", "fine"}
STATES = {"", "known", "came-back"}
LABELS = {"Seen", "Inferred"}
VIEWS = {"rows", "cards"}
BADGES = {"Strong", "Worth exploring", "Speculative"}

# The card form of skills/improve-architecture/references/cards.md: each line
# form here was parsed by Mermaid 11, and a line outside it may not be.
ID = r"[A-Za-z][A-Za-z0-9_]*"
LABEL = r'(\[([A-Za-z0-9 _.,:/-]+|"[^"]+")\])'
NODE = rf"{ID}{LABEL}?"
ARROW = r'(-->|-\.->)(\|"[^"]+"\|)?'
SAY = r"[A-Za-z0-9 _.,:/()'-]+"
FLOWCHART = [rf"{NODE}", rf"{NODE}\s*{ARROW}\s*{NODE}", rf"subgraph {ID}{LABEL}?", r"end",
             rf"classDef {ID} [A-Za-z0-9#:,.%-]+;?", rf"class {ID}(,{ID})* {ID}"]
SEQUENCE = [rf"participant {ID}( as {SAY})?", rf"{ID}\s*(->>|-->>)\s*{ID}: {SAY}",
            rf"Note (over|left of|right of) {ID}(,{ID})?: {SAY}", rf"(loop|alt|else|opt) {SAY}", r"end"]


def problems(report):
    for key in KEYS:
        if key not in report:
            yield f'rows file: no "{key}"'
    if any(key not in report for key in KEYS):
        return
    view = report.get("view", "rows")
    if view not in VIEWS:
        yield f'view "{view}" is not rows or cards'
    not_checked = report.get("not_checked", [])
    if not isinstance(not_checked, list) or not all(isinstance(line, str) and line for line in not_checked):
        yield 'rows file: "not_checked" is not a list of lines'
    kinds = {k.get("id") for k in report["kinds"]}
    seen = set()
    for row in report["rows"]:
        rid = row.get("id")
        if rid in seen:
            yield f"row {rid}: id used twice"
        seen.add(rid)
        if row.get("kind") not in kinds:
            yield f'row {rid}: kind "{row.get("kind")}" is not in kinds'
        if row.get("advice") not in ADVICE:
            yield f'row {rid}: advice "{row.get("advice")}" is not fix, keep-and-mark, or fine'
        state = row.get("state", "")
        if state not in STATES:
            yield f'row {rid}: state "{state}" is not known or came-back'
        elif state and not row.get("ticket"):
            yield f"row {rid}: {state} needs a ticket"
        if state == "known" and row.get("choice"):
            yield f"row {rid}: a Known row asks nothing, so choice is false"
        if view == "cards":
            yield from card_problems(rid, row.get("card"))
        places = row.get("places") or []
        if not places:
            yield f"row {rid}: no places"
        for n, place in enumerate(places, 1):
            if place.get("label") not in LABELS:
                yield f'row {rid} place {n}: label "{place.get("label")}" is not Seen or Inferred'


def card_problems(rid, card):
    if not card:
        yield f"row {rid}: no card"
        return
    if card.get("badge") not in BADGES:
        yield f'row {rid}: badge "{card.get("badge")}" is not Strong, Worth exploring, or Speculative'
    for side in ("before", "after"):
        if not card.get(side):
            yield f"row {rid}: card has no {side} diagram"
            continue
        for n, reason in diagram_problems(card[side]):
            yield f"row {rid} {side} line {n}: {reason}"


def diagram_problems(source):
    lines = source.split("\n")
    head = lines[0].strip()
    if head not in ("flowchart LR", "flowchart TD", "sequenceDiagram"):
        yield 1, "start with flowchart LR, flowchart TD, or sequenceDiagram"
        return
    sequence = head == "sequenceDiagram"
    forms = SEQUENCE if sequence else FLOWCHART
    openers = ("loop", "alt", "opt") if sequence else ("subgraph",)
    blocks = []
    for n, line in enumerate(lines[1:], 2):
        line = line.strip()
        if not line or line.startswith("%%"):
            continue
        if any(re.fullmatch(form, line) for form in forms):
            word = line.split()[0]
            if word in openers:
                blocks.append((n, word))
            elif word == "else" and (not blocks or blocks[-1][1] != "alt"):
                yield n, "else outside an alt block"
            elif word == "end" and not blocks:
                yield n, "end with no open block"
            elif word == "end":
                blocks.pop()
            continue
        if re.search(r"-\.\s.+\s\.->", line) or re.search(r'-\.->\|[^"]', line):
            yield n, 'write an arrow label as -.->|"text"|'
        elif re.search(r"--\s.+\s-->", line) or re.search(r'-->\|[^"]', line):
            yield n, 'write an arrow label as -->|"text"|'
        else:
            yield n, "not a card diagram line, see cards.md"
    for n, word in blocks:
        yield n, f"{word} with no end"


def plural(n, one, many):
    return one if n == 1 else many


def summary(rows, changes):
    if not rows:
        return "I found nothing to fix." if changes else "I found nothing to change."
    known = [r for r in rows if r["state"] == "known"]
    open_rows = [r for r in rows if r["state"] != "known"]
    settled = [r for r in open_rows if not r["choice"]]
    count = lambda advice: sum(1 for r in settled if r["advice"] == advice)
    parts = [p for p in (
        f"fix {count('fix')}" if count("fix") else "",
        f"keep {count('keep-and-mark')}" if count("keep-and-mark") else "",
        f"leave {count('fine')} as they are" if count("fine") else "",
    ) if p]
    text = f"I found {len(rows)} {plural(len(rows), 'thing', 'things')}."
    if parts:
        said = parts[0] if len(parts) == 1 else ", ".join(parts[:-1]) + " and " + parts[-1]
        text += f" I would {said}."
    choice = sum(1 for r in open_rows if r["choice"])
    if choice:
        text += f" {choice} {plural(choice, 'needs', 'need')} your choice."
    if known:
        n = len(known)
        text += f" {n} {plural(n, 'is', 'are')} Known: an open ticket covers {plural(n, 'it', 'them')}."
    return text


def page_data(report):
    data = dict(report)
    data["rows"] = [{"state": "", "ticket": "", "choice": False, **row,
                     "places": [{"new": False, **p} for p in row["places"]],
                     "count": len(row["places"]),
                     "spreading": any(p.get("new") for p in row["places"])}
                    for row in report["rows"]]
    data["summary"] = summary(data["rows"], report["changes"])
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("rows", help="the rows .json")
    path = ap.parse_args().rows
    with open(path, encoding="utf-8") as f:
        report = json.load(f)
    found = list(problems(report))
    if found:
        print("\n".join(found))
        sys.exit(1)
    with open(os.path.join(os.path.dirname(os.path.realpath(__file__)), "report.html"), encoding="utf-8") as f:
        shell = f.read()
    output = os.path.splitext(path)[0] + ".html"
    tmp = output + ".tmp"
    payload = json.dumps(page_data(report), ensure_ascii=False).replace("<", r"\u003c")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(shell.replace("const DATA = {};", "const DATA = " + payload + ";"))
        os.replace(tmp, output)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print(f"page: {output}")


if __name__ == "__main__":
    main()
