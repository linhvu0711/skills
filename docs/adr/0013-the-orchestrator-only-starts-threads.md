---
status: amended by ADR-0015
---

# The orchestrator only starts threads

The orchestrator starts one T3 thread for each issue at each Stage and does nothing more with it. It does not retry, fix, message, or answer that thread. The user handles every thread. Most skills ask the user questions along the way. An orchestrator that drove those threads would answer for the user or stall on the questions, and it would act in threads the user is working in. We designed retries after a crash, and re-readying a PR that broke after another PR merged, then dropped both for this reason. A thread that ends with no Stage change stays as it is until the user says `restart #n` in the orchestrator thread. When the run is done, it starts one more thread, `/retro run <run folder>`, and leaves it to the user like the others.
