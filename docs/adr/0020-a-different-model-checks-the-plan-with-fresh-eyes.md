---
status: amended by ADR-0021
---

# A different model checks the plan, with fresh eyes

Before the user sees a plan that Opus wrote, plan-up can have the `plan-checker` agent, on Fable, check it: always at size L or XL, at M when the plan looks risky. The checker reads only the issue, the plan, and a clean copy of the code, never the planner's notes or the chat, so it starts from the code and not from the planner's view, and a mistake the planner made is not handed to it as a fact. A plan Fable wrote gets no Fable check, since one model mostly agrees with itself. The check lives in plan-up, not in ship, so a plan made without ship is checked too. We considered passing the planner's notes, which is faster, and checking every plan, which costs more than small plans repay, and chose fresh eyes on the plans big enough to hurt.
