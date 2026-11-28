# Cursor macOS runs use a rented Mac with its own worker

Cursor's own machines run Ubuntu only. So `cursor.sh --platform macos` runs the agent as a My Machines agent on a Namespace Mac that `mac.sh` rents, with a Cursor worker started on it. `start` rents the Mac through `mac.sh rent`. `say` goes through `mac.sh renew`, which keeps the worker's name and ID, because Cursor sends an agent's later runs to the worker ID it first ran on.

The Mac lives for one run. handoff.sh's `watch`, or its `release`, gives it back through `mac.sh return`, and `poll` never touches it. A worker refuses a `grok_` key, so a Mac run needs a personal `crsr_` key. `--platform windows` stops, because Devin has Windows machines.
