# Agents

## Rules

- Change a skill, update its README in the same commit.
- A skill copied or adapted from another repo gets its upstream's `LICENSE` in its folder and a row in `THIRD_PARTY_NOTICES.md`.
- A test for a skill's script goes in `skills/<name>/tests/`, one file per script, on the helpers and the one fake `gh` in `scripts/test-lib.sh`. `scripts/test.sh` runs every such file; add the file's cases to its own `cases` list.

## Checks

- `scripts/check.sh` looks for leaks: absolute home paths, email addresses, and the words in the owner's private list at `.git/info/private-words` (local, never committed).
- `scripts/check.sh` also fails on a relative path in a skill or the shared core that points to no file. A skill's paths start at its folder; a shared core file's paths start at its own folder.
- `scripts/check.sh` fails when a `copy` or `heavy adaptation` row in `THIRD_PARTY_NOTICES.md` has no `LICENSE` next to it: `skills/<name>/LICENSE`, or `shared-skill-core/LICENSE-<owner>` for a shared core file.
- `scripts/check.sh` fails when a skill has no `README.md`, or its README lacks one of `## Use it when`, `## What you get`, `## Needs`, `## Fits with`. A skill that `THIRD_PARTY_NOTICES.md` lists, itself or a file inside it, also needs `## Credits`.
- `scripts/check.sh` fails when a skill's `SKILL.md` has no frontmatter, a `name` that is not its folder name, or an empty `description`.
- The pre-commit hook runs `scripts/check.sh --staged` on the lines a commit adds, and the license, README, and `SKILL.md` checks on all it commits. Turn it on once per clone with `git config core.hooksPath scripts/hooks`.
- The commit-msg hook runs `scripts/check.sh --commit-msg`: a commit that changes a file under `skills/<name>/`, or a shared core file that skill reads, without `skills/<name>/README.md` fails, unless its message has a line `Readme: unchanged`. A skill reads a shared core file when one of its files names it or its folder, when it reads another file in that core subfolder, or when a core file it reads names or includes it. That line skips only this check; the pre-commit checks still run. The GitHub Repo check does not run it.
- `git commit --no-verify` skips both hooks. The Repo check on GitHub still runs `scripts/check.sh` on every push and pull request.
- `scripts/adopt.sh <name>` moves a skill from `~/.agents/skills` into `skills/<name>/`, links it back, and runs the check on it. Run it from the main checkout, so the link points there.
