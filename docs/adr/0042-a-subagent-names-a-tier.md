---
status: supersedes ADR-0025, ADR-0028, ADR-0030; amends ADR-0020, ADR-0023, ADR-0040
---

# A subagent names a tier, and one table picks its models

Each subagent's file says only its tier, 1 to 4, and whether it is a checker. `shared/model-tiers.md` holds three tables. The first gives the model and effort each company runs at each tier. The second gives the try order: the companies a subagent tries, in order, set by its tier, its checker line, and the main agent's harness. The third says which companies are in use. The scripts join the tables, so a model swap or an order change is one cell.

We pick a tier from the hardest step of the job, by what each tier's models can do, and the user confirms the tier of each new subagent. A checker tries another company before the main agent's own, since a model rates its own family's work too well. At tier 2 every subagent tries Devin first. At tier 3 only checkers do. From Claude Code and Codex, the last try is always the main agent's own model, so a helper fails only when the main agent fails. Outside T3, that last try is the only one. Antigravity has no tier-1 model, so under an Antigravity main agent a tier-1 subagent runs only on Claude. In practice the main agent is Claude Code.

This drops the rule from ADR 0020 and ADR 0025 that a plan Fable wrote gets no design check. The design checker now tries Neon first, and the try order handles that bias the same way for every checker. The gate from ADR 0040 now sends a helper to the first company in its try order.

We considered keeping each agent's own model lists, with a check against the table. A file then reads alone, but a model swap touches every file. We also considered one try-order rule in code, but it needs special cases for tier 2 and tier 3.
