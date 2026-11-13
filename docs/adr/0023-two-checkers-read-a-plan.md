---
status: amends ADR-0021
---

# Two checkers read a plan, each started by its own signs

Plan-up's plan check runs two Fable agents side by side. `plan-correctness-checker` looks for what would make the build fail or ship the wrong thing. `plan-design-checker` looks for a part the plan patches but should rebuild, an empty module, a seam with one adapter, logic in the wrong place, tests that reach inside a module, and parts the work does not need. The planner starts each one by its own signs, on a plan of size S or more: the correctness checker when a wrong plan would be costly to fix, the design checker when the plan adds or moves a part or touches one with signs of a wrong design. We considered one agent with both lists, which is cheaper, but the bug hunt crowds out the design read. We also considered one size gate for both, but it skips small plans that change the shape of the code.
