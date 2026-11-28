#!/usr/bin/env python3
"""Locate a Codex CLI session (rollout) by ID and render a clean transcript.

Codex stores each session as a rollout JSONL under
  ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl
and archived ones under
  ~/.codex/archived_sessions/rollout-<timestamp>-<session-id>.jsonl
Both folders come from rollout_io.data_folders().
The session ID is the trailing UUID in the filename (and in session_meta.id).

Rollout entries have a top-level `type` (session_meta | turn_context | event_msg
| response_item) and a `payload`. Human turns live in event_msg/user_message
(Codex < 0.150) or event_msg/item_completed with item.type == "UserMessage"
(Codex >= 0.150, Aug 2026); response_item/message role=user is the last-resort
fallback. Assistant text + tool activity live in response_item. Reasoning blocks
are encrypted on disk, so only their count is surfaced. The rollout is read
into a list of messages, and ../printer.py prints them.

Usage:
    extract_session.py <session-id | path> [--summary] [--max-result-chars N]

Modes (default = balanced: prompts + assistant text in full, tool calls as
one-liners, tool results truncated):
    --summary           only user prompts + assistant text (most compact)
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

rollout_io = adapter_lib.load("rollout_io", os.path.join(here, "rollout_io.py"))
printer = adapter_lib.load("printer", os.path.join(here, "..", "printer.py"))
chat_log = adapter_lib.load("chat_log", os.path.join(here, "..", "chat_log.py"))

WORDS = printer.Words(
    transcript="Loaded Codex session transcript",
    assistant="Codex",
    cli="Codex CLI",
)


def locate(session_id):
    """Return rollout file paths matching the id (exact uuid, then prefix), or
    the file itself when given a path."""
    given = os.path.expanduser(session_id.strip().strip("`'\""))
    if os.path.isfile(given):
        return [os.path.abspath(given)]
    sid = session_id.strip().strip("`'\"")
    for suffix in (".jsonl.zst", ".jsonl"):
        if sid.endswith(suffix):
            sid = sid[: -len(suffix)]
            break
    # the uuid is embedded after the timestamp in the filename
    patterns = [
        os.path.join(str(folder), "**", f"rollout-*{sid}*{suffix}")
        for folder in rollout_io.data_folders()
        for suffix in rollout_io.SUFFIXES
    ]
    hits = []
    for p in patterns:
        hits.extend(glob.glob(p, recursive=True))
    return sorted(set(hits))


def load(path):
    rows = []
    with rollout_io.open_rollout(path) as fh:
        rows.extend(chat_log.rows(fh))
    return rows


def user_message_of(row):
    """Return the human prompt text carried by an event_msg row, else None.

    Old format: payload.type == user_message, text in payload.message.
    New format: payload.type == item_completed, payload.item.type == UserMessage,
    text in payload.item.content[].text.
    """
    if row.get("type") != "event_msg":
        return None
    p = row.get("payload") or {}
    pt = p.get("type")
    if pt == "user_message":
        return (p.get("message") or "").strip() or None
    if pt == "item_completed":
        item = p.get("item") or {}
        if item.get("type") == "UserMessage":
            return chat_log.text_of(item.get("content"), "[image]").strip() or None
    return None


def summarize_exec_input(input_text):
    """One-line summary of an `exec` custom_tool_call.

    Since Codex 0.150 the input is JS that wraps the real tool call, e.g.
        const r = await tools.exec_command({"cmd":"ls","workdir":"..."}); text(r.output);
    Pull out the wrapped tool name and its JSON argument; fall back to the JS.
    """
    if not isinstance(input_text, str):
        return str(input_text)[:200]
    m = re.search(r"tools\.(\w+)\(", input_text)
    if not m:
        first = input_text.strip().splitlines()[0] if input_text.strip() else ""
        return f"js: {first[:180]}"
    name = m.group(1)
    start = m.end()
    # balanced-brace scan for the first JSON object argument
    arg = None
    if start < len(input_text) and input_text[start] == "{":
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(input_text)):
            ch = input_text[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    arg = input_text[start:i + 1]
                    break
    if name == "apply_patch":
        # the patch usually sits in a JS string const; read the file headers straight from the JS
        files = patch_files(input_text)
        if files:
            return "apply_patch: " + "; ".join(files)[:300]
    if arg is None:
        return f"{name}: {input_text[start:start + 160].strip()}"
    return f"{name}: {summarize_call(name, arg)}"


def summarize_call(name, arguments):
    """One-line summary of a function_call's JSON-string arguments."""
    try:
        inp = json.loads(arguments) if isinstance(arguments, str) else arguments
    except Exception:
        return (arguments or "")[:200]
    if not isinstance(inp, dict):
        return str(inp)[:200]
    for key in ("cmd", "command", "code", "file_path", "path", "pattern", "query", "url", "message"):
        if key in inp:
            v = inp[key]
            if isinstance(v, list):
                v = " ".join(map(str, v))
            v = str(v).replace("\n", " ")
            return v[:200] + ("…" if len(v) > 200 else "")
    v = json.dumps(inp, ensure_ascii=False)
    return v[:200] + ("…" if len(v) > 200 else "")


