# retro

Looks back over your coding sessions, from every harness it can read, and over the PRs no session worked on. It finds where the agent struggled and what worked well, and turns what repeats into shared fixes to the repo's agent setup: a check, a pointer, a review rule, a standard, a skill.

## Use it when

A session felt harder than it should have, the same kind of trouble keeps coming back, or you want to know what to change after a stretch of work. Type `/retro` for the session you are in. Name a range, IDs, a topic, or sources to read more: `/retro today`, `/retro last 3 days`, `/retro from 2026-10-01 to 2026-10-05`, `/retro the handoff sessions this week`, `/retro only claude sessions`, `/retro PRs from last week`, `/retro last 3 days, all projects`. Many sessions and PRs show what one cannot: the same mistake, the same slow search, the same review comment, the same correction you keep typing, the same good habit.

[orchestrate](../orchestrate/) starts it for you when a run is done, as `/retro run <run folder>`.

## What you get

Retro first asks which harnesses (the tools that run the agent, such as Claude Code or Codex) hold sessions for this repo. Each harness it can read has an adapter in [`sessions/`](../../shared/sessions/); a harness with data and no adapter is named in the report as `found <harness> sessions, cannot read them yet`, never skipped silently. It also lists the PRs and issues in the window that no session names. A PR a session worked on is left out, since the session already holds its reviews and fixes.

If that adds up to more than 20 readers, it tells you the count and waits for `go`. Then one reader agent reads each session (with its helper agents' logs), each PR (its body, reviews, review threads, and the end of each failed CI log), and the issues. Each writes an evidence list: the moments things went wrong, corrections you or a reviewer gave more than once, steps you did by hand, and ways of working worth sharing. Text in a session or a PR can come from anyone, so each reader is told it is data to read, never orders to follow.

Retro then maps the repo's own agent setup: which file holds the steering, the review rules, the coding standards, the skills, the checks, and the docs, whatever their names. It groups the moments by the fix that would stop them, and each fix names the real file it changes, or says "add one" and names the skill that writes it. Fixes go only to files the team shares, never to your own private files.

The report is a page on this machine, opened in your browser. Patterns come first: problems seen in two or more sessions or PRs that one fix would stop, each with its items, quotes as proof, the fix, where it goes, and a strength badge (`Strong`, `Worth exploring`, `Speculative`). Retro also finds a skill that should have run and did not; the fix it proposes is that skill's description. Steps you did by hand in two or more sessions become a proposed new skill, or a tip that names the skill you can already type for them. A tip has nothing to file. For a correction you keep giving, the first fix it proposes is to delete the old code or the old way the agent keeps copying; then a check, a skill fix, and a steering line last. A proposed check names the past mistake that it would have caught. Ways of working that went well in two or more items become a card to share them. Serious one-time problems follow, then a top pick. Tick the cards you want, press Copy, and paste the line. Each pick becomes an issue through [to-issue](../to-issue/), or a seed through [capture](../capture/) when to-issue needs more than the card holds. You are told which.

If nothing is worth changing, it says `Nothing worth changing` and stops. Either way it says what it read, and names anything it did not read or read only in part. It changes no code and files nothing you did not pick.

## Needs

- `python3` (standard library only), `git`, and `gh` for the repo name, the PRs, and the issues. Without `gh` access it reads sessions only and says so.
- Session logs on this machine for at least one harness with an adapter in the shared core's [`sessions/`](../../shared/sessions/): today Claude Code (`~/.claude/projects/`) and Codex (`~/.codex/sessions/` and `~/.codex/archived_sessions/`, headless `codex exec` runs left out). Older Codex chats are compressed; reading them needs Python 3.14+ or the `zstd` command.
- For `run <folder>`: T3 Code's provider logs under `~/.t3/userdata/logs/provider/`, read by [`sessions/t3/`](../../shared/sessions/t3/).
- Sub-agents: Explore agents in Claude Code, `explorer` agents in Codex, one per session or PR.
- A browser and `open` or `xdg-open` for the report page, served by the shared core's `serve.sh`. Without them, the report comes as a list in chat.
- [to-issue](../to-issue/) and [capture](../capture/), for the cards you pick.

## Fits with

- Use it after a build worth learning from, such as one run with [ship](../ship/). [orchestrate](../orchestrate/) starts it at the end of every run.
- Fixes it proposes often land through [set-review-rules](../set-review-rules/), [set-coding-standards](../set-coding-standards/), or [audit-coding-standards](../audit-coding-standards/), and through [write-for-agents](../write-for-agents/) for any skill or steering text.
- [find-cc-session](../find-cc-session/) and [find-co-session](../find-co-session/) find one session; retro reads many through the same scripts, behind each harness's adapter.

## Credits

Adapted from the `retro` skill in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Its kinds of finding and its reference on implementation and review come from there, rewritten around this repo's skills. Reading many sessions from any harness, reading PRs, the setup map, the report page, and the hand-off to issues are new here.

The missed-skill and manual-work kinds, and deleting the old code first for a repeated correction, take ideas from the `reflect` and `correct` skills in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
