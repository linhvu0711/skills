"""Where Codex keeps its rollouts, and how to open one, plain or compressed.

Codex files a live rollout under ``~/.codex/sessions/YYYY/MM/DD/`` and moves an
archived one, under the same name, to ``~/.codex/archived_sessions/``.

Codex keeps older rollouts as ``rollout-*.jsonl.zst``. Python reads zstd
itself from 3.14 (``compression.zstd``); an older Python reads it through the
``zstd`` command. With neither, opening a compressed rollout raises NoZstd, an
OSError. A compressed rollout that is cut off or corrupt raises OSError with
the reader's message, from ``compression.zstd`` at any read, or from the zstd
command on a file read to its end, so a caller can list the file as not read
instead of skipping it silently.
"""

from __future__ import annotations

import contextlib
import os
import shutil
import subprocess

SUFFIXES = (".jsonl", ".jsonl.zst")
NO_ZSTD = "needs Python 3.14+ or zstd"


def data_folders() -> list[str]:
    """The folders Codex keeps rollouts in, read at call time so HOME counts."""
    codex = os.path.join(os.path.expanduser("~"), ".codex")
    return [os.path.join(codex, "sessions"), os.path.join(codex, "archived_sessions")]


class NoZstd(OSError):
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
        try:
            with zstd.open(path, "rt", encoding="utf-8", errors="replace") as h:
                yield h
        except (EOFError, zstd.ZstdError) as e:
            raise OSError(str(e)) from e
        return
    if not shutil.which("zstd"):
        raise NoZstd(NO_ZSTD)
    proc = subprocess.Popen(["zstd", "-dcq", path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    try:
        yield proc.stdout
        # A reader that stopped early, as at line 1, leaves zstd running and its
        # code says nothing; only a read to the end can see that zstd failed.
        if not proc.stdout.read(1) and proc.wait() != 0:
            err = proc.stderr.read().strip().splitlines()
            raise OSError(err[-1] if err else f"zstd exited {proc.returncode}")
    finally:
        proc.stdout.close()
        proc.stderr.close()
        proc.kill()
        proc.wait()
