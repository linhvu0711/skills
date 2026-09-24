# Agents

## Checks

- `scripts/check.sh` looks for leaks: absolute home paths, email addresses, and the words in the owner's private list at `.git/info/private-words` (local, never committed).
- `scripts/check.sh` also fails on a relative path in a skill or the shared core that points to no file. A skill's paths start at its folder; a shared core file's paths start at its own folder.
- The pre-commit hook runs `scripts/check.sh --staged` on the lines a commit adds. Turn it on once per clone with `git config core.hooksPath scripts/hooks`.
- `git commit --no-verify` skips the hook. The Repo check on GitHub still runs `scripts/check.sh` on every push and pull request.
- `scripts/adopt.sh <name>` moves a skill from `~/.agents/skills` into `skills/<name>/`, links it back, and runs the check on it. Run it from the main checkout, so the link points there.
