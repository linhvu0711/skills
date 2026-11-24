# Three skills keep a codebase clean, sorted by the fix

An agent copies the code it reads, so a bad example spreads. Four skills each looked for some kinds of bad example, and no skill looked for two kinds: a hack with no comment, and one job done two ways. We sort a find by the fix it needs. `prune-codebase` finds code that must go: unused code, copies, hacks, and bad comments. `audit-coding-standards` finds code that must be written one way. `improve-architecture` finds code that needs a new design. A skill that finds a problem handles it, and an open ticket marks the find as known for the next skill. This replaces ADR 0026. Simplification leaves `improve-codebase`, and the skill is named `improve-architecture` again.

## Considered options

- One skill for all kinds. We rejected it because one scan and one report for every kind found less of each kind.
- A list in each report of finds that belong to another skill. We rejected it because the user would have to start a second skill to act on a find that is already in front of them.
- Twisted logic, and a package used for one small thing, as kinds of clean-up. We left them out because both need much judgment and gave rows the user turned down.
