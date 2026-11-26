---
status: superseded by ADR-0042
---

# A subagent tries its home models in order

A subagent's file can list more than one home model for a main harness, and T3 tries them from left to right before the backup. Under a Claude main agent, the logic reviewer and the two plan checkers list Gemini 4 Neon in Antigravity, then the same model in Devin at the same effort, then Claude Opus as backup. Antigravity runs a child only when the main agent is in full-access mode. Devin runs commands under auto with no asks. So the Devin step keeps the check on another company's model when Antigravity cannot run. This replaces ADR 0028's "no third step". The report names where a subagent ran each time it did not run on its first home, and why each earlier home was skipped.

We considered one shared rule that sends any Antigravity home to Devin. It needs no change to the agent files, but it must match Devin's model name (`gemini-4-neon-high`) to Antigravity's (`gemini-4-neon`) at run time.
