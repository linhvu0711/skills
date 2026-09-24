# The repo is the one real copy of the public skills

The public skills live in this repo, and `~/.agents/skills/<name>` and `~/.agents/shared-skill-core` are links into it; private skills stay as plain folders in `~/.agents/skills/`. We chose this over turning `~/.agents` itself into the repo, where one `git add -f` or a new skill would leak by default, and over a sync script that copies skills into a separate repo, where the two copies drift. A new skill is private until it is adopted.
