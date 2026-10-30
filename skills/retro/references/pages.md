# Pages

Retro shows one page: the report, after reading. It is one HTML file the agent writes, served on this machine, so it opens the same way in every harness.

The page ends in a Copy bar: the user ticks cards, the bar shows the line, the user pastes the line in chat. The line is the only way a choice comes back.

## Writing and showing it

- Folder: `$HOME/.agents/artifacts/retro/<owner>-<repo>-<YYYYMMDD-HHMM>/`, made for this run and holding only the page, since the server shares the whole folder. Transcripts and bundles stay in the scratch folders. File: `report.html`.
- A full document: `<!doctype html>`, `<html>`, `<head>` with `<title>`, `<meta name="viewport" content="width=device-width, initial-scale=1">`, and `<style>`, then `<body>`.
- Tailwind loads from its play CDN (`<script src="https://cdn.tailwindcss.com"></script>`). It and the Copy bar script below are the only scripts.
- Define the light palette on `:root`, and the dark one under `@media (prefers-color-scheme: dark)`. Give `body` a token background.
- The layout works at phone width: 16px side gutter, no horizontal page scroll; a wide table scrolls inside its own box. The Copy bar adds `env(safe-area-inset-bottom, 0px)` to its bottom padding, and the page leaves room under its last card for the bar.
- Serve and open it:

  ```bash
  URL=$(../../shared/serve.sh <folder> report.html)
  open "$URL"
  ```

  `xdg-open` in place of `open` on Linux. `serve.sh` prints the URL; a `stop:` line from it, or neither `open` nor `xdg-open` on this machine: show the report in chat instead, as a numbered list of the cards with the same parts, and the user answers with the same line. Give the URL in chat either way.

## Copy bar

A bar fixed to the bottom of the page: a read-only text box with the line, and a `Copy` button. The text box is always shown, so a user whose clipboard is blocked can select the line by hand. Every checkbox carries `data-n` with its card number.

```html
<div class="copybar fixed inset-x-0 bottom-0 flex gap-2 p-3 border-t">
  <input id="line" readonly aria-label="Line to paste in chat" class="flex-1 font-mono text-sm px-2 rounded border">
  <button id="copy" class="px-3 rounded border">Copy</button>
</div>
<script>
  const boxes = [...document.querySelectorAll("input[data-n]")];
  const line = document.getElementById("line");
  function update() {
    const on = boxes.filter(b => b.checked).map(b => b.dataset.n);
    line.value = on.length ? "issue " + on.join(" ") : "issue none";
  }
  boxes.forEach(b => b.addEventListener("change", update));
  document.getElementById("copy").addEventListener("click", () => {
    line.select();
    (navigator.clipboard ? navigator.clipboard.writeText(line.value) : Promise.reject())
      .catch(() => document.execCommand("copy"));
  });
  update();
</script>
```

## Report

- **Header**: the `<title>` and heading `Retro report`, one line of scope (this project and its roots, or all projects, or the orchestrate run; the window; the topic; the sources), and the read line of SKILL.md § Read line: what was read, each item not read or read in part with the reason, each touched PR, and each scan line.
- **Patterns**: one card per pattern, most costly first, numbered from 1. Each card:
  - Title: the fix, short ("Add a check for unpushed worktrees").
  - Badges: the kind of finding, and strength: `Strong` (three or more items, or a costly moment), `Worth exploring` (two items), `Speculative` (the fix guess is the reader's, not seen in the repo).
  - Items: the session numbers and dates, and the PR numbers, it came from.
  - Quotes: one blockquote per moment, manual-steps line, or worth-sharing line, each with its item and `Where`.
  - Fix: one sentence; a check also names the mistake it would have failed on, by item and `Where`. Where: the file from the setup map, or `none: add one with /<skill>`, and the skill that owns it, as SKILL.md § Kinds of finding names.
  - A checkbox, not ticked. A tip (SKILL.md § Kinds of finding, Repeated manual work) has none, so it can never be picked to file.
- **One-time problems**: smaller cards after the patterns, numbered on from the last pattern, same parts, badge `One-time`.
- **Top pick**: one larger card at the end: the card number, its title, why it goes first in one sentence, and an anchor link to it.

Style: plain, editorial, generous white space. One accent color; amber for `Worth exploring`, slate for `Speculative`. Quotes in a monospace font. No other interaction than the checkboxes and the Copy bar.
