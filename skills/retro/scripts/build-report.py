#!/usr/bin/env python3
"""Build the retro report page from its cards file.

    build-report.py <cards .json>

Writes report.html next to the cards file, prints `page: <html path>`, and
exits 0. Prints each problem and exits 1 without changing the old page when
the cards file is bad.
"""
import json
import os
import sys
from html import escape
from pathlib import Path


def columns(cards):
    return sorted(cards["items"], key=lambda item: item["date"])


def column_head(item):
    top, _, rest = item["id"].partition(" ")
    bottom = rest or item.get("ref", "")
    return (f'<th class="p-1 font-normal text-center"><span class="block">{escape(top)}</span>'
            f'<span class="block muted">{escape(bottom)}</span></th>')


def header(cards):
    read = "".join(f"<p>{line}</p>" for line in cards["read"])
    mono = " · ".join(escape(cards[key]) for key in ("scope", "window", "counts"))
    return f"""  <header class="space-y-3">
    <h1 class="font-serif text-3xl">Retro report: {escape(cards["repo"])}</h1>
    <p class="font-mono text-sm muted">{mono}</p>
    <div class="flex flex-wrap gap-4 text-xs uppercase tracking-wider muted">
      <span class="flex items-center gap-2"><span class="dot hit-strong"></span>strong</span>
      <span class="flex items-center gap-2"><span class="dot hit-amber"></span>worth exploring</span>
      <span class="flex items-center gap-2"><span class="dot hit-slate"></span>speculative</span>
      <span class="flex items-center gap-2"><span class="dot hit-one"></span>one-time or tip</span>
      <span class="flex items-center gap-2"><span class="dot"></span>not seen in that item</span>
    </div>
    <details class="text-sm">
      <summary class="muted">What was read</summary>
      <div class="mt-2 space-y-2 muted max-w-3xl">{read}</div>
    </details>
  </header>
"""


def overview(cards):
    cols = columns(cards)
    heads = "\n".join(f"            {column_head(item)}" for item in cols)
    key = "".join(f'<li><span class="font-mono">{escape(item["id"])}</span> · {escape(item["title"])} · {escape(item["date"])}</li>'
                  for item in cols)
    return f"""
  <section id="overview" class="card rounded-xl border p-6 space-y-4">
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <h2 class="font-serif text-2xl">Where each problem showed up</h2>
      <p class="text-xs muted">rows: cards · columns: the items they came from</p>
    </div>
    <div class="overflow-x-auto">
      <table class="text-sm w-full">
        <thead class="text-xs uppercase tracking-wider muted">
          <tr>
            <th></th><th class="text-left font-normal pb-2">Card</th>
{heads}
          </tr>
        </thead>
        <tbody>
        </tbody>
      </table>
    </div>
    <ul id="key" class="text-xs muted space-y-0.5">{key}</ul>
  </section>
"""


def page(cards, shell):
    body = header(cards) + overview(cards)
    return shell.replace("{{repo name}}", escape(cards["repo"])).replace("  <!-- REPORT -->\n", body)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    path = Path(sys.argv[1])
    cards = json.loads(path.read_text(encoding="utf-8"))
    shell = (Path(__file__).resolve().parent.parent / "assets" / "report.html").read_text(encoding="utf-8")
    output = path.parent / "report.html"
    tmp = output.with_suffix(".html.tmp")
    try:
        tmp.write_text(page(cards, shell), encoding="utf-8")
        os.replace(tmp, output)
    finally:
        if tmp.exists():
            tmp.unlink()
    print(f"page: {output}")


if __name__ == "__main__":
    main()
