"""Read a chat log: its JSON lines, and the text of one message.

Claude Code and Codex both keep a chat as JSON lines, and both put a
message's text in a string or in a list of typed blocks. The finders and the
extractors under sessions/ read them through these two helpers.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Iterator

TEXT = ("text", "input_text", "output_text")
IMAGE = ("image", "input_image", "output_image")


def rows(lines: Iterable[str]) -> Iterator[object]:
    """Each line's JSON value; a blank line or one that is not JSON is skipped."""
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except ValueError:
            continue


def text_of(content, image: str | None = None) -> str:
    """A message's text: a string as it is, or a block list's text joined by
    newlines, with `image` standing for each image block when it is given."""
    if isinstance(content, str):
        return content
    if content is None:
        return ""
    if not isinstance(content, list):
        return str(content)
    parts = []
    for b in content:
        if isinstance(b, str):
            parts.append(b)
        elif isinstance(b, dict):
            if b.get("type") in TEXT:
                parts.append(b.get("text", ""))
            elif image and b.get("type") in IMAGE:
                parts.append(image)
    return "\n".join(p for p in parts if p)
