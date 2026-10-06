# Docs ship with the code that makes them true

A grill no longer writes `CONTEXT.md` or an ADR while it talks, and no longer opens a docs PR before the work. The text it settles waits in the issue it files, under `## Docs to write`, and the PR whose code makes it true writes it. A doc that is true already, like "we will not build X", rides on the first code ticket; only a grill with no work after it opens a docs PR. We chose this because a docs PR before the code cost an extra PR each time, and a doc that lands before its code tells the next reader something the code does not do.

## Considered options

- A docs PR at the end of each grill (the old way): rejected for the extra PR and the docs that run ahead of the code.
- Keep the text only as a comment on the issue: rejected, because the next grill reads `docs/adr/` and open issues' bodies, not comments, and would suggest the rejected option again.

## Consequences

- While a decision waits in an open issue, `/grill`, `/improve-architecture`, and `/plan-up` read those issues as decided, not built.
- A seed is never closed for growing: it becomes the issue, the map, or the epic parent. A `/discover-path` map keeps all doc text in its own `## Docs to write` until `/to-epic` hands each entry to a sub-issue.
- A later decision edits waiting text in place. A superseded ADR is needed only for an ADR that shipped.
