---
status: amends ADR-0013
---

# The orchestrator closes a done epic

This amends ADR 0013. When a Run is done, the orchestrator closes each epic of the Run that is still open: the epic named in the set, and each epic that joined as a sub-issue. The done rule already waits for every sub-issue of an epic to close, so the epic is the only issue left open, and the user closed each one by hand. It closes no epic outside the Run, such as the parent of a ticket the user named, since the Run never read it. The close runs once, in the Done steps, as its own command, never in a check: the watcher runs checks with no chat turn. The rest of ADR 0013 holds: the orchestrator comments, labels, and merges nothing.
