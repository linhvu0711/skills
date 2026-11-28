# A thread quiet for 10 minutes reads as stopped

T3 shows a `/ship` thread that paused between turns as `completed`, the same as one that stopped, so the orchestrator cannot ask T3 which one it is. A `/ship` thread ends its turn each time it waits for its helpers, so a short pause is not a stop.

The orchestrator reads a thread as stopped only when T3 gave it no update for 10 minutes, or gave no update time at all. That is two watcher checks at the 5-minute default (#279). The 10 minutes is a guess. It stays until T3 shows a paused state of its own.
