#!/usr/bin/env python3
"""Locate a Claude Code session by ID and render a clean, context-friendly transcript.

Session transcripts live at ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl.
This walks every project dir, finds the matching file (exact id, then unique
prefix), and prints a markdown transcript suitable for loading into another
Claude Code conversation.

Usage:
    extract_session.py <session-id> [--full] [--summary] [--tail N]
                                    [--after-compact] [--max-result-chars N] [--list]

Modes (default = balanced: prompts + assistant text in full, tool calls as
one-liners, tool results truncated, thinking omitted):
    --summary           only user prompts + assistant text (most compact)
    --full              include thinking, full tool results, no truncation
    --tail N            only the last N user turns
    --after-compact     start at the last compaction summary (it already covers
                        everything before it), dropping the pre-compact history
    --max-result-chars  per tool-result truncation cap (default 500)
    --list              print the located file path, metadata and the rendered
                        size of each mode, no transcript
    --skeleton          the deterministic state skeleton (title, first prompt, last
                        reply, files edited, PR link, recap rows) followed by the
                        last N user turns in summary mode (N = --tail, default 3);
                        implies --after-compact
"""
import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime

PROJECTS_DIR = os.path.expanduser("~/.claude/projects")


def locate(session_id):
    """Return list of (path) matching the id. Strips .jsonl if given."""
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


def is_noise_string(s):
    """Slash-command plumbing / injected wrappers we don't want verbatim."""
    s = s.lstrip()
    return s.startswith((
        "<local-command-caveat>",
        "<local-command-stdout>",
        "<command-stdout>",
        "<bash-stdout>",
        "<bash-input>",
    ))


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
    try:
        v = json.dumps(inp, ensure_ascii=False)
    except Exception:
        v = str(inp)
    return v[:200] + ("…" if len(v) > 200 else "")


def extract_text_from_result(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict):
                if b.get("type") == "text":
                    parts.append(b.get("text", ""))
                elif b.get("type") == "image":
                    parts.append("[image]")
            elif isinstance(b, str):
                parts.append(b)
        return "\n".join(parts)
    return str(content)


