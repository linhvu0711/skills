# Sequence

Answers: what happens, in order, when one thing is triggered, across several parts. Requests, jobs, event handlers, CLI commands. The most useful diagram for "how does X work" when X crosses files.

## Facts to collect

- The trigger: who or what starts it. First participant.
- Participants: each module, service, store, or external that takes part. `path` to the file that owns it.
- Messages in order: caller, callee, what is sent (method name, HTTP verb and route, event name). `path` to the call site.
- Which messages wait (`sync`) and which do not (`async`: fire and forget, publish, enqueue).
- Returns that carry something the next step needs (`return`), and errors that end the flow early.
- Loops and alternatives: what repeats, what branches, on what condition.

## Draw it

Use `type: "sequence"`.

| Thing | Data |
|---|---|
| Trigger | first participant, `kind: "actor"` for a person, `box` for a scheduler or webhook |
| Store | `kind: "store"` |
| Call | step `kind: "sync"`, label as the code reads: `getUser(id)`, `POST /orders` |
| Publish / enqueue | step `kind: "async"` |
| Response that matters | step `kind: "return"`, label with what comes back: `user or null` |
| Repeat | frame `loop each item` over the step range |
| Branch | frame `alt token valid` over the happy steps; put the other branch in `note` or a second frame `else` |
| Self call worth seeing | step with `from === to` |

## Layout

Order participants by first use, left to right. That alone removes most crossing lines. Keep a return only when its content changes the next step; the reader assumes calls return.

## Budget

3 to 7 participants, 6 to 18 steps. Longer flows split at a natural boundary (request accepted, then background work) into two pages.

## Pitfalls

- Every getter as a step. Show the calls that cross a boundary or change state.
- Missing the error path. One `alt` frame with the failing branch is often the whole reason to draw this.
