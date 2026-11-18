#!/usr/bin/env python3
"""The Claude Code or Codex session behind each T3 Code thread.

T3 Code runs each thread on a provider and logs its events to
~/.t3/userdata/logs/provider/events.<thread id>.log, one
`[<time>] <tag>: <json>` line per event. The provider's own session ID sits
in those lines as "sessionId". So a thread's transcript is the Claude or
Codex session of that ID, read through that harness's adapter: T3 has no
adapter of its own.

    thread_session.py <thread id>...

Prints one JSON line per session, {"thread", "harness", "session"}, in the
order the log names them, or {"thread", "error": "not found"} when the
thread has no log or the log names no session. Exit 0.
"""

import json
import os
import re
import sys

PROVIDERS = {"claudeAgent": "claude", "codex": "codex"}
PROVIDER = re.compile(r'"provider":"(claudeAgent|codex)"')
SESSION = re.compile(r'"sessionId":"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"')


def sessions(thread):
    path = os.path.expanduser(f"~/.t3/userdata/logs/provider/events.{thread}.log")
    harness, found = None, []
    try:
        with open(path, encoding="utf-8", errors="replace") as h:
            for line in h:
                if harness is None and (m := PROVIDER.search(line)):
                    harness = PROVIDERS[m.group(1)]
                for sid in SESSION.findall(line):
                    if sid not in found:
                        found.append(sid)
    except OSError:
        return [{"thread": thread, "error": "not found"}]
    if not harness or not found:
        return [{"thread": thread, "error": "not found"}]
    return [{"thread": thread, "harness": harness, "session": s} for s in found]


def main():
    for thread in sys.argv[1:]:
        for row in sessions(thread):
            print(json.dumps(row))


if __name__ == "__main__":
    main()
