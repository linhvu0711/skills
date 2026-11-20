# Simplification lives in improve-codebase, and the skill files issues only

One skill scans for both deepenings and simplifications. Both read the same busy code and show in the same report, and a big simplification needs the same grill as a deepening. The skill was named improve-architecture; it is now improve-codebase, so the name covers both jobs. The grill takes every candidate, big ones first and then small ones in topic groups, and files issues. The skill changes no code, so plan-up plans every cut, with a lock test where no test covers the code, before it ships.

## Considered options

- A separate simplify skill. We rejected it because it would read the same code twice, copy the scan and the report, and split one find, such as a wrapper that only passes calls through, across two reports.
- The skill makes small cuts itself in one PR, as prune-comments does. We rejected it because a comment edit cannot change behavior, but a code cut can, so a cut waits for a plan with a lock test.