def render(rows, mode, tail, max_result_chars, after_compact=False, header=True):
    # Metadata
    meta = {}
    title = None
    timestamps = []
    n_user = n_asst = n_thinking = n_tools = 0
    for r in rows:
        t = r.get("type")
        if t == "ai-title":
            title = r.get("aiTitle") or title
        if r.get("timestamp"):
            timestamps.append(r["timestamp"])
        for k in ("cwd", "gitBranch", "version", "sessionId"):
            if r.get(k) and k not in meta:
                meta[k] = r[k]

    # Build ordered transcript blocks
    blocks = []  # list of (kind, text)
    n_compact = 0

    def add_user_text(txt, is_compact):
        nonlocal n_compact
        if not txt or is_noise_string(txt):
            return
        if is_compact:
            n_compact += 1
            blocks.append(("compact", txt.strip()))
            return
        note = parse_task_notification(txt)
        if note:
            blocks.append(("tool", note))
            return
        slash = parse_slash_command(txt)
        if slash and not slash.split(None, 3)[3:]:
            blocks.append(("tool", slash))   # bare slash command: plumbing, not a turn
        else:
            blocks.append(("user", slash or txt.strip()))

    for r in rows:
        t = r.get("type")
        if t == "user":
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
                        if mode == "summary":
                            continue
                        res = extract_text_from_result(b.get("content"))
                        is_err = b.get("is_error")
                        if mode != "full" and len(res) > max_result_chars:
                            res = res[:max_result_chars] + f"\n… [+{len(res) - max_result_chars} chars truncated]"
                        prefix = "tool error" if is_err else "tool result"
                        blocks.append(("result", f"[{prefix}] {res.strip()}"))
        elif t == "assistant":
            content = r.get("message", {}).get("content")
            if not isinstance(content, list):
                if isinstance(content, str) and content.strip():
                    blocks.append(("assistant", content.strip()))
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                bt = b.get("type")
                if bt == "text":
                    txt = b.get("text", "").strip()
                    if txt:
                        blocks.append(("assistant", txt))
                elif bt == "thinking":
                    n_thinking += 1
                    if mode == "full":
                        blocks.append(("thinking", b.get("thinking", "").strip()))
                elif bt == "tool_use":
                    n_tools += 1
                    if mode == "summary":
                        continue
                    blocks.append(("tool", f"→ {b.get('name')}({summarize_tool_input(b.get('name'), b.get('input'))})"))

    n_user = sum(1 for k, _ in blocks if k == "user")
    n_asst = sum(1 for k, _ in blocks if k == "assistant")

    # after-compact: the last compaction summary already covers everything before it
    if after_compact:
        idxs = [i for i, (k, _) in enumerate(blocks) if k == "compact"]
        if idxs:
            blocks = blocks[idxs[-1]:]

    # tail: keep blocks from the last N user turns onward
    if tail:
        idxs = [i for i, (k, _) in enumerate(blocks) if k == "user"]
        if len(idxs) > tail:
            blocks = blocks[idxs[-tail]:]
    if not header:
        blocks = [b for b in blocks if b[0] != "compact"]

    out = []
    if not header:
        out.append(f"## Last {tail} user turns (verbatim, summary mode)" if tail else "## Transcript (summary mode)")
        out.append("")
    if header:
        out.append("# Loaded session transcript")
    if header and title:
        out.append(f"**Title:** {title}")
    if header:
        out.append(f"**Session ID:** `{meta.get('sessionId', '?')}`")
        if meta.get("cwd"):
            out.append(f"**Project (cwd):** `{meta['cwd']}`")
        if meta.get("gitBranch"):
            out.append(f"**Git branch:** `{meta['gitBranch']}`")
        if timestamps:
            out.append(f"**Span:** {fmt_ts(min(timestamps))} → {fmt_ts(max(timestamps))}")
        counts = f"**Activity:** {n_user} user prompts · {n_asst} assistant replies · {n_tools} tool calls · {n_thinking} thinking blocks"
        if n_compact:
            counts += f" · {n_compact} compaction summar{'y' if n_compact == 1 else 'ies'}"
        out.append(counts)
        out.append(f"**Render mode:** {mode}" + (f" · tail {tail}" if tail else "") + (" · after last compaction" if after_compact else ""))
        out.append("\n---\n")

    label = {"user": "## 🧑 User", "assistant": "## 🤖 Assistant",
             "tool": "", "result": "", "thinking": "## 💭 Thinking",
             "compact": "## 📦 Compaction summary (auto-generated recap of everything above it)"}
    for kind, text in blocks:
        if kind in ("tool", "result"):
            out.append(text)
        else:
            out.append(label[kind])
            out.append(text)
        out.append("")
    return "\n".join(out)


COMPACT_SECTIONS = ("Pending Tasks", "Current Work", "Optional Next Step")


def compact_recap(text):
    """Pull the forward-looking sections out of a compaction summary."""
    parts = re.split(r"^\s*\d+\.\s+(?=[A-Z][^:\n]{2,40}:)", text, flags=re.M)
    keep = []
    for part in parts:
        head = part.split(":", 1)[0].strip()
        if head in COMPACT_SECTIONS:
            # the last section carries the harness boilerplate that follows the summary; drop it
            part = re.split(r"^\s*(?:If you need specific details|Continue the conversation)", part, flags=re.M)[0]
            keep.append(part.strip())
    return "\n".join(keep) if keep else text[:1500].strip()


