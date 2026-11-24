# A clean-codebase run reads the whole repo

A skill used to read only the files in recent commits. A skill on the shared clean-codebase run reads the whole repo every time, and a folder the user names makes the run smaller. We considered a run that reads only what changed since the last run. A find that one run misses would then never be read again, and agents copy old code as well as new code. The cost is a longer run on a big repo. The report still lists first what is new since the last run.
