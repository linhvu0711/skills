# Pages

Retro shows one page: the report, after reading. It is a copy of `assets/report.html`, filled in, served on this machine, so it opens the same way in every harness. In the copy, replace every `{{…}}` placeholder and the example cards and rows. The head, the tokens, and the classes stay as they are; a new colour is a token, set in both themes.

The page shows; it takes no pick. The pick comes back in chat, as card numbers (SKILL.md step 8).

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

Card text is HTML. Code, a command, a flag, or a path goes in `<code>`, never a markdown backtick. A quote keeps its words, with `<`, `>`, and `&` escaped.

## Report

- **Header**: `Retro report: <repo>`; one mono line of scope (this project and its roots, or all projects, or the orchestrate run), the window, and the counts read; the legend as the scaffold has it; and in the closed `What was read` part, the read line of SKILL.md § Read line: what was read, each item not read or read in part with the reason, each touched PR, and each scan line.
- **Overview** (`id="overview"`): one row per card, its number and its title linked to the card. One column per item any card came from, sessions and PRs, in date order, headed by its short name (`S1` over `#25`, or `PR` over `#40`). A cell is filled with the card's strength class when the card came from that item (`hit-one` for a one-time problem or a tip), and empty otherwise.
- **Patterns** (`id="cards"`): one card per pattern, most costly first, numbered from 1. Each card, as the scaffold's example cards show:
  - Title: the fix, short ("Add a check for unpushed worktrees").
  - Badges: strength, filled: `Strong` (three or more items, or a costly moment), `Worth exploring` (two items), `Speculative` (the fix guess is the reader's, not seen in the repo). Then the kind of finding, outlined.
  - Item strip: one dot per overview column, filled for the items this card came from, then `<k> of <n> items` and their names.
  - Where: the file from the setup map, or `none: add one with /<skill>`, and the skill that owns it, as SKILL.md § Kinds of finding names; one line per file, in the mono list.
  - What happened: one blockquote per moment, manual-steps line, or worth-sharing line, each with its item and `Where`. The two that show the moment best come first; the rest go in the closed `<k> more quotes` part.
  - Before and after: a fix that changes text in a file on this machine reads that file and shows, per file, its path and place, the lines the fix changes as they are now, and the same lines after. The `Fix.` sentence follows under the two columns. Any other fix, such as `none: add one with /<skill>` or a file not on this machine, shows the Fix box in that place.
  - Fix: one sentence; a check also names the mistake it would have failed on, by item and `Where`.
- **Tip**: a card for repeated manual work whose skill the user can already type (SKILL.md § Kinds of finding) has the badge `Tip` in place of a strength, and its Fix box names the skill and its command.
- **One-time problems** (`id="one-time"`): cards after the patterns, numbered on from the last pattern, same parts, badge `One-time`.
- **Top pick** (`id="top-pick"`): one larger card at the end: the card number, its title linked to its card, why it goes first in one sentence, and the scaffold's question line.

Style: the scaffold's, editorial and plain. No interaction but the folded parts and the links.
