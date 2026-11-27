<!-- template: one ruler for tickets and PRs. issue-rules.md § Size reads it for tickets; pr-shape.md § Label and make-pr read it for the PR size label; render.sh pastes it into the handoff rules under ## Size. Edit here only. -->
Size is the number of changed lines: the lines a change adds and removes.

| Size | Changed lines |
|---|---|
| XS | 0 to 9 |
| S | 10 to 29 |
| M | 30 to 99 |
| L | 100 to 499 |
| XL | 500 to 999 |
| XXL | 1,000 or more |

What does not count: test files, unless the change touches only tests, and then its test lines are the count; lines whose only change is whitespace, and blank lines added or removed; lockfiles (`*.lock`, `package-lock.json`, `pnpm-lock.yaml`, `npm-shrinkwrap.json`, `bun.lockb`, `go.sum`, `packages.lock.json`, `Package.resolved`, `conda-lock.yml`, `pylock.toml`, `pylock.*.toml`, `*.lockfile`); and files that `.gitattributes` marks `linguist-generated`. A test file sits under a `test/`, `tests/`, or `__tests__/` folder, or is named `*.test.*` or `*.spec.*`.

A PR: the script `size.py` counts its diff against its base. Run `python3 size.py <base>` in the PR's checkout, with the base as `origin/<branch>`; it prints the size.

A ticket: a guess on the same scale, made before the code exists: the lines its change will add and remove, by the same rules. Say it in one line, as `L: about 300 lines, 6 files`. XL is a ticket like any other. XXL is never a ticket: the work goes to file-epic.
