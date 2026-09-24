# Catalog

Pick the type by the question, not by the artifact the user named. "Draw the architecture" is a question in disguise; find it first.

## Question to type

| The user wants to know | Type | Card |
|---|---|---|
| Who uses the system and for what | Use case | `types/use-case.md` |
| What the system is, and what sits around it | C4 context | `types/c4.md` |
| What runs inside the system, and how the parts talk | C4 container, or Component | `types/c4.md`, `types/component.md` |
| What pieces make up a module and what they need from each other | Component | `types/component.md` |
| Which modules import which; what breaks if I touch X | Dependency graph | `types/dependency-graph.md` |
| How the UI is built; where state lives; which component owns what | UI component tree | `types/component-tree.md` |
| What classes or types exist and how they relate | Class | `types/class.md` |
| What the data model is; tables, keys, cardinality | ERD | `types/erd.md` |
| Where data goes; what reads, transforms, and stores it | Data flow | `types/data-flow.md` |
| What happens step by step for one request or action, across parts | Sequence | `types/sequence.md` |
| What the logic does; branches and loops in one process | Flowchart | `types/flowchart.md` |
| A multi-step process with parallel work or several owners | Activity | `types/activity.md` |
| What states a thing can be in and what moves it | State machine | `types/state-machine.md` |
| Where things run; hosts, containers, networks, what is deployed where | Deployment | `types/deployment.md` |

Ties: prefer the type whose nodes are things the user can open in the editor. A sequence beats a flowchart when more than one file is involved. A component diagram beats C4 when the scope is one repo.

Two types are right when the question has a structure half and a behavior half ("how is auth built and what happens on login"). Draw structure first. Never three.

## Node budget

| Type | Nodes | Edges |
|---|---|---|
| Use case, C4 context, state machine, flowchart | 6 to 14 | 20 |
| Sequence | 3 to 7 participants, 6 to 18 steps | |
| Class, ERD | 4 to 12 tables | 20 |
| Component, C4 container, deployment, data flow, activity | 6 to 16 | 24 |
| Dependency graph, component tree | 8 to 24 | 40 |

Over budget means the scope is too wide, not the page. Cut by one of these, in order: drop nodes with one edge that do not answer the question; collapse a cluster into one group-sized node; split into two diagrams (overview plus one zoomed in) and publish both.
