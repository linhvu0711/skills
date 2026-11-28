#!/usr/bin/env python3
"""Locate a Claude Code session by ID and render a clean, context-friendly transcript.

Session transcripts live at ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl.
This walks every project dir, finds the matching file (exact id, then unique
prefix), reads it into a list of messages, and ../printer.py prints them as a
markdown transcript suitable for loading into another Claude Code conversation.

Usage:
    extract_session.py <session-id | path> [--summary] [--after-compact] [--max-result-chars N]

Modes (default = balanced: prompts + assistant text in full, tool calls as
one-liners, tool results truncated, thinking omitted):
    --summary           only user prompts + assistant text (most compact)
    --after-compact     start at the last compaction summary (it already covers
                        everything before it), dropping the pre-compact history
    --max-result-chars  per tool-result truncation cap (default 500)
"""
import argparse
import glob
import json
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
# `python3 -I` leaves the script's folder off sys.path, so the sessions folder goes on it here.
sys.path.insert(0, os.path.dirname(here))
import adapter_lib  # noqa: E402  # adapter_lib imports only after the sys.path line above

printer = adapter_lib.load("printer", os.path.join(here, "..", "printer.py"))
chat_log = adapter_lib.load("chat_log", os.path.join(here, "..", "chat_log.py"))

PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
WORDS = printer.Words(
    transcript="Loaded session transcript",
    assistant="Assistant",
    cli="",
)


def locate(session_id):
    """Return list of (path) matching the id, or the file itself when given a
    path (a helper agent's log under <id>/subagents/). Strips .jsonl if given."""
    given = os.path.expanduser(session_id.strip())
    if os.path.isfile(given):
        return [os.path.abspath(given)]
    sid = session_id.strip()
    if sid.endswith(".jsonl"):
        sid = sid[:-6]
    exact = glob.glob(os.path.join(PROJECTS_DIR, "*", f"{sid}.jsonl"))
    if exact:
        return exact
    # fall back to prefix match (allows passing a short unique prefix)
    return glob.glob(os.path.join(PROJECTS_DIR, "*", f"{sid}*.jsonl"))


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        rows.extend(chat_log.rows(fh))
    return rows


def parse_task_notification(s):
    """Condense a <task-notification> (background task finished) to one line."""
    if not s.lstrip().startswith("<task-notification>"):
        return None
    def tag(name):
        m = re.search(rf"<{name}>(.*?)</{name}>", s, re.S)
        return m.group(1).strip() if m else ""
    summary = tag("summary") or tag("task-id")
    status = tag("status")
    result = tag("result").splitlines()[0][:160] if tag("result") else ""
    line = f"[task notification] {summary}"
    if status:
        line += f" · {status}"
    if result:
        line += f" · {result}"
    return line


def parse_slash_command(s):
    """If string is a <command-name> wrapper, return a short label, else None."""
    if "<command-name>" not in s:
        return None
    name = re.search(r"<command-name>(.*?)</command-name>", s, re.S)
    args = re.search(r"<command-args>(.*?)</command-args>", s, re.S)
    if not name:
        return None
    label = name.group(1).strip()
    a = (args.group(1).strip() if args else "")
    return f"[slash command] {label} {a}".rstrip()


def summarize_tool_input(name, inp):
    if not isinstance(inp, dict):
        return str(inp)[:200]
    for key in ("command", "file_path", "path", "pattern", "query", "url", "prompt", "description"):
        if key in inp and isinstance(inp[key], str):
            v = inp[key].replace("\n", " ")
            return v[:200] + ("…" if len(v) > 200 else "")
    v = json.dumps(inp, ensure_ascii=False)
    return v[:200] + ("…" if len(v) > 200 else "")


def read(rows):
    """The log as a printer.Chat: every block in order, and the chat's facts."""
    meta = {}
    title = None
    timestamps = []
    messages = []

    def add_user_text(txt, is_compact):
        if not txt or adapter_lib.injected(txt, "claude"):
            return
        if is_compact:
            messages.append(printer.Message("compact", txt.strip()))
            return
        note = parse_task_notification(txt)
        if note:
            messages.append(printer.Message("note", note))
            return
        slash = parse_slash_command(txt)
        if slash and not slash.split(None, 3)[3:]:
            messages.append(printer.Message("note", slash))   # bare slash command: plumbing, not a turn
        elif slash:
            messages.append(printer.Message("user", slash, command=True))
        else:
            messages.append(printer.Message("user", txt.strip()))

    for r in rows:
        t = r.get("type")
        if r.get("timestamp"):
            timestamps.append(r["timestamp"])
        for k in ("cwd", "gitBranch", "sessionId"):
            if r.get(k) and k not in meta:
                meta[k] = r[k]
        if t == "ai-title":
            title = r.get("aiTitle") or title
        elif t == "user":
            if r.get("isMeta"):
                continue
            is_compact = bool(r.get("isCompactSummary"))
            content = r.get("message", {}).get("content")
            if isinstance(content, str):
                add_user_text(content, is_compact)
            elif isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    bt = b.get("type")
                    if bt == "text":
                        add_user_text(b.get("text", ""), is_compact)
                    elif bt == "tool_result":
                        messages.append(printer.Message(
                            "result", chat_log.text_of(b.get("content"), "[image]"), error=bool(b.get("is_error"))))
        elif t == "assistant":
            content = r.get("message", {}).get("content")
            if not isinstance(content, list):
                if isinstance(content, str) and content.strip():
                    messages.append(printer.Message("assistant", content.strip()))
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                bt = b.get("type")
                if bt == "text":
                    txt = b.get("text", "").strip()
                    if txt:
                        messages.append(printer.Message("assistant", txt))
                elif bt == "thinking":
                    messages.append(printer.Message("thinking", b.get("thinking", "").strip()))
                elif bt == "tool_use":
                    messages.append(printer.Message(
                        "call", f"{b.get('name')}({summarize_tool_input(b.get('name'), b.get('input'))})"))

    return printer.Chat(
        messages=messages, words=WORDS,
        session_id=meta.get("sessionId"), cwd=meta.get("cwd"), branch=meta.get("gitBranch"),
        title=title,
        span=(min(timestamps), max(timestamps)) if timestamps else None,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--after-compact", action="store_true")
    ap.add_argument("--max-result-chars", type=int, default=500)
    args = ap.parse_args()

    matches = locate(args.session_id)
    if not matches:
        sys.exit(f"stop: no session file found for id '{args.session_id}' under {PROJECTS_DIR}: pass the full UUID or a unique prefix; list them with ls ~/.claude/projects/*/*.jsonl")
    path = printer.only_match(matches, args.session_id)
    rows = load(path)
    chat = read(rows)
    mode = "summary" if args.summary else "balanced"
    print(printer.transcript(chat, mode, args.max_result_chars, args.after_compact))


if __name__ == "__main__":
    main()
