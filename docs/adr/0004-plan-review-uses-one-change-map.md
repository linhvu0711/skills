# Plan review uses one change map

A person who reviews a plan needs to see who owns what and what moves between parts. Which file imports which does not help them. So the plan page draws one diagram kind, the change map. A box in it is a part with a job, named in the project's own words, an arrow is what moves, and a store box lists the tables or keys that change. We first drew five large merged PRs from another repo as file-level diagrams, and they showed only imports, so the plan page has its own small renderer and does not use `create-diagram`.

## Considered options

- File-level component or dependency diagrams. Their boxes are files and their arrows are imports, which tell a reviewer nothing about jobs.
- A separate `create-diagram` page, linked from the plan. That is a second tab, and a notation the skill does not have.
- The change map plus ERD and deployment kinds. That is three notations to learn, and neither is needed: table changes go in the store box, and a release change is parts and flows too.
