# A guessed step waits for the user's yes

When a label, an open PR, or the user's own words pick an issue's step, the thread starts. An issue with none of these gets a Proposal, and no thread starts until the user says yes, in run-in-t3 and the orchestrator alike. The skill writes the yes to the issue as a label when one fits, so no skill guesses that issue again.

We considered starting at once when the guess is cheap (`/triage`, `/grill`) and asking only for `/ship`, but "sure" is a judgment that would differ between issues that look alike. We also considered acting in run-in-t3, where the user is watching, and asking in the orchestrator, but that keeps the two skills different.
