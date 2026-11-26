---
status: superseded by ADR-0042
---

# A subagent's model depends on the main agent

In T3, each subagent runs on a home model picked for the main agent's harness. A checker runs on another company's model, because a model rates its own family's work too well: under a Claude main agent the logic reviewer runs on Gemini 4 Neon, and under Codex or Antigravity on Claude Opus. The walker and the scope and standards reviewers run on Devin's SWE-2, which is free. When a home model cannot run, the subagent runs on its backup model from the main agent's own harness, and the report says so. That backup fails only when the main agent fails, so there is no third step. Outside T3, every subagent runs on its backup model. Devin is never a main agent, so it gets no skills, rules, or gates.

We considered one home model per subagent whatever the main agent, which is simpler but lets Claude check a Claude main agent's work; stopping the skill when a model cannot run, which hides nothing but lets one Devin outage stop /review-pr; and Claude models for the checkers in plain Antigravity, which keeps the check cross-company but needs a second table.
