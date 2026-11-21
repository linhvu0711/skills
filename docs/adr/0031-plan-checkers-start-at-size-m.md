---
status: amends ADR-0023
---

# Plan checkers start at size M

Plan-up starts its two plan checkers only on a plan of size M or more. XS and S plans skip both, and the plan's summary says so, as `Plan check: skipped · size S`. On an M plan or bigger, each checker still starts on its own signs, as ADR 0023 says. S plans are small and follow paths the repo already has, so a second model's read costs more than it finds. We considered keeping the floor at S, as ADR 0023 chose, which also reads the few S plans that change the shape of the code.
