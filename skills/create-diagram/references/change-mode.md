# Planned mode

Planned mode draws the code as it is and overlays what the plan does to it. The reader flips between three views on one page: **Current** hides added things, **Planned** hides removed things, **Diff** shows all with color.

## Mark the plan

1. Draw the current diagram first, from code facts. This is the base, and it must stand alone in the Current view.
2. Read the plan: the chat, a plan file, an issue, a PR description. For each statement that touches the diagram, mark one of:
   - `change: "add"` on a new node, edge, group, or step.
   - `change: "remove"` on one that goes away.
   - `change: "modify"` on one whose role, contract, or path changes. Put what changes in `note`.
3. An added edge needs both ends visible in the Planned view. An edge to a removed node is itself `remove`, or it is wrong.
4. A move is a remove plus an add, unless the thing keeps its identity and only its home changes: then it is `modify` with the new home in `note`.

## Keep it honest

- Facts about the current code come from files. Facts about the plan come from the plan text. Keep the panel `note` explicit about which is which: "Plan: moves token check into middleware."
- When the plan is silent on something the diagram needs (who calls the new service, what happens to the old table), do not invent it. Put the gap in `findings`: "Plan does not say who deletes rows from `sessions` after the move."
- When the plan contradicts the code (renames a module that does not exist, calls an endpoint that is gone), that goes in `findings` too. This is the most useful line on the page.

## When the overlay stops working

If the plan changes more than half the nodes, the Diff view becomes noise. Then publish two pages: the current diagram, and the planned diagram as its own base with no change marks. Say so in the reply and link both.

## Default view

Leave `mode` unset for the Diff view when changes exist. Set `mode: "planned"` when the user asked "what will it look like" and the current state is context, not the point.
