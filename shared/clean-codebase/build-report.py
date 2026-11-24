#!/usr/bin/env python3
"""Build a clean-codebase report page from its rows file.

    build-report.py <rows .json>

Writes the page next to the rows file, prints `page: <html path>`, and
exits 0. Prints each problem and exits 1 without changing the old page
when the rows file is bad.
"""
import json
import os
import sys
from pathlib import Path

KEYS = ["skill", "repo", "commit", "date", "scope", "new", "tickets", "kinds", "changes", "rows"]
ADVICE = {"fix", "keep-and-mark", "fine"}
STATES = {"", "known", "came-back"}
LABELS = {"Seen", "Inferred"}


def problems(report):
    for key in KEYS:
        if key not in report:
            yield f'rows file: no "{key}"'
    if any(key not in report for key in KEYS):
        return
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
        places = row.get("places") or []
        if not places:
            yield f"row {rid}: no places"
        for n, place in enumerate(places, 1):
            if place.get("label") not in LABELS:
                yield f'row {rid} place {n}: label "{place.get("label")}" is not Seen or Inferred'


def plural(n, one, many):
    return one if n == 1 else many


def summary(rows):
    if not rows:
        return "I found nothing to change."
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
    data["rows"] = [dict(row, count=len(row["places"]), spreading=any(p["new"] for p in row["places"]))
                    for row in report["rows"]]
    data["summary"] = summary(report["rows"])
    return data


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = Path(sys.argv[1])
    report = json.loads(path.read_text(encoding="utf-8"))
    found = list(problems(report))
    if found:
        print("\n".join(found))
        sys.exit(1)
    shell = (Path(__file__).resolve().parent / "report.html").read_text(encoding="utf-8")
    output = path.with_suffix(".html")
    tmp = output.with_suffix(".html.tmp")
    payload = json.dumps(page_data(report), ensure_ascii=False).replace("</", r"<\/")
    try:
        tmp.write_text(shell.replace("const DATA = {};", "const DATA = " + payload + ";"), encoding="utf-8")
        os.replace(tmp, output)
    finally:
        if tmp.exists():
            tmp.unlink()
    print(f"page: {output}")


if __name__ == "__main__":
    main()
