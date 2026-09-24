# make-commit

Writes a short Conventional Commits message for your staged change, focused on why, not what.

## Use it when

You need a commit message: "write a commit", "commit message", `/make-commit`, `/commit`, or `/git-commit`. The agent can also pick it up on its own from those phrases.

## What you get

One message in a code block, ready to paste. The subject is `type(scope): summary`, imperative, 50 characters when it can be and never over 72. A body only when the why is not obvious, and always for breaking changes, security fixes, data migrations, and reverts. It does not stage, commit, or amend.

```
feat(api): add GET /users/:id/profile

Mobile client needs profile data without the full user payload
to reduce LTE bandwidth on cold-launch screens.
```

## Needs

Nothing but the agent. It reads the change you describe or the diff in front of it and runs no tools.

## Fits with

Called by [land-pr](../land-pr/) for its fix commits, [validate-pr-review](../validate-pr-review/) after you say go, [set-coding-standards](../set-coding-standards/) and [set-review-rules](../set-review-rules/) as their last step, and [discover-path](../discover-path/).

## Credits

A copy of the `caveman-commit` skill from [juliusbrussee/caveman](https://github.com/juliusbrussee/caveman) (`skills/caveman-commit`), MIT license. The skill text is upstream's, plus one line added here that says its paths start at its folder.