def render_skeleton(rows, tail, max_result_chars):
    meta = {}
    title = None
    timestamps = []
    pr = None
    away = None
    compact = None
    first_user = None
    last_asst = None
    edited = []
    for r in rows:
        t = r.get("type")
        if r.get("timestamp"):
            timestamps.append(r["timestamp"])
        for k in ("cwd", "gitBranch", "sessionId"):
            if r.get(k) and k not in meta:
                meta[k] = r[k]
        if t == "ai-title":
            title = r.get("aiTitle") or title
        elif t == "pr-link":
            pr = r.get("prUrl") or pr
        elif t == "system" and r.get("subtype") == "away_summary":
            away = r.get("content") or away
        elif t == "user" and not r.get("isMeta"):
            content = r.get("message", {}).get("content")
            texts = [content] if isinstance(content, str) else [
                b.get("text", "") for b in (content or []) if isinstance(b, dict) and b.get("type") == "text"]
            for txt in texts:
                txt = (txt or "").strip()
                if not txt or is_noise_string(txt) or parse_task_notification(txt):
                    continue
                if r.get("isCompactSummary"):
                    compact = txt
                elif first_user is None and not parse_slash_command(txt):
                    first_user = txt
        elif t == "assistant":
            for b in r.get("message", {}).get("content", []) or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and b.get("text", "").strip():
                    last_asst = b["text"].strip()
                elif b.get("type") == "tool_use" and b.get("name") in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
                    fp = (b.get("input") or {}).get("file_path") or (b.get("input") or {}).get("notebook_path")
                    if fp and fp not in edited:
                        edited.append(fp)

    out = ["# Session skeleton (deterministic, from the log)"]
    if title:
        out.append(f"**Title:** {title}")
    out.append(f"**Session ID:** `{meta.get('sessionId', '?')}`")
    if meta.get("cwd"):
        out.append(f"**Project (cwd):** `{meta['cwd']}`")
    if meta.get("gitBranch"):
        out.append(f"**Git branch:** `{meta['gitBranch']}`")
    if pr:
        out.append(f"**PR:** {pr}")
    if timestamps:
        out.append(f"**Span:** {fmt_ts(min(timestamps))} → {fmt_ts(max(timestamps))}")
    out.append("")
    out.append("**First prompt:**")
    out.append((first_user or "(none)")[:1500])
    out.append("")
    if away:
        out.append("**Last away recap (written by the assistant when the user stepped away):**")
        out.append(away.strip())
        out.append("")
    if compact:
        out.append("**From the last compaction summary:**")
        out.append(compact_recap(compact))
        out.append("")
    out.append("**Files edited (Edit/Write):**")
    out.extend(f"- `{fp}`" for fp in edited) if edited else out.append("- none")
    out.append("")
    out.append("**Last assistant reply:**")
    la = last_asst or "(none)"
    out.append(la[:2000] + (f"\n… [+{len(la) - 2000} chars truncated]" if len(la) > 2000 else ""))
    out.append("")
    out.append("---")
    out.append("")
    out.append(render(rows, "summary", tail or 3, max_result_chars, after_compact=True, header=False))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--tail", type=int, default=0)
    ap.add_argument("--after-compact", action="store_true")
    ap.add_argument("--max-result-chars", type=int, default=500)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--skeleton", action="store_true")
    args = ap.parse_args()

    matches = locate(args.session_id)
    if not matches:
        print(f"No session file found for id '{args.session_id}' under {PROJECTS_DIR}", file=sys.stderr)
        print("Tip: pass the full UUID, or a unique prefix. List sessions with:", file=sys.stderr)
        print("  ls ~/.claude/projects/*/*.jsonl", file=sys.stderr)
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
        title = next((r.get("aiTitle") for r in reversed(rows) if r.get("type") == "ai-title"), None)
        cwd = next((r.get("cwd") for r in rows if r.get("cwd")), None)
        n_users = render(rows, "summary", 0, args.max_result_chars).count("\n## 🧑 User\n")
        n_compact = sum(1 for r in rows if r.get("type") == "user" and r.get("isCompactSummary"))
        print(f"path:    {path}")
        print(f"title:   {title}")
        print(f"cwd:     {cwd}")
        print(f"lines:   {len(rows)}")
        print(f"turns:   {n_users} user prompts" + (f" · {n_compact} compaction summar{'y' if n_compact == 1 else 'ies'} (use --after-compact to skip the pre-compact history)" if n_compact else ""))
        print("size (chars / ~tokens at 4 chars per token):")
        for m in ("summary", "balanced", "full"):
            n = len(render(rows, m, 0, args.max_result_chars))
            line = f"  {m:<9} {n:>10,} chars  ~{n // 4:>8,} tokens"
            if n_compact:
                n2 = len(render(rows, m, 0, args.max_result_chars, after_compact=True))
                line += f"   (after-compact: {n2:,} chars ~{n2 // 4:,} tokens)"
            print(line)
        return

    if args.skeleton:
        print(render_skeleton(rows, args.tail, args.max_result_chars))
        return

    mode = "summary" if args.summary else "full" if args.full else "balanced"
    print(render(rows, mode, args.tail, args.max_result_chars, args.after_compact))


if __name__ == "__main__":
    main()
