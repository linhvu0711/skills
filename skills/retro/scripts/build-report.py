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


STRENGTH = {"Strong": "hit-strong", "Worth exploring": "hit-amber", "Speculative": "hit-slate",
            "One-time": "hit-one", "Tip": "hit-one"}


def columns(cards):
    return sorted(cards["items"], key=lambda item: item["date"])


def groups(cards):
    """The cards by home, this project first, each with its page number."""
    here = cards["repo"].lower()
    homes = {}
    for card in cards["cards"]:
        mine = card.get("home_unknown") or card.get("home", "").lower() == here
        homes.setdefault(cards["repo"] if mine else card["home"], []).append(card)
    order = sorted(homes, key=lambda home: home != cards["repo"])
    n = 0
    for home in order:
        numbered = []
        for card in homes[home]:
            n += 1
            numbered.append((n, card))
        yield home, numbered


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


def hits(card, cols):
    """Per column, the card's strength class when the card came from that item, else ""."""
    have = set(card["items"])
    return [STRENGTH[card["badge"]] if item["id"] in have else "" for item in cols]


def overview_rows(cards, cols):
    rows = []
    for home, numbered in groups(cards):
        rows.append(f'          <tr class="ov-home"><td></td><td colspan="{len(cols) + 1}" '
                    f'class="pt-3 pb-1 text-xs uppercase tracking-wider muted">{escape(home)}</td></tr>')
        for n, card in numbered:
            tds = "".join(f'<td class="p-1 text-center"><span class="{("cell " + c).strip()}"></span></td>'
                          for c in hits(card, cols))
            rows.append(f'          <tr class="ov-row">\n'
                        f'            <td class="pr-3 py-1 text-right font-mono muted">{n}</td>\n'
                        f'            <td class="pr-4 py-1"><a class="ov-link" href="#card-{n}">{card["title"]}</a></td>\n'
                        f'            {tds}\n'
                        f'          </tr>')
    return "\n".join(rows)


def strip(card, cols):
    dots = "".join(f'<span class="{("dot " + c).strip()}"></span>' for c in hits(card, cols))
    names = ", ".join(item["id"] for item in cols if item["id"] in set(card["items"]))
    parts = [f'{card["times"]} times in {len(card["items"])} of {len(cols)} items']
    if card.get("cost"):
        parts.append(card["cost"])
    parts.append(names)
    return f"""      <div class="flex items-center gap-3">
        <div class="flex gap-1">{dots}</div>
        <span class="text-xs muted">{escape(" · ".join(parts))}</span>
      </div>"""


def cards_section(cards):
    cols = columns(cards)
    out = []
    for home, numbered in groups(cards):
        for n, card in numbered:
            out.append(f"""    <article id="card-{n}" class="card rounded-xl border p-6 space-y-5">
      <h3 class="font-serif text-2xl">{n}. {card["title"]}</h3>
{strip(card, cols)}
    </article>""")
    return '\n  <section id="cards" class="space-y-12">\n' + "\n".join(out) + "\n  </section>\n"


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
{overview_rows(cards, cols)}
        </tbody>
      </table>
    </div>
    <ul id="key" class="text-xs muted space-y-0.5">{key}</ul>
  </section>
"""


def page(cards, shell):
    body = header(cards) + overview(cards) + cards_section(cards)
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
