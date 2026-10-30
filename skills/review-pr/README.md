# review-pr

Reviews a pull request on three separate checks (logic, scope, standards), one subagent each, with your repo's own review rules folded in.

## Use it when

You want a review before you merge. `/review-pr 42` reviews PR 42; `/review-pr` with no number reviews the PR of the current branch, or the branch against the default branch when there is no PR. It only runs when you call it.

## What you get

A report in chat and in `~/.claude/reviews/<repo>-<pr>.md`. Each finding has a severity (🔴 blocker, 🟠 should, 🔵 nit), a `path:line`, the rule it breaks, and a one-line fix. Scope is judged against the linked issue and its epic. It never posts to GitHub; the last line gives you the command to do it yourself:

```
Verdict: request changes. To post: gh pr review 42 --request-changes -F ~/.claude/reviews/acme-42.md
```

The logic check also flags a test that would still pass if every function it imports returned `undefined`, a test that breaks when only the inside of the code changes, a test that checks which of the repo's own functions the code called or mocks a part the repo owns, a fix that hides a failure instead of fixing its cause, and a guard for a state that should never happen. Its regression check also looks for the names grep misses: keys in data formats, database columns, and flags. The standards check adds sixteen possible smells: split state, two ways to do one job, code the change made unused but left in, importable internals, hand-synced lists, code that could be simpler, a check in the wrong place or outside data with no parse, an if/else chain that grows by one branch per case, two true/false values that must stay in sync, a comment that says what the code does instead of why, a step that is not safe to run twice or after a crash, code that works around a data shape that does not fit, a new case added at the side instead of in the model, two kinds of ID that can be mixed up, a type copied by hand from a schema, and a lock where each writer could have its own target. Every helper agent it starts is told it changes nothing: no file edits, no commits, no `gh` writes, since it reads PR text from anyone.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- `git` and `gh`, signed in.
- An agent that can start subagents. In Codex, which has none, it runs the three checks one after the other.
- The shared core files `../../shared/facts.md`, `../../shared/review/general-rules.md`, and `../../shared/review/rule-sources.md`.

## Fits with

- Reads the `REVIEW.md` that [set-review-rules](../set-review-rules/) writes. With no rules in the repo, the report suggests running it.
- Nothing calls this skill; you run it.

## Credits

Thanks to [mattpocock/skills](https://github.com/mattpocock/skills) for the `code-review` skill, which gave us the idea (MIT license). No text was copied.

The check on tests that count calls or mock the repo's own parts takes an idea from `tdd/tests.md` in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). No text was copied.

Some logic checks and smells take ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT): its root-cause, legacy-API, boundary, domain-model, idempotency, test-behavior, foundational-thinking, first-principles, type-system, and shared-state principles and its design red flags. No text was copied.
