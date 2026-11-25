#!/usr/bin/env python3
"""Build the retro report page from its cards file.

    build_report.py <cards .json>

Writes report.html next to the cards file, prints `page: <html path>`, and
exits 0. Prints each problem on stderr and exits 1 without changing the old
page when the cards file is bad.
"""
import argparse
import json
import os
import sys
from html import escape


KEYS = ["repo", "scope", "window", "counts", "read", "items", "cards", "questions", "top_why"]
STRENGTH = {"Strong": "hit-strong", "Worth exploring": "hit-amber", "Speculative": "hit-slate",
            "One-time": "hit-one", "Tip": "hit-one"}


def problems(cards):
    missing = [key for key in KEYS if key not in cards]
    for key in missing:
        yield f'cards file: no "{key}"'
    if missing:
        return
    ids = set()
    for item in cards["items"]:
        if item["id"] in ids:
            yield f'item "{item["id"]}": id used twice'
        ids.add(item["id"])
    for card in cards["cards"]:
        name = f'card "{card.get("title")}"'
        if card.get("badge") not in STRENGTH:
            yield f'{name}: badge "{card.get("badge")}" is not Strong, Worth exploring, Speculative, One-time, or Tip'
        for item in card.get("items", []):
            if item not in ids:
                yield f'{name}: item "{item}" is not in items'
        for q in card.get("quotes", []):
            if q.get("item") not in card.get("items", []):
                yield f'{name}: quote item "{q.get("item")}" is not one of the card\'s items'
    for n, question in enumerate(cards["questions"], 1):
        if question.get("item") not in ids:
            yield f'question {n}: item "{question.get("item")}" is not in items'


def columns(cards):
    """The items any card came from, in date order."""
    used = {item for card in cards["cards"] for item in card["items"]}
    return sorted((item for item in cards["items"] if item["id"] in used), key=lambda item: item["date"])


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


def strip(card, cols, read):
    dots = "".join(f'<span class="{("dot " + c).strip()}"></span>' for c in hits(card, cols))
    names = ", ".join(item["id"] for item in cols if item["id"] in set(card["items"]))
    parts = [f'{card["times"]} times in {len(card["items"])} of {read} items']
    if card.get("cost"):
        parts.append(card["cost"])
    parts.append(names)
    return f"""      <div class="flex items-center gap-3">
        <div class="flex gap-1">{dots}</div>
        <span class="text-xs muted">{escape(" · ".join(parts))}</span>
      </div>"""


CHIP = {"Strong": "bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-100",
        "Worth exploring": "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-100",
        "Speculative": "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-100",
        "One-time": "bg-stone-100 text-stone-700 dark:bg-stone-800 dark:text-stone-100",
        "Tip": "bg-stone-100 text-stone-700 dark:bg-stone-800 dark:text-stone-100"}


def chips(card):
    tags = [escape(card["kind"])]
    if card.get("open"):
        tags.append(f'open #{card["open"]}')
    if card.get("did_not_hold"):
        tags.append(f'the fix did not hold #{card["did_not_hold"]}')
    if card.get("home_unknown"):
        tags.append(f'home unknown ({escape(card["home_unknown"])})')
    badge = f'        <span class="rounded-full px-2 py-0.5 {CHIP[card["badge"]]}">{escape(card["badge"])}</span>'
    return "\n".join([badge] + [f'        <span class="rounded-full px-2 py-0.5 border">{tag}</span>' for tag in tags])


def quote(q, pad):
    return (f'{pad}<blockquote class="font-mono text-[13px] leading-relaxed px-3 py-2 rounded-r">{escape(q["text"])}'
            f'<span class="block font-sans text-xs muted mt-1">{escape(q["item"])} · {escape(q["where"])}</span></blockquote>')


def happened(card):
    shown = [quote(q, "          ") for q in card["quotes"][:2]]
    rest = card["quotes"][2:]
    if rest:
        folded = "\n".join(quote(q, "              ") for q in rest)
        shown.append(f"""          <details class="text-sm">
            <summary class="muted">{len(rest)} more quotes</summary>
            <div class="space-y-2 mt-2">
{folded}
            </div>
          </details>""")
    return "\n".join(shown)


