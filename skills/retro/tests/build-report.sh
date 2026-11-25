# build-report.sh: a cards file in, the retro report page out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

rb_build() { run python3 "$here/../scripts/build-report.py" "$@"; }

# rb_cards <jq filter>: the fixture cards file, changed by the filter, at $T/cards.json
rb_cards() {
  T="$(mktemp -d)"
  jq "$1" "$here/build-report/cards.json" > "$T/cards.json"
}

# rb_page <what> [<n>]: the content of $T/report.html, not its markup.
#   key       the text of each <li> under id="key", one per line
#   cells N   per cell of the ov-row numbered N, its other class or -, space-joined
#   strip N   inside id="card-N", per dot its other class or -, then " | " and the strip's text
rb_page() {
  python3 - "$T/report.html" "$@" <<'PY'
import sys
from html.parser import HTMLParser

path, what, arg = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.keys, self.rows, self.strips = [], [], {}
        self.text = None
        self.row = None
        self.card = None
        self.card_depth = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        self.stack.append((tag, a.get("id"), cls))
        ids = [i for _, i, _ in self.stack if i]
        if tag == "li" and "key" in ids:
            self.text = []
        if tag == "tr" and "ov-row" in cls:
            self.row = {"cells": [], "first": None, "td": 0}
        if self.row is not None and tag == "td":
            self.row["td"] += 1
            if self.row["td"] == 1:
                self.text = []
        if self.row is not None and tag == "span" and "cell" in cls:
            self.row["cells"].append(" ".join(c for c in cls if c != "cell") or "-")
        if tag == "article" and (a.get("id") or "").startswith("card-"):
            self.card = a["id"][5:]
            self.card_depth = len(self.stack)
            self.strips[self.card] = {"dots": [], "text": None}
        if self.card and tag == "span" and "dot" in cls:
            self.strips[self.card]["dots"].append(" ".join(c for c in cls if c != "dot") or "-")
        if self.card and tag == "span" and cls == ["text-xs", "muted"] and self.strips[self.card]["text"] is None:
            self.text = []

    def handle_endtag(self, tag):
        top = self.stack.pop() if self.stack else (None, None, [])
        if self.text is not None and tag == "li":
            self.keys.append(" ".join("".join(self.text).split()))
            self.text = None
        elif self.text is not None and self.row is not None and tag == "td" and self.row["first"] is None:
            self.row["first"] = " ".join("".join(self.text).split())
            self.text = None
        elif self.text is not None and self.card and tag == "span":
            self.strips[self.card]["text"] = " ".join("".join(self.text).split())
            self.text = None
        if tag == "tr" and self.row is not None and "ov-row" in top[2]:
            self.rows.append(self.row)
            self.row = None
        if tag == "article" and self.card and len(self.stack) < self.card_depth:
            self.card = None

    def handle_data(self, data):
        if self.text is not None:
            self.text.append(data)


p = Page()
p.feed(open(path, encoding="utf-8").read())
if what == "key":
    print("\n".join(p.keys))
elif what == "cells":
    print(next((" ".join(r["cells"]) for r in p.rows if r["first"] == arg), ""))
elif what == "strip":
    s = p.strips.get(arg, {"dots": [], "text": ""})
    print(" ".join(s["dots"]) + " | " + (s["text"] or ""))
PY
}

t_rb_key_in_date_order() {
  # Given: the fixture cards file, S1 dated 2026-11-12 listed before PR #40 dated 2026-11-10
  rb_cards .
  # When
  rb_build "$T/cards.json"
  # Then
  eq exit 0 "$code"
  eq stdout "page: $T/report.html" "$out"
  eq key "$(printf 'PR #40 · Add CSV export · 2026-11-10\nS1 · Fix the export menu · 2026-11-12')" "$(rb_page key)"
}

t_rb_builds_twice() {
  # Given: the fixture cards file, built once
  rb_cards .
  rb_build "$T/cards.json"
  cp "$T/report.html" "$T/first"
  # When
  rb_build "$T/cards.json"
  # Then
  eq exit 0 "$code"
  eq same "same" "$(cmp -s "$T/first" "$T/report.html" && echo same || echo differs)"
}

t_rb_overview_cells() {
  # Given: the fixture cards file; card 2 came from S1 only
  rb_cards .
  # When
  rb_build "$T/cards.json"
  # Then
  eq cells "- hit-amber" "$(rb_page cells 2)"
}

t_rb_dot_strip() {
  # Given: the fixture cards file; card 1 came from S1 and PR #40
  rb_cards .
  # When
  rb_build "$T/cards.json"
  # Then
  eq strip "hit-strong hit-strong | 5 times in 2 of 2 items · 9 user turns · PR #40, S1" "$(rb_page strip 1)"
}

t_rb_escapes_quote() {
  # Given: the fixture cards file; card 1's first quote is "push <main> first"
  rb_cards .
  # When
  rb_build "$T/cards.json"
  # Then
  has page 'push &lt;main&gt; first' "$(cat "$T/report.html")"
  lacks page 'push <main> first' "$(cat "$T/report.html")"
}

t_rb_this_project_first() {
  # Given: the acme/tools card first in the file
  rb_cards '.cards |= reverse'
  # When
  rb_build "$T/cards.json"
  # Then
  eq homes 'id="home-acme-shop" id="home-acme-tools" ' "$(grep -o 'id="home-[a-z-]*"' "$T/report.html" | tr '\n' ' ')"
}

cases=(
  "draws the key in date order|t_rb_key_in_date_order"
  "builds the same page twice|t_rb_builds_twice"
  "draws each overview cell from the card's items|t_rb_overview_cells"
  "draws the dot strip and item count from the card's items|t_rb_dot_strip"
  "escapes a quote's text|t_rb_escapes_quote"
  "puts this project's cards first|t_rb_this_project_first"
)
