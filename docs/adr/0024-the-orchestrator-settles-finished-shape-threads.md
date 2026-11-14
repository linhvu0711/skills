---
status: amends ADR-0013
---

# The orchestrator settles a finished grill or triage thread

This amends ADR 0013. When a /grill or /triage thread of a Run has finished its turn, is not settled, and its issue moved to a new Stage, the orchestrator reads its last turn and settles it in T3, unless the turn still needs the user: a question, an error it did not get past, or work left undone. Then the thread stays open, and the orchestrator thread says why in one line. A thread that failed stays open the same way. In a Run, every seed and bug ended in a thread the user had to settle by hand, though its work was done and the next Stage had its own thread. The script lists the threads, and the agent judges and settles each, since the `t3` command has no settle and a problem needs reading, not a pattern. It settles a thread once and never a /ship or /ready-pr thread, whose PR the user still reviews. The rest of ADR 0013 holds: the orchestrator answers no question and retries nothing.
