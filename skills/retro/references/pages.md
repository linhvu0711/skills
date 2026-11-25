# Pages

Retro shows one page: the report, after reading. It is a copy of `assets/report.html`, filled in, served on this machine, so it opens the same way in every harness. In the copy, replace every `{{…}}` placeholder and the example cards and rows. The head, the tokens, and the classes stay as they are; a new colour is a token, set in both themes.

The page shows; it takes no pick. The pick comes back in chat, as card numbers (SKILL.md step 9).

## Writing and showing it

- Folder: `$HOME/.agents/artifacts/retro/<owner>-<repo>-<YYYYMMDD-HHMM>/`, made for this run and holding only the page, since the server shares the whole folder. Transcripts and bundles stay in the scratch folders. File: `report.html`.
- Tailwind, from its play CDN in the scaffold's head, is the only script.
- The layout works at phone width: the scaffold's 16px side gutter, no horizontal page scroll; the overview table scrolls inside its own box.
- Serve and open it:

  ```bash
  URL=$(../../shared/serve.sh <folder> report.html)
  open "$URL"
  ```

  `xdg-open` in place of `open` on Linux. `serve.sh` prints the URL; a `stop:` line from it, or neither `open` nor `xdg-open` on this machine: show the report in chat instead, as a numbered list of the cards with the same parts, and ask the same question. Give the URL in chat either way.

## Card text

Card text is HTML. Code, a command, a flag, or a path goes in `<code>`, never a markdown backtick. A quote keeps its words, with `<`, `>`, and `&` escaped. Short sentences and plain words. An inside name, such as a tool or a role, is explained the first time it appears.

## Report

- **Header**: `Retro report: <repo>`; one mono line of scope (this project and its roots, or all projects, or the orchestrate run), the window, and the counts read; the legend as the scaffold has it; and in the closed `What was read` part, the read line of SKILL.md § Read line: what was read, each item not read or read in part with the reason, each touched PR, each `unread` line, each fix dropped as already in its home, and each home whose check was skipped.
- **Overview** (`id="overview"`): one row per card, in the groups and order of the cards, its number and its title linked to the card. Above each group's rows, one `ov-home` row with the home's `owner/name`. One column per item any card came from, sessions and PRs, in date order, headed by its short name (`S1` over `#25`, or `PR` over `#40`). A cell is filled with the card's strength class when the card came from that item (`hit-one` for a one-time problem or a tip), and empty otherwise. Under the table, a key: one line per column, its label, the item's title, and its date, as `S1 · Fix the export menu · 2026-11-12` or `PR #40 · Add CSV export · 2026-11-10`. A session's date is its row's `modified`; a PR's is its `date` from `github.py list`.
- **Cards** (`id="cards"`): one group per home that has a card, a `<div id="home-<owner>-<name>">` headed by the home's `owner/name`, with `(this project)` after this project's, as SKILL.md step 8 groups them. This project's group comes first, then each other home. Inside a group, one list, most important first. Patterns, one-time problems, and tips share the list. Cards are numbered from 1 down the whole page, so a number in chat names one card.
- **Card**: one per pattern, one-time problem, or tip, as the scaffold's example cards show:
  - Title: the fix, short ("Add a check for unpushed worktrees").
  - Badge: strength, filled: `Strong` (three or more items, or a real cost: lost work, a bad change that shipped, or many wasted turns), `Worth exploring` (two items), `Speculative` (the fix guess is the reader's, not seen in the repo), or `One-time` for a one-time problem. Beside it, the card's kind as a small outlined tag, `open #<n>` when the home has an open issue for it, `the fix did not hold #<n>` when its problem came back after that issue closed, and `home unknown (<reason>)` when step 8 found no home.
  - Item strip: one dot per overview column, filled for the items this card came from, then `<times> times in <k> of <n> items`, its cost, and the items' names.
  - Where: the file from the setup map, or `none: add one with /<skill>`, and the skill that owns it, as SKILL.md § Kinds of finding names; one line per file, in the mono list.
  - What happened: one blockquote per moment, manual-steps line, or worth-sharing line, each with its item and `Where`. The two that show the moment best come first; the rest go in the closed `<k> more quotes` part.
  - Before and after: a fix that changes text in a file on this machine reads that file and shows, per file, its path and place, the lines the fix changes as they are now, and the same lines after. The `Fix.` sentence follows under the two columns. Any other fix, such as `none: add one with /<skill>` or a file not on this machine, shows the Fix box in that place.
  - Fix: one sentence that names the moment it would have stopped, by item and `Where`.
- **Tip**: a card for repeated manual work whose skill the user can already type (SKILL.md § Kinds of finding) has the badge `Tip` in place of a strength, and its Fix box names the skill and its command.
- **Open questions** (`id="open-questions"`): after the cards, one line per open question: what was seen, then its item and `Where`. None: no section.
- **Top pick** (`id="top-pick"`): one larger card at the end: the card number, its title linked to its card, why it goes first in one sentence, and the scaffold's question line.

Style: the scaffold's, editorial and plain. No interaction but the folded parts and the links.
