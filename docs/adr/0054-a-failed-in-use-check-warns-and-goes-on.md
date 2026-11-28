# A failed in-use check warns and goes on

`prune-worktrees.sh` keeps a worktree that a live process uses as its working folder. When the check for live processes cannot run on this host, the script says so and goes on, and removes only worktrees that are clean and merged, as it did before the check existed (#138). A worktree the user names with `--remove` is still removed, uncommitted files and all, since the user chose it.

A clean, merged worktree has nothing to lose. Stopping the whole prune because one check could not run would leave every merged worktree in place.
