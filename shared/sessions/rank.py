"""Rank sessions against a search, for the finders under sessions/.

Each session is a dict of named text fields, as {"title": ..., "prompts": ...,
"body": ...}. The score is BM25F, the usual search-engine formula:

- whole words only, so "in" never matches inside "install";
- a word found in few sessions counts more than one found in most, so
  "gates" outweighs "skill" in a repo of skills;
- a word's count saturates and is set against the field's length, so a long
  session does not win by size alone;
- each field has a weight, so a word the user typed counts more than one the
  agent wrote.

A score above 0 means at least one search word is in the session; callers
such as recall rely on that.
"""

from __future__ import annotations

import math
import re
from collections import Counter
from functools import lru_cache

WORD = re.compile(r"[a-z0-9]+")
# Filler a description is made of: "the chat where we fixed ..." should rank
# on "fixed", not on "chat".
STOP = frozenset("""
a an the and or but of to in on at by for with from into onto about as is are was were be been
it its this that these those there here we us our you your i me my he she they them their
can could should would will do did does done have has had not no so too very just also
then than when where which who what why how all any some one get got make made
session sessions chat chats conversation find
""".split())
K1 = 1.2  # how fast repeats of a word stop adding to its score
B = 0.75  # how much a field's length counts against it


VOWELS = "aeiou"


def _consonant(w: str, i: int) -> bool:
    if w[i] in VOWELS:
        return False
    return w[i] != "y" or i == 0 or not _consonant(w, i - 1)


def _measure(w: str) -> int:
    """Porter's m: how many vowel-then-consonant runs the word has."""
    runs, prev = 0, True
    for i in range(len(w)):
        cons = _consonant(w, i)
        runs += cons and not prev
        prev = cons
    return runs


def _has_vowel(w: str) -> bool:
    return any(not _consonant(w, i) for i in range(len(w)))


def _cvc(w: str) -> bool:
    """Ends consonant, vowel, consonant, the last not w, x, or y: as in "mak"."""
    return (len(w) >= 3 and _consonant(w, len(w) - 3) and not _consonant(w, len(w) - 2)
            and _consonant(w, len(w) - 1) and w[-1] not in "wxy")


@lru_cache(maxsize=None)
def stem(word: str) -> str:
    """Steps 1 and 5a of the Porter stemmer, so "gates" finds "gate",
    "making" finds "make", and "note" stays apart from "not"."""
    w = word
    if w.endswith("sses") or w.endswith("ies"):
        w = w[:-2]
    elif w.endswith("s") and not w.endswith("ss") and len(w) > 2:
        w = w[:-1]
    if w.endswith("eed"):
        if _measure(w[:-3]) > 0:
            w = w[:-1]
    else:
        for suffix in ("ed", "ing"):
            if w.endswith(suffix) and _has_vowel(w[:-len(suffix)]):
                w = w[:-len(suffix)]
                if w.endswith(("at", "bl", "iz")):
                    w += "e"
                elif len(w) > 1 and w[-1] == w[-2] and _consonant(w, len(w) - 1) and w[-1] not in "lsz":
                    w = w[:-1]
                elif _measure(w) == 1 and _cvc(w):
                    w += "e"
                break
    if w.endswith("y") and _has_vowel(w[:-1]):
        w = w[:-1] + "i"
    if w.endswith("e"):
        m = _measure(w[:-1])
        if m > 1 or (m == 1 and not _cvc(w[:-1])):
            w = w[:-1]
    return w


def words(text: str) -> list[str]:
    return [stem(w) for w in WORD.findall(text.lower())]


def terms(query: str) -> list[str]:
    """The search words that count: whole words, stemmed, filler dropped, each once."""
    seen = []
    for w in WORD.findall(query.lower()):
        if w in STOP or len(w) < 2:
            continue
        s = stem(w)
        if s not in seen:
            seen.append(s)
    return seen


def scores(docs: list[dict[str, str]], query: str, weights: dict[str, float]) -> list[float]:
    """One BM25F score per doc, in order. Word rarity is measured over these docs."""
    want = terms(query)
    if not want or not docs:
        return [0.0] * len(docs)
    wanted = set(want)
    counts, lengths = [], []
    for doc in docs:
        per_field, field_len = {}, {}
        for field in weights:
            raw = Counter(WORD.findall((doc.get(field) or "").lower()))
            field_len[field] = sum(raw.values())
            hits = Counter()
            for w, k in raw.items():
                if stem(w) in wanted:
                    hits[stem(w)] += k
            per_field[field] = hits
        counts.append(per_field)
        lengths.append(field_len)
    n = len(docs)
    avg = {f: (sum(l[f] for l in lengths) / n) or 1.0 for f in weights}
    df = Counter(t for c in counts for t in want if any(c[f][t] for f in weights))
    out = []
    for c, ln in zip(counts, lengths):
        total = 0.0
        for t in want:
            tf = sum(w * c[f][t] / (1 - B + B * ln[f] / avg[f]) for f, w in weights.items())
            if tf:
                idf = math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5))
                total += idf * tf / (K1 + tf)
        out.append(round(total, 2))
    return out


def best_line(lines, query: str) -> str:
    """The line holding the most search words, for a match snippet; '' when none does."""
    want = set(terms(query))
    best, hits = "", 0
    for line in lines:
        line = line.strip()
        if not line:
            continue
        n = len(want & set(words(line)))
        if n > hits:
            best, hits = line, n
            if hits == len(want):
                break
    return best
