# Data flow

Answers: where data comes from, what transforms it, where it rests, and where it goes. Pipelines, ETL, event streams, analytics, anything where the data is the story and the order of calls is not.

## Facts to collect

- External entities: sources and sinks outside the scope (users, third-party APIs, other systems).
- Processes: each unit that transforms data. Name by what it does to the data: "Normalize events", "Score risk". `path` to it.
- Stores: databases, caches, buckets, topics where data rests.
- Flows: each movement of data, labelled with the data name, not the mechanism: "raw events", "user profile", "daily totals".
- Level: a context (level 0) diagram is the whole system as one process. Level 1 opens it up. Pick one level per page.

## Draw it

| Thing | Node |
|---|---|
| External entity | `external` |
| Process | `rounded` |
| Store | `store` for databases and buckets, `queue` for topics and queues |
| Flow | edge, label is the data; `dashed` for control or trigger signals |
| Trust or system boundary | group `boundary` |

## Layout

Sources on the left, sinks on the right. Stores on a row below the processes they serve. Each flow moves rightward; a backward flow is a signal to reconsider the level.

## Budget

6 to 16 nodes. Every process must have at least one flow in and one out; a process with only inputs is a store or a sink in disguise.

## Pitfalls

- Labelling flows with verbs. Verbs belong to sequence diagrams; here the label is a noun.
- Mixing levels: one process opened up beside others left closed. Open one, or open none.