def fix_side(card):
    if not card.get("texts"):
        return f"""        <div class="card rounded-lg border p-4 space-y-2">
          <p class="text-xs uppercase tracking-wider muted">Fix</p>
          <p>{card["fix"]}</p>
        </div>"""
    files = "\n".join(f"""          <div class="space-y-1">
            <p class="font-mono text-xs muted">{escape(t["file"])} · {escape(t["place"])}</p>
            <div class="diff-del font-mono text-[13px] px-3 py-1.5 rounded">− {escape(t["now"])}</div>
            <div class="diff-add font-mono text-[13px] px-3 py-1.5 rounded">+ {escape(t["after"])}</div>
          </div>""" for t in card["texts"])
    return f"""        <div class="card rounded-lg border p-4 space-y-3">
          <p class="text-xs uppercase tracking-wider muted">The text, before and after</p>
{files}
        </div>"""


def card_html(n, card, cols, read):
    where = "".join(f"<li>{line}</li>" for line in card["where"])
    fix_line = f'\n      <p><strong>Fix.</strong> {card["fix"]}</p>' if card.get("texts") else ""
    return f"""    <article id="card-{n}" class="card rounded-xl border p-6 space-y-5">
      <h3 class="font-serif text-2xl">{n}. {card["title"]}</h3>
      <div class="flex flex-wrap items-center gap-2 text-xs">
{chips(card)}
      </div>
{strip(card, cols, read)}
      <ul class="font-mono text-sm muted">{where}</ul>
      <div class="grid md:grid-cols-2 gap-4 items-start">
        <div class="space-y-2">
          <p class="text-xs uppercase tracking-wider muted">What happened</p>
{happened(card)}
        </div>
{fix_side(card)}
      </div>{fix_line}
    </article>"""


def cards_section(cards):
    cols = columns(cards)
    out = []
    for home, numbered in groups(cards):
        name = escape(home) + (" (this project)" if home == cards["repo"] else "")
        slug = home.replace("/", "-").lower()
        body = "\n".join(card_html(n, card, cols, len(cards["items"])) for n, card in numbered)
        out.append(f"""    <div id="home-{escape(slug)}" class="space-y-10">
    <h2 class="font-serif text-2xl muted">{name}</h2>
{body}
    </div>""")
    return '\n  <section id="cards" class="space-y-12">\n' + "\n".join(out) + "\n  </section>\n"


def questions(cards):
    if not cards["questions"]:
        return ""
    lines = "".join(f'<li>{q["text"]} <span class="text-xs muted">{escape(q["item"])} · {escape(q["where"])}</span></li>'
                    for q in cards["questions"])
    return f"""
  <section id="open-questions" class="space-y-3">
    <h2 class="font-serif text-2xl">Open questions</h2>
    <ul class="list-disc pl-5 space-y-1">{lines}</ul>
  </section>
"""


def top_pick(cards):
    first = next(numbered[0][1] for _, numbered in groups(cards))
    return f"""
  <section id="top-pick">
    <article class="card top rounded-xl border-2 p-8 space-y-3">
      <p class="text-xs uppercase tracking-wider muted">Top pick</p>
      <h2 class="font-serif text-3xl"><a class="accent" href="#card-1">1. {first["title"]}</a></h2>
      <p>{cards["top_why"]}</p>
      <p class="text-sm muted">Which cards should become issues? Answer in chat with their numbers, for example <code>1 4</code>, or <code>none</code>.</p>
    </article>
  </section>
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
{overview_rows(cards, cols)}
        </tbody>
      </table>
    </div>
    <ul id="key" class="text-xs muted space-y-0.5">{key}</ul>
  </section>
"""


def page(cards, shell):
    body = header(cards) + overview(cards) + cards_section(cards) + questions(cards) + top_pick(cards)
    return shell.replace("{{repo name}}", escape(cards["repo"])).replace("  <!-- REPORT -->\n", body)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("cards", help="the cards .json")
    path = ap.parse_args().cards
    with open(path, encoding="utf-8") as f:
        cards = json.load(f)
    found = list(problems(cards))
    if found:
        sys.exit("\n".join(found))
    assets = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "assets")
    with open(os.path.join(assets, "report.html"), encoding="utf-8") as f:
        shell = f.read()
    output = os.path.join(os.path.dirname(path), "report.html")
    tmp = output + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(page(cards, shell))
        os.replace(tmp, output)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print(f"page: {output}")


if __name__ == "__main__":
    main()
