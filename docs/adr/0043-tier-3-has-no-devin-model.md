---
status: amends ADR-0042
---

# Tier 3 has no Devin model

Tier-3 checkers (gap-checker, plan-correctness-checker, logic-reviewer) no longer try SWE-2.1 xhigh in Devin first. It was too slow for a checker. Tier 3 now has no Devin model, so each checker starts on its next try: Gemini 4 Neon from Claude Code, Claude Opus from Codex or Antigravity. Tier 2 still tries SWE-2.1 high in Devin first.

The cost is a same-family check in one case. T3 runs a try in Antigravity only in `full-access` mode, so in `auto` mode a tier-3 checker under a Claude Code main agent runs on Claude Opus and checks Claude's own work. We accept that. A slow checker makes every plan and every review wait, and the same-family check happens only in `auto` mode.

We considered keeping SWE-2.1 xhigh as the second try, after Gemini and before Claude. It would keep an outside checker in `auto` mode, but every one of those runs would still wait on the slow model.
