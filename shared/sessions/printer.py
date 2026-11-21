"""Print one past chat, whatever harness wrote it.

Each harness's extract_session.py reads its own log into a Chat: a plain list
of Messages, the chat's facts, and the Words the harness calls its parts by.
This module prints that Chat as a transcript in one of three modes, as a
skeleton, or as the --list summary, so every harness prints the same layout.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from datetime import datetime

MODES = ("summary", "balanced", "full")
# The kinds each mode prints; user, assistant, note, and compact print in all.
SHOWN = {
    "summary": {"user", "assistant", "note", "compact"},
    "balanced": {"user", "assistant", "note", "compact", "call", "result"},
    "full": {"user", "assistant", "note", "compact", "call", "result", "thinking"},
}
COMPACT_LABEL = "## 📦 Compaction summary (auto-generated recap of everything above it)"


@dataclass(frozen=True)
class Words:
    """What a harness calls the parts of its chat."""

    transcript: str  # heading of a transcript
    skeleton: str  # heading of a skeleton
    assistant: str  # label of a reply
    last_reply: str  # skeleton heading of the last reply
    edits: str  # skeleton heading of the files the chat edited
    cli: str  # label of the cli version line, when the chat has one


@dataclass(frozen=True)
class Message:
    """One block of a chat, in log order.

    kind is user, assistant, thinking, call (text is `name(args)`), result,
    note (a plumbing line every mode prints and nothing counts), or compact.
    """

    kind: str
    text: str
    error: bool = False  # a result: the tool failed
    files: tuple[str, ...] = ()  # a call: the files it edited
    command: bool = False  # a user turn that is a slash command with arguments


@dataclass(frozen=True)
class Chat:
    messages: list[Message]
    words: Words
    session_id: str | None = None
    cwd: str | None = None
    branch: str | None = None
    repo: str | None = None
    model: str | None = None
    effort: str | None = None
    cli: str | None = None
    pr: str | None = None
    title: str | None = None
    away: str | None = None  # the last recap written while the user was away
    recap: str | None = None  # the forward-looking part of the last compaction
    span: tuple[str, str] | None = None  # first and last raw timestamps
    reasoning: int | None = None  # set: encrypted reasoning blocks, in place of thinking
    facts: tuple[tuple[str, object], ...] = ()  # --list lines after `path`
    lines: int = 0  # rows in the log


def _when(ts: str) -> str:
    if not ts:
        return ""
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts


def _cut(text: str, limit: int) -> str:
    if len(text) > limit:
        return text[:limit] + f"\n… [+{len(text) - limit} chars truncated]"
    return text


def _first_at(chat: Chat) -> int | None:
    return next((i for i, m in enumerate(chat.messages) if m.kind == "user" and not m.command and m.text), None)


def _first_prompt(chat: Chat) -> str | None:
    at = _first_at(chat)
    return chat.messages[at].text if at is not None else None


def _count(chat: Chat, kind: str) -> int:
    return sum(1 for m in chat.messages if m.kind == kind)


def _compactions(n: int) -> str:
    return f"{n} compaction summar{'y' if n == 1 else 'ies'}"


def _blocks(chat: Chat, mode: str, tail: int, max_result_chars: int, after_compact: bool) -> list[Message]:
    blocks = [m for m in chat.messages if m.kind in SHOWN[mode]]
    if after_compact:
        idxs = [i for i, m in enumerate(blocks) if m.kind == "compact"]
        if idxs:
            blocks = blocks[idxs[-1]:]
    if tail:
        idxs = [i for i, m in enumerate(blocks) if m.kind == "user"]
        if len(idxs) > tail:
            blocks = blocks[idxs[-tail]:]
    return blocks


def _lines(chat: Chat, blocks: list[Message], mode: str, max_result_chars: int) -> list[str]:
    label = {"user": "## 🧑 User", "assistant": f"## 🤖 {chat.words.assistant}",
             "thinking": "## 💭 Thinking", "compact": COMPACT_LABEL}
    out = []
    for m in blocks:
        if m.kind == "call":
            out.append(f"→ {m.text}")
        elif m.kind == "result":
            text = m.text if mode == "full" else _cut(m.text, max_result_chars)
            out.append(f"[{'tool error' if m.error else 'tool result'}] {text.strip()}")
        elif m.kind == "note":
            out.append(m.text)
        else:
            out.append(label[m.kind])
            out.append(m.text)
        out.append("")
    return out


def transcript(chat: Chat, mode: str, tail: int = 0, max_result_chars: int = 500,
               after_compact: bool = False) -> str:
    """The chat as markdown: a header, then its blocks in this mode."""
    at = _first_at(chat)
    compacts = [i for i, m in enumerate(chat.messages) if m.kind == "compact"]
    # --after-compact promises nothing from before the last compaction, the header too.
    if after_compact and compacts and at is not None and at < compacts[-1]:
        at = None
    first = chat.messages[at].text if at is not None else None
    out = [f"# {chat.words.transcript}"]
    if chat.title:
        out.append(f"**Title:** {chat.title}")
    elif first:
        out.append(f"**First prompt:** {first.splitlines()[0][:80]}…")
    out.append(f"**Session ID:** `{chat.session_id if chat.session_id is not None else '?'}`")
    if chat.cwd:
        out.append(f"**Project (cwd):** `{chat.cwd}`")
    if chat.branch:
        out.append(f"**Git branch:** `{chat.branch}`" + (f" · {chat.repo}" if chat.repo else ""))
    if chat.model:
        out.append(f"**Model:** {chat.model}" + (f" (reasoning: {chat.effort})" if chat.effort else ""))
    if chat.cli:
        out.append(f"**{chat.words.cli}:** {chat.cli}")
    if chat.span:
        out.append(f"**Span:** {_when(chat.span[0])} → {_when(chat.span[1])}")
    activity = (f"**Activity:** {_count(chat, 'user')} user prompts · {_count(chat, 'assistant')} assistant replies"
                f" · {_count(chat, 'call')} tool calls · ")
    if chat.reasoning is not None:
        activity += f"{chat.reasoning} reasoning blocks (encrypted)"
    else:
        activity += f"{_count(chat, 'thinking')} thinking blocks"
    if _count(chat, "compact"):
        activity += f" · {_compactions(_count(chat, 'compact'))}"
    out.append(activity)
    out.append(f"**Render mode:** {mode}" + (f" · tail {tail}" if tail else "")
               + (" · after last compaction" if after_compact else ""))
    out.append("\n---\n")
    out += _lines(chat, _blocks(chat, mode, tail, max_result_chars, after_compact), mode, max_result_chars)
    return "\n".join(out)


def skeleton(chat: Chat, tail: int = 0) -> str:
    """The fixed facts of the chat, then its last user turns in summary mode."""
    out = [f"# {chat.words.skeleton}"]
    if chat.title:
        out.append(f"**Title:** {chat.title}")
    out.append(f"**Session ID:** `{chat.session_id if chat.session_id is not None else '?'}`")
    if chat.cwd:
        out.append(f"**Project (cwd):** `{chat.cwd}`")
    if chat.branch:
        out.append(f"**Git branch:** `{chat.branch}`")
    if chat.model:
        out.append(f"**Model:** {chat.model}")
    if chat.pr:
        out.append(f"**PR:** {chat.pr}")
    if chat.span:
        out.append(f"**Span:** {_when(chat.span[0])} → {_when(chat.span[1])}")
    out.append("")
    out.append("**First prompt:**")
    out.append((_first_prompt(chat) or "(none)")[:1500])
    out.append("")
    if chat.away:
        out.append("**Last away recap (written by the assistant when the user stepped away):**")
        out.append(chat.away.strip())
        out.append("")
    if chat.recap:
        out.append("**From the last compaction summary:**")
        out.append(chat.recap)
        out.append("")
    edited = list(dict.fromkeys(f for m in chat.messages if m.kind == "call" for f in m.files))
    out.append(f"**{chat.words.edits}:**")
    out.extend(f"- `{fp}`" for fp in edited) if edited else out.append("- none")
    out.append("")
    out.append(f"**{chat.words.last_reply}:**")
    last = next((m.text for m in reversed(chat.messages) if m.kind == "assistant"), None) or "(none)"
    out.append(_cut(last, 2000))
    out.append("")
    out.append("---")
    out.append("")
    n = tail or 3
    out.append(f"## Last {n} user turns (verbatim, summary mode)")
    out.append("")
    blocks = [m for m in _blocks(chat, "summary", n, 500, True) if m.kind != "compact"]
    out += _lines(chat, blocks, "summary", 500)
    return "\n".join(out)


def listing(chat: Chat, path: str, max_result_chars: int) -> str:
    """Where the chat is, its facts, and the size of each mode."""
    out = [f"{'path:':<8}{path}"]
    out += [f"{label + ':':<8}{value}" for label, value in chat.facts]
    out.append(f"{'lines:':<8}{chat.lines}")
    compacts = _count(chat, "compact")
    out.append(f"{'turns:':<8}{_count(chat, 'user')} user prompts"
               + (f" · {_compactions(compacts)} (use --after-compact to skip the pre-compact history)" if compacts else ""))
    out.append("size (chars / ~tokens at 4 chars per token):")
    for m in MODES:
        n = len(transcript(chat, m, 0, max_result_chars))
        line = f"  {m:<9} {n:>10,} chars  ~{n // 4:>8,} tokens"
        if compacts:
            n2 = len(transcript(chat, m, 0, max_result_chars, after_compact=True))
            line += f"   (after-compact: {n2:,} chars ~{n2 // 4:,} tokens)"
        out.append(line)
    return "\n".join(out)


def only_match(matches: list[str], session_id: str) -> str | None:
    """The one file an id names, None for none; several print the ambiguity and exit 2."""
    if len(matches) > 1:
        print(f"Ambiguous id '{session_id}' — {len(matches)} matches:", file=sys.stderr)
        for m in matches:
            print(f"  {m}", file=sys.stderr)
        print("Pass the full UUID to disambiguate.", file=sys.stderr)
        sys.exit(2)
    return matches[0] if matches else None
