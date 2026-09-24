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
- **Bot config**: a file a review tool owns. Named, never edited, and its
  rules are not yours to run.
- **Not a rule**: install steps, how to open a PR, code style that
  `CODING_STANDARDS.md` already owns.

Done when every path in the list has been looked for and every hit is
in a bin.
