# Domain modeling

Build and sharpen the project's domain model as you design, and write it down the moment it settles.

## Files

The glossary is `CONTEXT.md`. Decisions are ADRs under `docs/adr/`. [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md) gives the glossary format and the single- vs multi-context layout. [ADR-FORMAT.md](./ADR-FORMAT.md) gives the ADR format and the three conditions for offering one. Create a file or folder the first time you have something to write into it.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out at once. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account'. Do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When you discuss domain relationships, stress-test them with specific scenarios. Invent cases that probe the edges and force the user to be precise about where one concept ends and the next begins.

### Cross-reference with the source

When the user states how something works, check whether the code agrees, or the research note when the fact comes from outside the repo. If you find a contradiction, surface it. "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update CONTEXT.md inline

Update `CONTEXT.md` the moment a term is resolved. It holds terms only; implementation detail lives in code and ADRs.

The glossary work is done when every term the session used is in `CONTEXT.md` or was judged a general programming concept.

### Offer ADRs

Offer an ADR only when all three conditions in [ADR-FORMAT.md](./ADR-FORMAT.md) hold. When the decision rests on a researched fact, the ADR cites the primary source, per `research.md` § Using an existing note.
