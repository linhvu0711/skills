# A clean-codebase run changes no code and makes no commit

A skill on the run that finds code to remove does not delete it. A cut can change behavior, so it waits for a plan with a test that fails when the behavior changes, and the skill files a ticket. A run writes only what cannot change behavior: a rule in the Standard, a lint setting that no code breaks today, a comment edit, and an ADR that is true already. It leaves these files uncommitted, and the user ships them with the PR skill. `prune-comments` opened its own PR. That ends, so every skill on the run finishes the same way.
