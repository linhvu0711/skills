# review-pr

Reviews a pull request on three separate checks (logic, scope, standards), one subagent each, with your repo's Standard and its decisions folded in.

## Use it when

You want a review before you merge. `/review-pr 42` reviews PR 42; `/review-pr` with no number reviews the PR of the current branch, or the branch against the default branch when there is no PR. It only runs when you call it.

## What you get

A report in chat and in `~/.claude/reviews/<repo>-<pr>.md`. Each finding has a severity (🔴 blocker, 🟠 should, 🔵 nit), a `path:line`, the rule it breaks, and a one-line fix. The rules come from your Standard, `CODING_STANDARDS.md` and the `docs/standards/` files it links to, each sent to the check it belongs to. The ADRs in `docs/adr/` that are in force and about the changed files go along too, so a change that goes against a decision is a finding. A proposed, deprecated, or superseded ADR is left out, since it is not in force. Scope is judged against the linked issue and its epic. It never posts to GitHub; the last line gives you the command to do it yourself:

```
Verdict: request changes. To post: gh pr review 42 --request-changes -F ~/.claude/reviews/acme-42.md
```

The logic check also flags a test that would still pass if every function it imports returned `undefined`, a test that breaks when only the inside of the code changes, a test that checks which of the repo's own functions the code called or mocks a part the repo owns, a test the repo's own test rules say not to write, a fix that hides a failure instead of fixing its cause, and a guard for a state that should never happen. Its regression check also looks for the names grep misses: keys in data formats, database columns, and flags. The standards check adds sixteen possible smells: split state, two ways to do one job, code the change made unused but left in, importable internals, hand-synced lists, code that could be simpler, a check in the wrong place or outside data with no parse, an if/else chain that grows by one branch per case, two true/false values that must stay in sync, a comment that says what the code does instead of why, a step that is not safe to run twice or after a crash, code that works around a data shape that does not fit, a new case added at the side instead of in the model, two kinds of ID that can be mixed up, a type copied by hand from a schema, and a lock where each writer could have its own target. Every helper agent it starts is told it changes nothing: no file edits, no commits, no `gh` writes, since it reads PR text from anyone.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- `git` and `gh`, signed in.
- Subagents: the axis agents `logic-reviewer`, `scope-reviewer`, and `standards-reviewer`, in `agents/`, each started per `../../shared/facts.md` § Skill agents on the try list its tier gives for your harness, and explorers that read the Standard and the ADRs. The harness table, `../../shared/harness.md`, says how your harness starts them. [link.sh](../../scripts/link.sh) installs the agent files into Claude Code and Codex.
- The shared core files `../../shared/facts.md`, `../../shared/review/general-rules.md`, and `../../shared/coding-standards/standard.md`, which says which lines of the Standard are rules.

## Fits with

- Reads the Standard that [audit-coding-standards](../audit-coding-standards/) writes. With no Standard, the report suggests running it.
- Nothing calls this skill; you run it.

## Credits

Thanks to [mattpocock/skills](https://github.com/mattpocock/skills) for the `code-review` skill, which gave us the idea (MIT license). No text was copied.

The check on tests that count calls or mock the repo's own parts takes an idea from `tdd/tests.md` in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). No text was copied.

Some logic checks and smells take ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT): its root-cause, legacy-API, boundary, domain-model, idempotency, test-behavior, foundational-thinking, first-principles, type-system, and shared-state principles and its design red flags. No text was copied.
