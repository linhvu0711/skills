"""Open a Codex rollout as text, plain or compressed.

Codex keeps older rollouts as ``rollout-*.jsonl.zst``. Python reads zstd
itself from 3.14 (``compression.zstd``); an older Python reads it through the
``zstd`` command. With neither, opening a compressed rollout raises NoZstd, so
a caller can list the file as not read instead of skipping it silently.
"""

from __future__ import annotations

import contextlib
import shutil
import subprocess

SUFFIXES = (".jsonl", ".jsonl.zst")
NO_ZSTD = "needs Python 3.14+ or zstd"


class NoZstd(Exception):
    pass


def is_rollout_name(name: str) -> bool:
    return name.startswith("rollout-") and name.endswith(SUFFIXES)


@contextlib.contextmanager
def open_rollout(path):
    path = str(path)
    if not path.endswith(".zst"):
        with open(path, "r", encoding="utf-8", errors="replace") as h:
            yield h
        return
    try:
        from compression import zstd
    except ImportError:
        zstd = None
    if zstd is not None:
        with zstd.open(path, "rt", encoding="utf-8", errors="replace") as h:
            yield h
        return
    if not shutil.which("zstd"):
        raise NoZstd(NO_ZSTD)
    proc = subprocess.Popen(["zstd", "-dcq", path], stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
    try:
        yield proc.stdout
    finally:
        proc.stdout.close()
        proc.kill()
        proc.wait()
