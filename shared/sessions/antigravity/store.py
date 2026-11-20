"""Read Antigravity chats, as agy 1.5.12 stores them.

Each chat is one SQLite file, `<app data>/conversations/<id>.db`. Its steps
hold protobuf blobs with no schema shipped, so this module reads the wire
format by hand and knows the field paths:

- `steps.step_type` 14 is a user prompt: text at payload field 19 then 2,
  workspaces at 19 then 12, then that message's repeated field 12.
- 15 is an assistant step: its visible text at payload field 20 then 1, absent
  when the step holds only thinking or tool calls. Other types are skipped.
- `steps.metadata` fields 1, 6, 7, 8, 32 are Timestamps {1: seconds, 2: nanos}.

`read`, `folders`, and `locate` are the whole interface; the finder and the
extractor next to this file both use it.
"""

from __future__ import annotations

import dataclasses
import os
import sqlite3
import urllib.parse


class Unreadable(Exception):
    """A file in a chats folder that is not an Antigravity chat."""


@dataclasses.dataclass
class Chat:
    id: str
    path: str
    cwd: str
    title: str
    turns: list[tuple[str, str]]  # (role, text), role "user" or "assistant", in step order
    first: float  # epoch seconds of the first and last activity
    last: float
    size: int


def _varint(b: bytes, i: int) -> tuple[int, int]:
    n = shift = 0
    while True:
        if i >= len(b) or shift > 63:
            raise ValueError
        c = b[i]; i += 1
        n |= (c & 0x7F) << shift
        if not c & 0x80:
            return n, i
        shift += 7


def _message(b: bytes | None) -> dict[int, list]:
    """Every value of each field of one protobuf message."""
    out: dict[int, list] = {}
    i = 0
    while b and i < len(b):
        key, i = _varint(b, i)
        num, kind = key >> 3, key & 7
        if num == 0:
            raise ValueError
        if kind == 0:
            value, i = _varint(b, i)
        elif kind in (1, 5):
            size = 8 if kind == 1 else 4
            value, i = b[i:i + size], i + size
        elif kind == 2:
            size, i = _varint(b, i)
            value, i = b[i:i + size], i + size
        else:
            raise ValueError
        if i > len(b):
            raise ValueError
        out.setdefault(num, []).append(value)
    return out


def _first(m: dict[int, list], num: int, default=b""):
    return m.get(num, [default])[0]


def _seconds(blob: bytes) -> float:
    t = _message(blob)
    return _first(t, 1, 0) + _first(t, 2, 0) / 1e9


def _prompt(text: str) -> str:
    """The user's own words: T3 wraps a chat's first prompt in its instructions."""
    start, end = "<user_request>\n", "\n</user_request>"
    if start in text and end in text:
        return text.split(start, 1)[1].split(end, 1)[0]
    return text


def _cwd(uris: list[str]) -> str:
    """The first workspace, leaving out the attachments folder T3 adds to each chat."""
    for uri in uris:
        path = urllib.parse.unquote(uri.removeprefix("file://"))
        if not path.rstrip("/").endswith("/.t3/userdata/attachments"):
            return path
    return ""


def _title(path: str, cid: str) -> str:
    summaries = os.path.join(os.path.dirname(path), "..", "conversation_summaries.db")
    if not os.path.isfile(summaries):
        return ""
    try:
        db = sqlite3.connect(f"file:{summaries}?mode=ro", uri=True)
        row = db.execute("select title from conversation_summaries where conversation_id = ?", (cid,)).fetchone()
    except sqlite3.Error:
        return ""
    return (row[0] or "") if row else ""


def read(path: str) -> Chat | None:
    """The chat in one file, or None for a chat with no steps."""
    try:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        cid = db.execute("select cascade_id from trajectory_meta").fetchone()[0]
        steps = db.execute("select step_type, metadata, step_payload from steps order by idx").fetchall()
    except (sqlite3.Error, TypeError):
        raise Unreadable("not an Antigravity chat")
    if not steps:
        return None
    turns, uris, starts, times = [], [], [], []
    try:
        for kind, meta, payload in steps:
            m = _message(meta)
            starts += [_seconds(v) for v in m.get(1, [])]
            times += [_seconds(v) for f in (1, 6, 7, 8, 32) for v in m.get(f, [])]
            p = _message(payload)
            if kind == 14:
                ask = _message(_first(p, 19))
                turns.append(("user", _prompt(_first(ask, 2).decode("utf-8", "replace"))))
                for spaces in ask.get(12, []):
                    uris += [u.decode("utf-8", "replace") for u in _message(spaces).get(12, [])]
            elif kind == 15:
                text = _first(_message(_first(p, 20)), 1)
                if text:
                    turns.append(("assistant", text.decode("utf-8", "replace")))
    except (ValueError, AttributeError, TypeError):
        raise Unreadable("not an Antigravity chat")
    first = min(starts or times or [os.path.getmtime(path)])
    last = max(times or [first])
    return Chat(id=cid, path=path, cwd=_cwd(uris), title=_title(path, cid), turns=turns,
                first=first, last=last, size=os.path.getsize(path))


def folders() -> list[str]:
    """Where agy keeps chats: the terminal's app data."""
    return [os.path.expanduser("~/.gemini/antigravity-cli/conversations")]


def locate(arg: str) -> str | None:
    """The chat file a path, an id, or an id prefix names."""
    if os.path.isfile(arg):
        return arg
    for folder in folders():
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            continue
        for name in names:
            if name.endswith(".db") and name.startswith(arg):
                return os.path.join(folder, name)
    return None
