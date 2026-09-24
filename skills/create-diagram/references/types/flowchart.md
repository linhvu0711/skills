# Flowchart

Answers: what does this logic do, step by step, with its branches and loops. One process, one owner. When more than one file or service takes part, draw a sequence instead.

## Facts to collect

- The entry point: function, handler, command. `path` to its first line.
- Each step that changes state or calls out. Skip pure plumbing (logging, mapping).
- Each branch: the condition as code reads it, and both outcomes.
- Each loop: what it iterates and what ends it.
- Each exit: return value, thrown error, redirect.
- Early returns and error paths. These are what the reader cannot see in prose.

## Draw it

| Thing | Node | Notes |
|---|---|---|
| Entry / exit | `start` / `end` | one start; one end per distinct outcome, labelled with the outcome |
| Step | `box` | verb first: "Load user", "Write audit row" |
| Branch | `decision` | the question as the code asks it: "token expired?" |
| Call to another unit | `box` with `tag: "call"` and `path` | keeps the reader able to jump |
| Loop | edge back to an earlier node, label "next item" | |

Edges: label the two edges out of a decision `yes` / `no` (or the enum values). Every other edge has no label unless data passes along it.

## Layout

Top to bottom. One column for the happy path, `x: 1`. Failure exits on `x: 2`, alternate branches on `x: 0`. Decision outcomes go down (main) and sideways (other). Loop-back edges return on the outer column.

## Budget

6 to 14 nodes. Past that, the function is doing two jobs; draw the outer one and make the inner one its own diagram.

## Pitfalls

- A decision with one outgoing edge is a step, not a decision.
- Draw the decisions a product person would recognize, not the language's control flow (every `if`).
