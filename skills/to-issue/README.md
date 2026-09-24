# to-issue

Turns what the conversation already settled into one typed, sized GitHub issue that an agent can pick up cold. No interview.

## Use it when

You've talked a piece of work through, a feature, a fix, a refactor, and it's ready to be written down as a ticket. Type `/to-issue` (`$to-issue` in Codex). If the chat is missing who does what, what "done" means, or which repo, it lists those gaps as questions and stops. [grill](../grill/) closes them, or [diagnose](../diagnose/) for a bug whose cause is unknown.

## What you get

One issue with a type prefix in the repo's title style, a size label from XS to L, and a body with What to build, Done when (checkboxes, observable from outside the code), Scope, and Context. XS tickets, and S tickets whose every step is already known, also get Steps with `file:line` and the `handoff-ready` label, so a planner can trust them as they are. Work too big for one PR is sized XL and sent to [to-epic](../to-epic/) instead. Human work in a platform (make an account, get a key) becomes a `task` ticket labelled `manual`.

You get one line back, with the URL on your clipboard:

```
https://github.com/acme/shop/issues/42 · size/M · feat
```

## Needs

- `gh`, signed in.
- `python3`, for `scripts/conventions.py`, which remembers each repo's title style and size labels.
- Sub-agents for the lookup round (Explore agents in Claude Code; Codex reads the files itself).
- `pbcopy`, optional, for the clipboard.
- From the shared core: [issue-rules.md](../../shared-skill-core/issue-rules.md) (gate, types, body template, labels) and [size.md](../../shared-skill-core/size.md), the size ruler.

## Fits with

- Fed by [grill](../grill/), [diagnose](../diagnose/) (`Ready for /to-issue.`), and [discover-path](../discover-path/).
- Turns a `[bug]` from [capture](../capture/) into a `fix` ticket and closes the bug.
- Sends XL work to [to-epic](../to-epic/).
- Its tickets go to [plan-up](../plan-up/), [ship](../ship/), and [kickoff](../kickoff/). [handoff-devin](../handoff-devin/) and [handoff-cursor](../handoff-cursor/) read the size labels through its `scripts/conventions.py`.

## Credits

The idea of turning a conversation into agent-ready tickets comes from the `to-tickets` and `to-spec` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Thanks. No text was copied.
