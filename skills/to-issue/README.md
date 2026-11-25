# to-issue

Turns what the conversation already settled into one typed, sized GitHub issue that an agent can pick up cold. No interview.

## Use it when

You've talked a piece of work through, a feature, a fix, a refactor, and it's ready to be written down as a ticket. Type `/to-issue` (`$to-issue` in Codex). If the chat holds only a loose idea, or a bug nobody has decided how to fix, it files it through [capture](../capture/) as a seed or a bug, and tells you in one line what a real ticket still needs. If the work is agreed but one fact is missing, like what an empty list shows or which repo, it lists the gaps as questions and stops. [grill](../grill/) closes them, or [triage](../triage/) for a bug whose cause is unknown.

## What you get

One issue with a type prefix in the repo's title style, a size label from XS to L, and a body with What to build, Done when (checkboxes, observable from outside the code), Scope, and Context. It is assigned to you, unless you name someone else or say no assignee. XS tickets, and S tickets whose every step is already known, also get Steps with `file:line` and the `ready-to-build` label, so a planner can trust them as they are. A step that copies code copies the way the repo's Standard (`CODING_STANDARDS.md`) names for that job. It points at the nearest pattern in the code only when the Standard has no rule for it. Work too big for one PR is sized XL and sent to [to-epic](../to-epic/) instead. Human work in a platform (make an account, get a key) becomes a `task` ticket labelled `manual`. Every ticket is written for a stranger with neither the chat nor your machine: code in Context as permalinks, errors and evidence in the issue, and no local paths or session words. Before it files, it searches open and closed issues. Name another repo in the chat, or let a skill such as retro name it, and it files there: it reads that repo's labels and searches that repo's issues, and the issue names nothing of the repo you ran it in. A closed issue on the same work does not stop it: the new issue links it on its Related line, so a bug that came back keeps its history.

You get one line back, with the URL on your clipboard:

```
https://github.com/acme/shop/issues/42 · size/M · feat
```

When it files through capture, you get two lines back instead:

```
Captured: https://github.com/acme/shop/issues/88 (on your clipboard)
Not a ticket yet: what must Retry do after a 500?
```

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

## Needs

- `gh`, signed in.
- `python3`, for the shared core's [issue_conventions.py](../../shared/issue_conventions.py), which remembers each repo's title style and size labels.
- Readers for the lookup round, per the reader job in `../../shared/facts.md` (Codex reads the files itself).
- A clipboard tool, optional, for the URL, through [copy.sh](../../shared/copy.sh): macOS, Linux, or Windows. With none, it says the copy was skipped.
- From the shared core: [issue-rules.md](../../shared/issue-rules.md) (gate, types, body template, labels) and [size.md](../../shared/size.md), the size ruler.

## Fits with

- Fed by [grill](../grill/) and [discover-path](../discover-path/). Called by [triage](../triage/) as its last step.
- Turns a `[bug]` or a `seed` from [capture](../capture/), any bug or seed issue the chat names, or a one-ticket map that [discover-path](../discover-path/) cleared, into the ticket in place: same number, new title and body. Nothing new is opened and nothing is closed.
- Puts doc text that a [grill](../grill/) agreed on (a glossary entry, an ADR) under `## Docs to write`, so it lands in the PR that ships the code.
- Sends XL work to [to-epic](../to-epic/).
- Sends a loose idea, or a bug with no agreed fix, to [capture](../capture/).
- Its tickets go to [plan-up](../plan-up/), [ship](../ship/), and [kickoff-herdr](../kickoff-herdr/). [handoff](../handoff/) reads the size labels through the same script.

## Credits

The idea of turning a conversation into agent-ready tickets comes from the `to-tickets` and `to-spec` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Thanks. No text was copied. The closed-issue search before filing comes from the triage dedupe of `automations/benny` in pstack, in [cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack). Idea only; none of the text.