def summarize_patch(input_text):
    """For apply_patch: list the files touched, else first line."""
    if not isinstance(input_text, str):
        return str(input_text)[:200]
    files = [ln.strip() for ln in input_text.splitlines() if ln.lstrip().startswith("***")
             and "Patch" not in ln]
    if files:
        return "; ".join(files)[:300]
    first = input_text.strip().splitlines()[0] if input_text.strip() else ""
    return first[:200]


def clean_output(out):
    """Normalise a tool output to text and strip Codex's exec preamble.

    Returns (text, failed). `out` may be a str, a dict, or (Codex >= 0.150) a
    list of {"type": "input_text", "text": ...} blocks. The preamble looks like
    "Script completed\\nWall time 0.2 seconds\\nOutput:\\n" (or "Script failed",
    or just "Wall time: 1.2 seconds\\nOutput:") and is only stripped when it sits
    at the head of the output.
    """
    if isinstance(out, dict):
        out = out.get("content") or out.get("output") or json.dumps(out)
    if isinstance(out, list):
        out = chat_log.text_of(out, "[image]")
    if not isinstance(out, str):
        out = str(out)
    failed = out.lstrip().startswith("Script failed")
    head = out[:400]
    m = re.search(r"^(?:Script [^\n]*\n)?(?:Wall time[^\n]*\n)?Output:[ \t]*\n?", head)
    if m:
        out = out[m.end():]
    return out, failed


def read(rows):
    """The rollout as a printer.Chat: every block in order, and the chat's facts."""
    meta = {}
    turn_ctx = {}
    timestamps = []
    n_reasoning = 0
    for r in rows:
        t = r.get("type")
        if r.get("timestamp"):
            timestamps.append(r["timestamp"])
        if t == "session_meta" and not meta:
            meta = r.get("payload", {})
        elif t == "turn_context" and not turn_ctx:
            turn_ctx = r.get("payload", {})

    have_event_users = any(user_message_of(r) for r in rows)

    messages = []
    for r in rows:
        t = r.get("type")
        p = r.get("payload", {})
        if not isinstance(p, dict):
            continue
        pt = p.get("type")

        if t == "event_msg":
            msg = user_message_of(r)
            if msg and have_event_users:
                messages.append(printer.Message("user", msg))
            continue

        if t == "response_item":
            if pt == "message":
                role = p.get("role")
                txt = chat_log.text_of(p.get("content"), "[image]").strip()
                if not txt:
                    continue
                if role == "assistant":
                    messages.append(printer.Message("assistant", txt))
                elif role == "user" and not have_event_users:
                    if not adapter_lib.injected(txt):
                        messages.append(printer.Message("user", txt))
                # developer/system roles are skipped
            elif pt == "reasoning":
                n_reasoning += 1
            elif pt == "function_call":
                messages.append(printer.Message(
                    "call", f"{p.get('name')}({summarize_call(p.get('name'), p.get('arguments'))})"))
            elif pt == "custom_tool_call":
                name = p.get("name")
                if name == "apply_patch":
                    arg = summarize_patch(p.get("input"))
                elif name == "exec":
                    arg = summarize_exec_input(p.get("input"))
                else:
                    arg = str(p.get("input"))[:200]
                messages.append(printer.Message("call", f"{name}({arg})"))
            elif pt in ("function_call_output", "custom_tool_call_output"):
                res, failed = clean_output(p.get("output"))
                res = res.strip()
                if res:
                    messages.append(printer.Message("result", res, error=failed))

    git = meta.get("git") or {}
    return printer.Chat(
        messages=messages, words=WORDS,
        session_id=meta.get("id", "?"), cwd=meta.get("cwd"), branch=git.get("branch"),
        repo=git.get("repository_url") or None,
        model=turn_ctx.get("model") or meta.get("model"),
        effort=turn_ctx.get("collaboration_mode", {}).get("settings", {}).get("reasoning_effort"),
        cli=meta.get("cli_version"),
        span=(min(timestamps), max(timestamps)) if timestamps else None,
        reasoning=n_reasoning,
    )


def patch_files(text):
    """The files an apply_patch names in its headers, once each, in order."""
    files = re.findall(r"\*\*\* (?:Add|Update|Delete|Move to) File: ([^\\\n\"]+)", text)
    return list(dict.fromkeys(f.strip() for f in files))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--max-result-chars", type=int, default=500)
    args = ap.parse_args()

    matches = locate(args.session_id)
    if not matches:
        sys.exit(f"stop: no Codex rollout found for id '{args.session_id}' under {' or '.join(str(f) for f in rollout_io.data_folders())}: pass the full UUID or a unique prefix; list recent ones with ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head")
    path = printer.only_match(matches, args.session_id)
    try:
        rows = load(path)
    except rollout_io.NoZstd as e:
        sys.exit(f"stop: {path} {e}")

    chat = read(rows)
    mode = "summary" if args.summary else "balanced"
    print(printer.transcript(chat, mode, args.max_result_chars))


if __name__ == "__main__":
    main()
