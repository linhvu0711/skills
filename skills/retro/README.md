# retro

Looks back over one coding session or many, finds where the agent struggled, and turns what repeats into fixes to the agent's environment: a check, a pointer, a review rule, a skill fix.

## Use it when

A session felt harder than it should have, or the same kind of trouble keeps coming back. Type `/retro` for the session you are in. Name a range, IDs, or a topic to read many: `/retro last 3 days`, `/retro the handoff sessions this week`, `/retro last 3 days, all projects`. Many sessions show what one cannot: the same mistake, the same slow search, the same correction you keep typing.

## What you get

For many sessions, first a page that lists them: date, tool, title, size. Untick the ones to skip, press Copy, and paste the line in chat. One reader agent then reads each session, with its helper agents' logs, and writes a list of the moments the agent struggled. Retro groups those moments by the fix that would stop them.

Then a report page. Patterns come first: problems seen in two or more sessions that one fix would stop, each with the sessions, quotes as proof, the fix, where it goes, and a strength badge. Serious one-time problems follow, then a top pick. Tick the cards you want, press Copy, and paste the line. Each pick becomes an issue through [to-issue](../to-issue/), or a seed through [capture](../capture/) when to-issue needs more than the card holds. You are told which.

The report also says how many sessions were read, and names any that were not read or were read only in part. It changes no code and files nothing you did not pick.

## Needs

- `python3` (standard library only), `git`, and `gh` for the repo name and the issues.
- Claude Code and Codex session logs under `~/.claude/projects/` and `~/.codex/sessions/`. It reads both; headless `codex exec` runs are left out.
- From the shared core: the session scripts in [`sessions/`](../../shared-skill-core/sessions/).
- Sub-agents: Explore agents in Claude Code, `explorer` agents in Codex, one per session.
- Claude Code's Artifact tool and its `artifact-design` skill, for the two pages. In Codex the pages come as lists in chat.
- [to-issue](../to-issue/) and [capture](../capture/), for the cards you pick.

## Fits with

- Use it after a build worth learning from, such as one run with [ship](../ship/).
- Fixes it proposes often land through [set-review-rules](../set-review-rules/) or [audit-coding-standards](../audit-coding-standards/), and through [write-for-agents](../write-for-agents/) for any skill or steering text.
- [find-cc-session](../find-cc-session/) and [find-co-session](../find-co-session/) find one session; retro reads many with the same scripts.

## Credits

Adapted from the `retro` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Its kinds of finding and its reference on implementation and review come from there, rewritten around this repo's skills. Reading many sessions, the two pages, and the hand-off to issues are new here.
