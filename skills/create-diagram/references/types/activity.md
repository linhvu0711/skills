# Activity

Answers: how a multi-step process runs, who or what does each step, and where work happens in parallel. Business processes, pipelines, CI, approval flows, sagas.

## Facts to collect

- Owners: each lane is one role, service, or system that performs steps. Two to five lanes.
- Steps in order, with the lane that does them. `path` to the handler or job.
- Forks and joins: where work splits into parallel branches and where it waits for all of them.
- Decisions with their conditions.
- Start and each end.
- Hand-offs: the moment work crosses a lane. These are the interesting edges.

## Draw it

| Thing | Node | Notes |
|---|---|---|
| Lane | group `kind: "lane"` per owner, members are that owner's steps | lanes are columns: give each lane one `x` |
| Step | `rounded` | verb first |
| Decision | `decision` | edges out labelled with outcomes |
| Fork / join | `box` with `h: 8`, `w: 120`, empty label, `tag` omitted | a thin bar |
| Start / end | `start` / `end` | |
| Object passed between lanes | `file` node, dashed edges in and out | only when the payload is the point |

Edges: plain arrows in step order. Label a hand-off with what crosses: "approval request", "built image".

## Layout

Lanes as columns (`x: 0, 1, 2 ...`), time runs top to bottom (`y` increases). A step sits in the column of its owner. Parallel branches share the same `y` range in different columns.

## Budget

6 to 16 steps, 2 to 5 lanes.

## Pitfalls

- Everything in one lane means this is a flowchart; switch types.
- A lane with one step is usually an external system; make it an `external` node in a neighbor lane instead.
