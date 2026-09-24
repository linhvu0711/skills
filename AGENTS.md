# Agents

## Rules

- Change a skill, update its README in the same commit.
- A skill copied or adapted from another repo gets its upstream's `LICENSE` in its folder and a row in `THIRD_PARTY_NOTICES.md`.

## Checks

- `scripts/check.sh` looks for leaks: absolute home paths, email addresses, and the words in the owner's private list at `.git/info/private-words` (local, never committed).
- `scripts/check.sh` also fails on a relative path in a skill or the shared core that points to no file. A skill's paths start at its folder; a shared core file's paths start at its own folder.
- `scripts/check.sh` fails when a `copy` or `heavy adaptation` row in `THIRD_PARTY_NOTICES.md` has no `LICENSE` next to it: `skills/<name>/LICENSE`, or `shared-skill-core/LICENSE-<owner>` for a shared core file.
- `scripts/check.sh` fails when a skill has no `README.md`, or its README lacks one of `## Use it when`, `## What you get`, `## Needs`, `## Fits with`. A skill listed in `THIRD_PARTY_NOTICES.md` also needs `## Credits`.
- The pre-commit hook runs `scripts/check.sh --staged` on the lines a commit adds, and the license and README checks on all it commits. Turn it on once per clone with `git config core.hooksPath scripts/hooks`.
- `git commit --no-verify` skips the hook. The Repo check on GitHub still runs `scripts/check.sh` on every push and pull request.
- `scripts/adopt.sh <name>` moves a skill from `~/.agents/skills` into `skills/<name>/`, links it back, and runs the check on it. Run it from the main checkout, so the link points there.
