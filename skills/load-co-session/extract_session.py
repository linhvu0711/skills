#!/usr/bin/env python3
"""Locate a Codex CLI session (rollout) by ID and render a clean transcript.

Codex stores each session as a rollout JSONL under
  ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl
and archived ones under
  ~/.codex/archived_sessions/rollout-<timestamp>-<session-id>.jsonl
The session ID is the trailing UUID in the filename (and in session_meta.id).

Rollout entries have a top-level `type` (session_meta | turn_context | event_msg
| response_item) and a `payload`. Human turns live in event_msg/user_message
(Codex < 0.150) or event_msg/item_completed with item.type == "UserMessage"
(Codex >= 0.150, Aug 2026); response_item/message role=user is the last-resort
fallback. Assistant text + tool activity live in response_item. Reasoning blocks
are encrypted on disk, so only their count is surfaced.

Usage:
    extract_session.py <session-id> [--full] [--summary] [--tail N]
                                    [--max-result-chars N] [--list]

Modes (default = balanced: prompts + assistant text in full, tool calls as
one-liners, tool results truncated):
    --summary           only user prompts + assistant text (most compact)
    --full              full tool results, no truncation
    --tail N            only the last N user turns
    --max-result-chars  per tool-result truncation cap (default 500)
    --list              just print located file path + metadata, no transcript
    --skeleton          the deterministic state skeleton (first prompt, last reply,
                        files patched) followed by the last N user turns in summary
                        mode (N = --tail, default 3)
"""
import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime

CODEX_DIR = os.path.expanduser("~/.codex")

# Prefixes that mark injected context (AGENTS.md, environment, instructions)
# rather than a real human turn — used only in the response_item fallback path.
INJECTION_MARKERS = (
    "# AGENTS.md instructions",
    "<INSTRUCTIONS>",
    "<environment_context>",
    "<user_instructions>",
    "# Collaboration Mode",
    "<user_shell_environment>",
)


def locate(session_id):
    """Return rollout file paths matching the id (exact uuid, then prefix)."""
    sid = session_id.strip().strip("`'\"")
    if sid.endswith(".jsonl"):
        sid = sid[:-6]
    # the uuid is embedded after the timestamp in the filename
    patterns = [
        os.path.join(CODEX_DIR, "sessions", "**", f"rollout-*{sid}*.jsonl"),
        os.path.join(CODEX_DIR, "archived_sessions", f"rollout-*{sid}*.jsonl"),
    ]
    hits = []
    for p in patterns:
        hits.extend(glob.glob(p, recursive=True))
    return sorted(set(hits))


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def fmt_ts(ts):
    if not ts:
        return ""
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts


