# Pages

Retro shows one page: the report, after reading. `scripts/build-report.py` builds it from one cards file, so each fact the page shows in more than one place, such as which items a card came from, is written once. The page is served on this machine, so it opens the same way in every harness. The head, the tokens, and the classes of `assets/report.html` stay as they are; a new colour is a token, set in both themes.

The page shows; it takes no pick. The pick comes back in chat, as card numbers (SKILL.md step 9).

## Writing and showing it

- Folder: `$HOME/.agents/artifacts/retro/<owner>-<repo>-<YYYYMMDD-HHMM>/`, made for this run and holding only `cards.json` and `report.html`, since the server shares the whole folder. Transcripts and bundles stay in the scratch folders.
- Build the page: `python3 scripts/build-report.py <folder>/cards.json`. It prints `page: <path>`. Problem lines name each fault in the cards file: fix the file and build again.
- Tailwind, from its play CDN in the head of `assets/report.html`, is the only script.
- The layout works at phone width: the page's 16px side gutter, no horizontal page scroll; the overview table scrolls inside its own box.
- Serve and open it:

  ```bash
  URL=$(../../shared/serve.sh <folder> report.html)
  open "$URL"
  ```

  `xdg-open` in place of `open` on Linux. `serve.sh` prints the URL; a `stop:` line from it, or neither `open` nor `xdg-open` on this machine: show the report in chat instead, as a numbered list of the cards with the same parts, and ask the same question. Give the URL in chat either way.

## Card text

These fields are HTML: `read`, a card's `title`, `where`, and `fix`, `top_why`, and a question's `text`. Code, a command, a flag, or a path in them goes in `<code>`, never a markdown backtick. Every other field is plain text, and the builder escapes it: a quote's `text`, `item`, and `where`, a `texts` entry, and an item's `title`. So a quote keeps its words as they were said. Short sentences and plain words. An inside name, such as a tool or a role, is explained the first time it appears.

## Cards file

`cards.json`, one JSON object with these keys:

- `repo`: this project's `owner/name`, as step 1 found it.
- `scope`: this project and its roots, or all projects, or the orchestrate run.
- `window`: the dates read.
- `counts`: the counts read, as `12 sessions, 3 PRs, 1 issue read`.
- `read`: the read line of SKILL.md § Read line, one HTML line per entry: what was read, each item not read or read in part with the reason, each touched PR, each `unread` line, each harness the sources keep whose finder failed, each fix dropped as already in its home, and each home whose check was skipped.
- `items`: each session and PR read, once, whether or not a card came from it: a card's count is out of these, and an open question cites one of them. The overview's columns are the items a card came from. `id` is `S1` for a session, or `PR #40`; `ref`, for a session, is the issue it worked on, as `#25`; `title`; and `date`: a session's row `modified`, a PR's `date` from `github.py list`.
- `cards`: one per pattern, one-time problem, or tip, most important first inside each home, as SKILL.md step 8 ranks them. Each card holds:
  - `title`: the fix, short ("Add a check for unpushed worktrees").
  - `badge`: `Strong` (three or more items, or a real cost: lost work, a bad change that shipped, or many wasted turns), `Worth exploring` (two items), `Speculative` (the fix guess is the reader's, not seen in the repo), `One-time` for a one-time problem, or `Tip` for repeated manual work whose skill the user can already type (SKILL.md § Kinds of finding); a tip's `fix` names the skill and its command.
  - `kind`: the card's kind, as SKILL.md § Kinds of finding names it.
  - `home`: the home's `owner/name`, or `home_unknown` with the reason when step 8 found no home.
  - `open`: the number of the home's open issue for it, when there is one. `did_not_hold`: the number of the closed issue whose problem came back.
  - `items`: the ids of the items it came from. `times`: its moments. `cost`: the sum of its `Cost` lines, empty for a worth-sharing card.
  - `where`: one HTML line per file, the file from the setup map or `none: add one with /<skill>`, and the skill that owns it.
  - `quotes`: one per moment, manual-steps line, or worth-sharing line, each with `text`, `item`, one of the card's `items`, and `where`. The two that show the moment best come first.
  - `texts`: only for a fix that changes text in a file on this machine: per file, `file`, `place`, `now`, the lines as they are, and `after`, the same lines after the fix.
  - `fix`: one sentence that names the moment it would have stopped, by item and `Where`.
- `questions`: one per open question, with `text`, what was seen, and its `item` and `where`. None: an empty list.
- `top_why`: why the first card goes first, in one sentence.

The builder draws the columns in date order, the grid, the key, the dots, the counts, the groups, the numbers, and the top pick from these keys.

Style: `assets/report.html`'s, editorial and plain. No interaction but the folded parts and the links.
