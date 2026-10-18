# Where a repo keeps its review rules

Fixed list, always checked, every path looked for:

`REVIEW.md`, `REVIEWING.md`, `CONTRIBUTING.md`, `CODING_STANDARDS.md`,
`CLAUDE.md`, `AGENTS.md`, `CONTEXT.md`, `docs/adr/**`, `docs/**`,
`.github/PULL_REQUEST_TEMPLATE*`, `.github/pull_request_template*`,
`.github/CODEOWNERS`, `CODEOWNERS`, CI config (`.github/workflows/**`,
`.gitlab-ci.yml`, `Jenkinsfile`), review bot configs
(`.coderabbit.yaml`, `.github/copilot-instructions.md`, `.cursorrules`,
`.cursor/rules/**`).

Read each hit. Sort it into one of three bins:

- **Review rule**: a sentence a reviewer must check. "Every migration
  has a down." "No new dependency without an issue." A PR template
  checklist counts. A "Reviewing" or "Code review" section in any file
  counts, line by line.
- **Bot config**: a file a review tool owns. Its rules are not yours to
  run. The one pointer line set-review-rules writes there is the only
  part of it anyone here edits.
- **Not a rule**: install steps, how to open a PR, code style that
  `CODING_STANDARDS.md` already owns.

Done when every path in the list has been looked for and every hit is
in a bin.

## Review bots

A repo uses a review bot when its config file is in the repo, or when
`reviewers.sh`, next to this file, names it on one of the last 10 PRs:
`gh pr list --state all --limit 10 --json number -q '.[].number'`, then
the script once per number.

Each bot reads `REVIEW.md` through one pointer, never a copy of the
rules, so the rules change in one file:

| Bot | File | Pointer |
|---|---|---|
| devin | none | none: it reads `REVIEW.md` itself |
| coderabbit | `.coderabbit.yaml` | `"**/REVIEW.md"` in `knowledge_base.code_guidelines.filePatterns` |
| bugbot | `.cursor/BUGBOT.md` | `- [Review rules](../REVIEW.md)` |
| any other | | none known |

A missing file is made with the pointer alone. A file that holds the
pointer stays as it is. A file that holds more keeps all of it; the
pointer is added and nothing else changes.
