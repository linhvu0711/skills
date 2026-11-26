---
status: amends ADR-0030, amended by ADR-0042
---

# The gate sends a helper to its home first

ADR 0030 says a subagent tries its home models in order, and `shared/facts.md` § Skill agents tells the main agent how. Nothing checked it, and the main agent started helpers by name, which runs the backup: from 2026-11-20 to 2026-11-22, all 18 walker runs in T3 used Claude Sonnet, never Devin. So in T3 the subagent gate refuses the main agent's first start by name of a helper whose first home is not its own harness with the backup's model and effort. A second start by name of the same helper in the same chat goes through and runs on the backup, and the report line says why. This is the one case where the gate blocks the main agent.

We considered clearer words at each step that starts a helper, but `facts.md` already said it and every run skipped it. We considered a script that prints how to start each helper, but the main agent must still remember to run it. We considered letting the backup through only when the chat log shows a home refused, but each harness writes its log in its own format and Antigravity gives the hook no log path. We considered a pass word in the start, but the main agent can add it without trying a home.
