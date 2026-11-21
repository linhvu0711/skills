#!/usr/bin/env python3
"""Render one Antigravity chat as text, for ../adapter_lib.py's `extract`.

    extract_session.py <path, id, or id prefix>

Prints a header, then each prompt and reply in order. The store reads only
prompts and replies, so there is one mode and nothing to cut. No chat
found: `stop: no Antigravity chat <session>` on stderr, exit 1.
"""

import argparse
import datetime as dt
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
# Loaded by path: `python3 -I` leaves the script's folder off sys.path.
spec = importlib.util.spec_from_file_location("store", os.path.join(here, "store.py"))
store = importlib.util.module_from_spec(spec)
# Registered before it runs: dataclasses looks a module up in sys.modules, and
# Python 3.11 and older fail on store.py's Chat without it.
sys.modules["store"] = store
spec.loader.exec_module(store)

LABEL = {"user": "## 🧑 User", "assistant": "## 🤖 Antigravity"}


def when(t):
    return dt.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M")


def render(chat):
    prompts = [t for role, t in chat.turns if role == "user"]
    out = ["# Loaded Antigravity session transcript"]
    if prompts:
        first = prompts[0].strip().splitlines()[0] if prompts[0].strip() else ""
        out.append(f"**First prompt:** {first[:80]}{'…' if len(first) > 80 else ''}")
    out.append(f"**Session ID:** `{chat.id}`")
    if chat.cwd:
        out.append(f"**Project (cwd):** `{chat.cwd}`")
    out.append(f"**Span:** {when(chat.first)} → {when(chat.last)}")
    out.append(f"**Activity:** {len(prompts)} user prompts · {len(chat.turns) - len(prompts)} assistant replies")
    out.append("**Render mode:** prompts and replies")
    out.append("\n---\n")
    for role, text in chat.turns:
        out += [LABEL[role], text, ""]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description="Render one Antigravity chat.")
    ap.add_argument("session")
    args = ap.parse_args()
    path = store.locate(args.session)
    try:
        chat = store.read(path) if path else None
    except store.Unreadable:
        chat = None
    if chat is None:
        print(f"stop: no Antigravity chat {args.session}", file=sys.stderr)
        return 1
    print(render(chat))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
