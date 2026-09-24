# create-pr

Opens a GitHub pull request for the current branch, with a body that follows the repo's PR template.

## Use it when

Your changes are committed and you want a PR: "create a PR", "open a pull request", "submit this for review", or `/create-pr`. The agent can also pick it up on its own from those phrases.

## What you get

It checks that `gh` is installed and signed in, looks at the branch, the commits, and the diff against the base, offers to rebase when the branch is behind, then fills in `.github/pull_request_template.md` and opens the PR with `gh pr create --body-file`. It ends with the PR URL, a reminder that CI will run, and the command to add reviewers:

```
gh pr edit --add-reviewer USERNAME
```

## Needs

- `gh`, installed and signed in, and `git`.
- A PR template at `.github/pull_request_template.md` in the repo. The skill follows it strictly.

## Fits with

- [set-coding-standards](../set-coding-standards/) can end with `Ready for /create-pr`.
- Nothing else in this repo calls it; [land-pr](../land-pr/) takes over once the PR is open.

## Credits

A copy of the `create-pull-request` skill from [cline/cline](https://github.com/cline/cline) (`.agents/skills/create-pull-request`), Apache-2.0 license. The skill text is upstream's; this repo does not reword it.
