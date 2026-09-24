# set-review-rules

Writes a `REVIEW.md` for your repo: the same three-part review every repo gets, plus the rules only your repo needs.

## Use it when

You want reviewers, human or agent, to check the same things on every pull request. Type `/set-review-rules` in the repo. It only runs when you call it.

## What you get

A `REVIEW.md` at the root. The top block is fixed and checks three things: does it work (Logic), does it match the task (Scope), does it fit how the repo writes code (Standards). Below it go your repo rules, one line each, such as "A migration PR includes the down migration and a dry-run log". It finds rules already in the repo (PR templates, `CONTRIBUTING.md`, bot configs), proposes more from the folders that fix and revert commits touch most, and asks you about each one before it writes. `CLAUDE.md` and `AGENTS.md` get one line that points at the file. Nothing is committed. The chat ends with:

```
Ready for /make-commit
```

## Needs

- `git` and `gh` (`gh issue view` checks that an issue a rule names still exists).
- The [grill](../grill/) skill, which asks you about each proposal.
- The shared core files `../../shared-skill-core/facts.md`, `../../shared-skill-core/review/general-rules.md`, and `../../shared-skill-core/review/rule-sources.md`.

## Fits with

- Calls [grill](../grill/).
- Hands off to [make-commit](../make-commit/).
- [review-pr](../review-pr/) reads the `REVIEW.md` it writes, and suggests this skill when a repo has no review rules.

## Credits

Thanks to [mattpocock/skills](https://github.com/mattpocock/skills) for the `code-review` skill, which gave us the idea (MIT license). No text was copied.
