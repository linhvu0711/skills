# Resolve the target

Used by run-in-t3 and orchestrate. It turns the issues the user names, in words or by number, into the repo and the issue numbers a skill works on.

## Resolving the target from the session

The user seldom pastes a URL. They name issues by number or in words, most often ones this session made or talked about: `12`, `12 and 14`, `all of P1 in this epic`, `on this`, or nothing right after `/file-issue`. Before you go on, do these steps.

1. **Repo.** Take it from the session: the issues made or linked here, or the repo of the current folder (`gh repo view --json nameWithOwner`). Two repos fit, or none: ask.
2. **Issues.** Find each issue the user means. A number is an issue in that repo. Words point back into the session: "this", "that issue", "the one we just made", a link pasted earlier, the PR the work sits on. A phase, as in "P1 of this epic", is the `### Phase 1` section under `## Phases` in the epic's body; take its open tickets, top to bottom (`gh issue view <epic> --json body,subIssues`). None or several match: say what you found, name the candidates, and ask.

The word `on` is overloaded: `on this` can mean "target this issue" or "stack it on this PR". When that is unclear, ask before going on.
