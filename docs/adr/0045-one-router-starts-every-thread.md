# One Router picks every thread's skill and effort

run-in-t3 and the orchestrator both start T3 threads for issues, and both ask one shared Router, in `shared/route/`, what each issue's thread runs and at what effort. The Router reads one issue at a time; the skill the user typed decides which issues share a thread. The orchestrator adds only run tracking: the state file, the watcher, the board, conflicts, settling, and closing epics.

We considered having the orchestrator call the run-in-t3 skill. run-in-t3 is a skill only the user may start, it adds an agent step with its own report and stop rules, and the orchestrator needs one data line per issue, not a chat report. We also considered a Router that takes a group of issues and gives one answer, as `decide.sh` did; it broke when one issue in the group was a bug.
