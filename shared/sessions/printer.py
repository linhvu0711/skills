"""Print one past chat, whatever harness wrote it.

Each harness's extract_session.py reads its own log into a Chat: a plain list
of Messages, the chat's facts, and the Words the harness calls its parts by.
This module prints that Chat as a transcript in one of two modes, so every
harness prints the same layout.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from datetime import datetime

SHOWN = {
    "summary": {"user", "assistant", "note", "compact"},
    "balanced": {"user", "assistant", "note", "compact", "call", "result"},
}
COMPACT_LABEL = "## 📦 Compaction summary (auto-generated recap of everything above it)"


@dataclass(frozen=True)
class Words:
    """What a harness calls the parts of its chat."""

    transcript: str  # heading of a transcript
    assistant: str  # label of a reply
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
    title: str | None = None
    span: tuple[str, str] | None = None  # first and last raw timestamps
    reasoning: int | None = None  # set: encrypted reasoning blocks, in place of thinking


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


def _count(chat: Chat, kind: str) -> int:
    return sum(1 for m in chat.messages if m.kind == kind)


def _compactions(n: int) -> str:
    return f"{n} compaction summar{'y' if n == 1 else 'ies'}"


def _blocks(chat: Chat, mode: str, after_compact: bool) -> list[Message]:
    blocks = [m for m in chat.messages if m.kind in SHOWN[mode]]
    if after_compact:
        idxs = [i for i, m in enumerate(blocks) if m.kind == "compact"]
        if idxs:
            blocks = blocks[idxs[-1]:]
    return blocks


def _lines(chat: Chat, blocks: list[Message], max_result_chars: int) -> list[str]:
    label = {"user": "## 🧑 User", "assistant": f"## 🤖 {chat.words.assistant}", "compact": COMPACT_LABEL}
    out = []
    for m in blocks:
        if m.kind == "call":
            out.append(f"→ {m.text}")
        elif m.kind == "result":
            text = _cut(m.text, max_result_chars)
            out.append(f"[{'tool error' if m.error else 'tool result'}] {text.strip()}")
        elif m.kind == "note":
            out.append(m.text)
        else:
            out.append(label[m.kind])
            out.append(m.text)
        out.append("")
    return out


def transcript(chat: Chat, mode: str, max_result_chars: int = 500, after_compact: bool = False) -> str:
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
    out.append(f"**Render mode:** {mode}" + (" · after last compaction" if after_compact else ""))
    out.append("\n---\n")
    out += _lines(chat, _blocks(chat, mode, after_compact), max_result_chars)
    return "\n".join(out)


def only_match(matches: list[str], session_id: str) -> str | None:
    """The one file an id names, None for none; several stop with one line that lists them."""
    if len(matches) > 1:
        sys.exit(f"stop: id {session_id!r} matches {len(matches)} sessions: {', '.join(matches)}; pass the full UUID")
    return matches[0] if matches else None
