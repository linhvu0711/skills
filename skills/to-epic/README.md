# to-epic

Cuts a large piece of work into a phased GitHub epic: one parent issue, native sub-issues, and native blocked-by edges. You approve the breakdown in chat before anything is created.

## Use it when

The work is settled but too big for one PR. [to-issue](../to-issue/) sized it XL, or [discover-path](../discover-path/) printed `Map clear.` Type `/to-epic` in the same chat (`$to-epic` in Codex). If the work actually fits one ticket, it says so and points you back to to-issue.

## What you get

First, a breakdown in chat: phases, and per ticket a title, type, size, blocked-by list, and one line of what it delivers. Each ticket is a thin vertical slice that can be verified alone. Work outside the repo, like an account or a key, is its own `task` ticket, never a note. It ends with three questions about granularity, edges, and splits, and loops on your changes until you say `go`.

Then the parent and every sub-issue are created in phase order, with the edges wired, and the parent body rewritten with real numbers:

```
https://github.com/acme/shop/issues/40
#41 [feat] Team entity with create and list · M · phase 1
#42 [task] Create the Stripe Connect account · task · phase 1
...
Free to start now: #41
Yours: #42 Stripe Connect account, #50 live invoice
```

Over 12 tickets, it proposes splitting into several epics first.

## Needs

- `gh`, signed in, on a repo with sub-issues and issue dependencies.
- `python3`, for [to-issue](../to-issue/)'s `scripts/conventions.py`, which remembers each repo's title style and size labels.
- Sub-agents for the lookup round (Explore agents in Claude Code, with web search for a task's platform docs; Codex reads the files itself).
- `pbcopy`, optional, for the parent URL.
- From the shared core: [issue-rules.md](../../shared-skill-core/issue-rules.md), which every sub-issue follows.

## Fits with

- Fed by [discover-path](../discover-path/) and [grill](../grill/). [to-issue](../to-issue/) sends XL work here, and this skill sends a one-ticket job back.
- Its phases are run as a stack of PRs by [plan-up](../plan-up/) and [ship](../ship/), one ticket per layer.

## Credits

Adapted from the `to-tickets` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills.
