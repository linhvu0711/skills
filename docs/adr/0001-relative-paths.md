# Skills point at files by paths relative to their own folder

A skill names its own files as `scripts/x.sh`, another skill's files as `../<skill>/...`, and the shared core as `../../shared/...`. The repo check can verify every such path, and no home folder appears in the text. The paths assume the repo's layout: skills side by side in one folder, with `shared/` next to that folder. Some agents report a skill's folder as a link path (for example `~/.claude/skills/<name>`); in that case `shared` must also be reachable from there, for example by a link.
