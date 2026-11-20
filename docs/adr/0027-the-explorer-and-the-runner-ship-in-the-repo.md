---
status: amends ADR-0017
---

# The explorer and the runner ship in the repo

The repo ships the explorer and the runner as subagent files, with the same names in every harness and a model for each harness, and `link.sh` installs them. ADR 0017 kept them out of the repo because `~/.claude/delegation` wrote those files and could switch them to another backend. With a model for each harness, and T3 able to start any model, that switch has no job left, so the delegation tool is retired. Skills still ask for these jobs in plain words, as ADR 0017 says.
