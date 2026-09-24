# Skills point at files by paths relative to their own folder

A skill names its own files as `scripts/x.sh`, another skill's files as `../<skill>/...`, and the shared core as `../../shared-skill-core/...`. The repo check can verify every such path, and no home folder appears in public text. Claude Code and Codex report a skill's folder as the link path (`~/.claude/skills/<name>`, `~/.codex/skills/<name>`), so `~/.claude/shared-skill-core` and `~/.codex/shared-skill-core` are links to `~/.agents/shared-skill-core`. Removing those two links breaks every skill that reads the shared core.
