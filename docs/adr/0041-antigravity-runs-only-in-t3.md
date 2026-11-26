---
status: supersedes ADR-0026 (an Antigravity helper takes the main agent's model)
---

# Antigravity runs only in T3

The owner runs Antigravity only inside T3 Code, never on its own. So the repo stops installing skill agents and the subagent gate into Antigravity. `link.sh` writes no Antigravity agent file, no "skills" plugin manifest, and no gate entry in that plugin's hooks, and it removes the copies it wrote before. It still links each skill into Antigravity's skills folder, and the plugins folder into each T3 Antigravity folder, since Antigravity in T3 reads both. ADR 0026 gave each Antigravity agent file the backup `inherit`, because such a file cannot name a model. With no Antigravity agent files, that rule has nothing left to apply to. In T3, T3 starts a helper on Antigravity with an exact model and thought level. We considered keeping the files for a later run of plain `agy`. We dropped it because every file is one more thing the checks must keep correct, for a setup nobody runs.