def text_blocks(content):
    """Join input_text / output_text / text blocks from a message content list."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts = []
    for b in content:
        if isinstance(b, dict):
            if b.get("type") in ("input_text", "output_text", "text"):
                parts.append(b.get("text", ""))
            elif b.get("type") in ("input_image", "output_image", "image"):
                parts.append("[image]")
        elif isinstance(b, str):
            parts.append(b)
    return "\n".join(p for p in parts if p)


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
            return text_blocks(item.get("content")).strip() or None
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
        files = re.findall(r"\*\*\* (?:Add|Update|Delete|Move to) File: ([^\\\n\"]+)", input_text)
        if files:
            return "apply_patch: " + "; ".join(dict.fromkeys(files))[:300]
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
        out = text_blocks(out)
    if not isinstance(out, str):
        out = str(out)
    failed = out.lstrip().startswith("Script failed")
    head = out[:400]
    m = re.search(r"^(?:Script [^\n]*\n)?(?:Wall time[^\n]*\n)?Output:[ \t]*\n?", head)
    if m:
        out = out[m.end():]
    return out, failed


def render(rows, mode, tail, max_result_chars, header=True):
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

    blocks = []  # (kind, text)
    first_user = None
    for r in rows:
        t = r.get("type")
        p = r.get("payload", {})
        if not isinstance(p, dict):
            continue
        pt = p.get("type")

        if t == "event_msg":
            msg = user_message_of(r)
            if msg and have_event_users:
                blocks.append(("user", msg))
                if first_user is None:
                    first_user = msg
            continue

        if t == "response_item":
            if pt == "message":
                role = p.get("role")
                txt = text_blocks(p.get("content")).strip()
                if not txt:
                    continue
                if role == "assistant":
                    blocks.append(("assistant", txt))
                elif role == "user" and not have_event_users:
                    if not txt.lstrip().startswith(INJECTION_MARKERS):
                        blocks.append(("user", txt))
                        if first_user is None:
                            first_user = txt
                # developer/system roles are skipped
            elif pt == "reasoning":
                n_reasoning += 1
            elif pt == "function_call":
                if mode == "summary":
                    continue
                blocks.append(("tool", f"→ {p.get('name')}({summarize_call(p.get('name'), p.get('arguments'))})"))
            elif pt == "custom_tool_call":
                if mode == "summary":
                    continue
                name = p.get("name")
                if name == "apply_patch":
                    arg = summarize_patch(p.get("input"))
                elif name == "exec":
                    arg = summarize_exec_input(p.get("input"))
                else:
                    arg = str(p.get("input"))[:200]
                blocks.append(("tool", f"→ {name}({arg})"))
            elif pt in ("function_call_output", "custom_tool_call_output"):
                if mode == "summary":
                    continue
                res, failed = clean_output(p.get("output"))
                res = res.strip()
                if mode != "full" and len(res) > max_result_chars:
                    res = res[:max_result_chars] + f"\n… [+{len(res) - max_result_chars} chars truncated]"
                if res:
                    blocks.append(("result", f"[{'tool error' if failed else 'tool result'}] {res}"))

    n_user = sum(1 for k, _ in blocks if k == "user")
    n_asst = sum(1 for k, _ in blocks if k == "assistant")
    n_tools = sum(1 for k, _ in blocks if k == "tool")

    if tail:
        idxs = [i for i, (k, _) in enumerate(blocks) if k == "user"]
        if len(idxs) > tail:
            blocks = blocks[idxs[-tail]:]

    title = (first_user.splitlines()[0][:80] + "…") if first_user else None
    git = meta.get("git") or {}

    out = []
    if not header:
        out.append(f"## Last {tail} user turns (verbatim, summary mode)" if tail else "## Transcript (summary mode)")
        out.append("")
    else:
        out.append("# Loaded Codex session transcript")
        if title:
            out.append(f"**First prompt:** {title}")
        out.append(f"**Session ID:** `{meta.get('id', '?')}`")
        if meta.get("cwd"):
            out.append(f"**Project (cwd):** `{meta['cwd']}`")
        if git.get("branch"):
            repo = git.get("repository_url", "")
            out.append(f"**Git branch:** `{git['branch']}`" + (f" · {repo}" if repo else ""))
        model = turn_ctx.get("model") or meta.get("model")
        if model:
            eff = turn_ctx.get("collaboration_mode", {}).get("settings", {}).get("reasoning_effort")
            out.append(f"**Model:** {model}" + (f" (reasoning: {eff})" if eff else ""))
        if meta.get("cli_version"):
            out.append(f"**Codex CLI:** {meta['cli_version']}")
        if timestamps:
            out.append(f"**Span:** {fmt_ts(min(timestamps))} → {fmt_ts(max(timestamps))}")
        out.append(f"**Activity:** {n_user} user prompts · {n_asst} assistant replies · {n_tools} tool calls · {n_reasoning} reasoning blocks (encrypted)")
        out.append(f"**Render mode:** {mode}" + (f" · tail {tail}" if tail else ""))
        out.append("\n---\n")

    label = {"user": "## 🧑 User", "assistant": "## 🤖 Codex"}
    for kind, text in blocks:
        if kind in ("tool", "result"):
            out.append(text)
        else:
            out.append(label[kind])
            out.append(text)
        out.append("")
    return "\n".join(out)


def patched_files(p):
    """File paths an apply_patch touched, whether direct or wrapped in an exec JS call."""
    name = p.get("name")
    src = p.get("input") if isinstance(p.get("input"), str) else ""
    if name == "apply_patch" or (name == "exec" and "apply_patch" in src):
        files = re.findall(r"\*\*\* (?:Add|Update|Delete|Move to) File: ([^\\\n\"]+)", src)
        return list(dict.fromkeys(f.strip() for f in files))
    return []


def render_skeleton(rows, tail, max_result_chars):
    meta = {}
    turn_ctx = {}
    timestamps = []
    first_user = None
    last_asst = None
    edited = []
    have_event_users = any(user_message_of(r) for r in rows)
    for r in rows:
        t = r.get("type")
        p = r.get("payload") or {}
        if r.get("timestamp"):
            timestamps.append(r["timestamp"])
        if t == "session_meta" and not meta:
            meta = p
        elif t == "turn_context" and not turn_ctx:
            turn_ctx = p
        elif t == "event_msg":
            msg = user_message_of(r)
            if msg and have_event_users and first_user is None:
                first_user = msg
        elif t == "response_item":
            pt = p.get("type")
            if pt == "message":
                txt = text_blocks(p.get("content")).strip()
                if p.get("role") == "assistant" and txt:
                    last_asst = txt
                elif p.get("role") == "user" and not have_event_users and first_user is None \
                        and txt and not txt.lstrip().startswith(INJECTION_MARKERS):
                    first_user = txt
            elif pt in ("custom_tool_call", "function_call"):
                for fp in patched_files(p):
                    if fp not in edited:
                        edited.append(fp)

    git = meta.get("git") or {}
    out = ["# Codex session skeleton (deterministic, from the rollout)"]
    out.append(f"**Session ID:** `{meta.get('id', '?')}`")
    if meta.get("cwd"):
        out.append(f"**Project (cwd):** `{meta['cwd']}`")
    if git.get("branch"):
        out.append(f"**Git branch:** `{git['branch']}`")
    model = turn_ctx.get("model") or meta.get("model")
    if model:
        out.append(f"**Model:** {model}")
    if timestamps:
        out.append(f"**Span:** {fmt_ts(min(timestamps))} → {fmt_ts(max(timestamps))}")
    out.append("")
    out.append("**First prompt:**")
    out.append((first_user or "(none)")[:1500])
    out.append("")
    out.append("**Files patched (apply_patch):**")
    out.extend(f"- `{fp}`" for fp in edited) if edited else out.append("- none")
    out.append("")
    out.append("**Last Codex reply:**")
    la = last_asst or "(none)"
    out.append(la[:2000] + (f"\n… [+{len(la) - 2000} chars truncated]" if len(la) > 2000 else ""))
    out.append("")
    out.append("---")
    out.append("")
    out.append(render(rows, "summary", tail or 3, max_result_chars, header=False))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--tail", type=int, default=0)
    ap.add_argument("--max-result-chars", type=int, default=500)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--skeleton", action="store_true")
    args = ap.parse_args()

    matches = locate(args.session_id)
    if not matches:
        print(f"No Codex rollout found for id '{args.session_id}' under {CODEX_DIR}", file=sys.stderr)
        print("Tip: pass the full UUID, or a unique prefix. Recent sessions:", file=sys.stderr)
        print("  ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head", file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        print(f"Ambiguous id '{args.session_id}' — {len(matches)} matches:", file=sys.stderr)
        for m in matches:
            print(f"  {m}", file=sys.stderr)
        print("Pass the full UUID to disambiguate.", file=sys.stderr)
        sys.exit(2)

    path = matches[0]
    rows = load(path)

    if args.list:
        meta = next((r.get("payload", {}) for r in rows if r.get("type") == "session_meta"), {})
        first_user = next((m for m in (user_message_of(r) for r in rows) if m), None)
        if first_user is None:
            for r in rows:
                p = r.get("payload") or {}
                if r.get("type") == "response_item" and p.get("type") == "message" and p.get("role") == "user":
                    txt = text_blocks(p.get("content")).strip()
                    if txt and not txt.startswith(INJECTION_MARKERS):
                        first_user = txt
                        break
        src = meta.get("source")
        spawn = (src.get("subagent") or {}).get("thread_spawn") if isinstance(src, dict) else None
        print(f"path:   {path}")
        print(f"id:     {meta.get('id')}")
        print(f"cwd:    {meta.get('cwd')}")
        branch = (meta.get("git") or {}).get("branch")
        if branch:
            print(f"branch: {branch}")
        if spawn:
            print(f"thread: subagent '{spawn.get('agent_nickname')}' ({spawn.get('agent_role')}) of parent {spawn.get('parent_thread_id')}")
        else:
            print(f"thread: {meta.get('thread_source') or 'user'} via {meta.get('originator') or src}")
        print(f"prompt: {(first_user or '').splitlines()[0][:100] if first_user else ''}")
        print(f"lines:  {len(rows)}")
        n_users = sum(1 for r in rows if user_message_of(r))
        print(f"turns:  {n_users} user prompts")
        print("size (chars / ~tokens at 4 chars per token):")
        for m in ("summary", "balanced", "full"):
            n = len(render(rows, m, 0, args.max_result_chars))
            print(f"  {m:<9} {n:>10,} chars  ~{n // 4:>8,} tokens")
        return

    if args.skeleton:
        print(render_skeleton(rows, args.tail, args.max_result_chars))
        return

    mode = "summary" if args.summary else "full" if args.full else "balanced"
    print(render(rows, mode, args.tail, args.max_result_chars))


if __name__ == "__main__":
    main()
