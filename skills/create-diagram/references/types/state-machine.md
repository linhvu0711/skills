# State machine

Answers: what states one thing can be in, what moves it between them, and what can never happen. Order status, connection lifecycle, job status, UI modes, auth session.

## Facts to collect

- The thing: the entity or object whose state field this is. `path` to the enum or type that names the states.
- Every state value. Include ones only reachable by migration or admin action; mark them in `note`.
- Every transition: from, to, the event or call that causes it, the guard if any. `path` to the line that writes the new state.
- Initial state and terminal states.
- Side effects on transition that matter (send email, release stock): in the edge `note`.
- Writes that bypass the machine (a raw update elsewhere). Those go in `findings`.

## Draw it

| Thing | Data |
|---|---|
| State | `rounded`, label is the state value as the code spells it |
| Initial | `start` node with one edge into the initial state |
| Terminal | `end` node reached from terminal states, or mark terminal states with `tag: "final"` |
| Transition | edge, label `event [guard]`: `pay() [amount > 0]`, `timeout 30s` |
| Self transition | edge with `from === to` |
| Composite state | group `zone` around sub-states |

## Layout

Initial state at the left or top. Happy path along one row. Failure and cancel states below it. Terminal states at the far end. Backward transitions (retry, reopen) use the row above.

## Budget

6 to 14 states. More than that means two machines are tangled together; split by the field that owns them.

## Pitfalls

- The status enum drawn, but not every write site found. The transition list is what this diagram is for; a missing transition is the bug the reader was looking for.
- Guards written as prose. Copy the condition from the code.
