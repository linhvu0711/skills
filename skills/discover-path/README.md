# discover-path

Turns an idea too big for one grill into a map on GitHub: a parent issue whose child tickets are the questions to settle, worked one per run until the way to the goal is clear.

## Use it when

The idea is big and foggy, and you can't cut it into tickets yet because too much is undecided. [grill](../grill/) tells you so when its questions keep multiplying. Type `/discover-path` with the idea, a seed issue URL, or an existing map URL (`$discover-path` in Codex).

## What you get

The first run charts the map. It grills you on where the effort should end and what stands in the way, then proposes the tickets in chat. Nothing reaches GitHub until you approve. After that you get a map issue labelled `discovery/map` (a seed issue you started from becomes the map, same number) and one child ticket per question, typed `grill`, `research`, `experiment`, or `task`, with blocked-by edges between them.

Each later run takes the next free ticket, settles it with you, posts the answer, closes the ticket, and updates the map. Glossary entries and ADRs the grills agree on wait on the map, under `## Docs to write`, not in your doc files, and no docs PR opens while you work:

```
Closed [grill] Which plan model: per seat or per team?. Next free: [research] Does Stripe support per-seat proration?. Run /discover-path <map-url> again.
```

When no ticket and no fog is left, it prints `Map clear.`, the full list of decisions, and hands over to [to-epic](../to-epic/), or to [to-issue](../to-issue/) when the work fits one ticket. The map becomes the epic or the ticket, same number, and each doc entry goes to the sub-issue whose code makes it true, so it lands in that PR. When the end is a decision with no code to build, the doc entries ship in one docs PR.

## Needs

- `gh`, signed in, on a repo with sub-issues and issue dependencies. When the plan lacks them, it falls back to task lists and `Blocked by:` lines.
- Sub-agents for research tickets (Explore agents with web search in Claude Code).
- A clipboard tool, optional, to put the map URL on the clipboard, through [copy.sh](../../shared-skill-core/copy.sh): macOS, Linux, or Windows. With none, it says the copy was skipped.
- [grill](../grill/) for the charting and every grill ticket.
- [commit](../commit/) to commit research notes.
- [create-mockup](../create-mockup/) and [create-diagram](../create-diagram/) for experiment tickets.
- From the shared core: [issue-rules.md](../../shared-skill-core/issue-rules.md). From grill: [research.md](../grill/references/research.md).

## Fits with

- Calls [grill](../grill/), [commit](../commit/), [create-mockup](../create-mockup/), and [create-diagram](../create-diagram/).
- Hands a clear map to [to-epic](../to-epic/), or to [to-issue](../to-issue/) when the work fits one ticket.
- Suggested by [grill](../grill/) when the work will not settle in one session.

## Credits

Adapted from the `wayfinder` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills.
