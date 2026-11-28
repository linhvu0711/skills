"""gh.py: the one way a Python script of the shared core or a skill runs gh.

Load it by path, since `python3 -I` leaves the script's folder off sys.path,
from the real file, so a linked skill finds the shared core:

    spec = importlib.util.spec_from_file_location("gh", <path to gh.py>)
    GH = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(GH)

gh prints hints on stderr beside a good answer, so stderr stays out of the
answer. On a failure the error is gh's last line; the first is often a hint,
such as `A new release of gh is available`.

run(*args, cwd=None): gh's stdout. A failure raises GhError, whose text is
the last non-empty line of gh's stderr, `gh exited <n>` when it printed none,
`gh: command not found`, or `gh: could not start: <why>`. GhError.status is
the HTTP status GitHub gave, read from the error body gh api prints, or None
when gh printed no body (a gh command that is not gh api, a GraphQL error).

stop(what, *args): run's stdout, or `stop: gh could not <what>:
<line>` on stderr and exit 1.
"""

import json
import subprocess
import sys


class GhError(Exception):
    """gh failed; the text is its last error line."""

    def __init__(self, line, status=None):
        super().__init__(line)
        self.status = status


def api_status(stdout):
    # Only gh api prints a JSON error body; any other gh command has no status.
    try:
        body = json.loads(stdout)
    except ValueError:
        return None
    status = body.get("status") if isinstance(body, dict) else None
    return int(status) if status else None


def run(*args, cwd=None):
    try:
        done = subprocess.run(["gh", *args], cwd=cwd, capture_output=True, text=True)
    except FileNotFoundError:
        raise GhError("gh: command not found")
    except OSError as e:
        raise GhError(f"gh: could not start: {e.strerror}")
    if done.returncode != 0:
        lines = [l for l in done.stderr.splitlines() if l.strip()]
        raise GhError(lines[-1] if lines else f"gh exited {done.returncode}", api_status(done.stdout))
    return done.stdout


def stop(what, *args):
    try:
        return run(*args)
    except GhError as e:
        sys.exit(f"stop: gh could not {what}: {e}")
