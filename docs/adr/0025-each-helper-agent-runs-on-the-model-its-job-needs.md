---
status: amends ADR-0020, ADR-0023
---

# Each helper agent runs on the model its job needs

A skill agent's file names the model its job needs. Sonnet takes a job with set steps and a clear goal: the walker and the scope and standards reviewers. Opus takes a job that finds a cause or checks a claim where the facts are not clear yet: the logic reviewer, the CI helper, the finding judge, and the plan correctness checker. Fable costs the most and has the most taste, so it takes design work and no digging: the plan design checker and the interface designer. This amends ADR 0023: the correctness checker moves from Fable to Opus, since it checks facts against the code and judges no design. It amends ADR 0020 too: the rule that a plan Fable wrote gets no Fable check now holds for the design checker alone, and the Opus correctness checker reads plans that Opus wrote, since it gets only the issue, the plan, and the code, and the code settles each fact it checks. The CI helper and the finding judge run at medium effort, since each gets one narrow piece and a later step catches a wrong answer. We considered keeping them on Sonnet, which is cheaper, but a wrong cause or a wrong verdict sends the next step the wrong way.
