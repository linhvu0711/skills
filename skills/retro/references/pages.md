# Pages

Retro shows two pages: the session list before reading, and the report after. Each is one HTML file, published with the Artifact tool. Load the `artifact-design` skill before writing either. Write each to the scratch folder (`retro-sessions.html`, `retro-report.html`) and publish it with icon `list` or `report`. A second run in the same chat republishes to the same path.

Each page ends in a Copy bar: the user ticks boxes, the bar shows the line, the user pastes the line in chat. The line is the only way a choice comes back.

## Artifact rules

- The host wraps the file in the document skeleton. Write no `<!doctype>`, `<html>`, `<head>`, or `<body>`. Put `<title>` and `<style>` at the top.
- Tailwind loads from its play CDN (`<script src="https://cdn.tailwindcss.com"></script>`). It and the Copy bar script below are the only scripts.
- Define the light palette on `:root`, redefine it under `@media (prefers-color-scheme: dark)` guarded as `:root:not([data-theme="light"])`, and again under `:root[data-theme="dark"]`. Give `body` a token background.
- The layout works at phone width: 16px side gutter, no horizontal page scroll; a wide table scrolls inside its own box. The Copy bar adds `env(safe-area-inset-bottom, 0px)` to its bottom padding, and the page leaves room under its last row for the bar.

## Copy bar

A bar fixed to the bottom of the page: a read-only text box with the line, and a `Copy` button. The text box is always shown, so a user whose clipboard is blocked can select the line by hand. Every checkbox carries `data-n` with its row or card number. Set `MODE` to `"drop"` on the session list and `"pick"` on the report.

```html
<div class="copybar fixed inset-x-0 bottom-0 flex gap-2 p-3 border-t">
  <input id="line" readonly aria-label="Line to paste in chat" class="flex-1 font-mono text-sm px-2 rounded border">
  <button id="copy" class="px-3 rounded border">Copy</button>
</div>
<script>
  const MODE = "drop";
  const boxes = [...document.querySelectorAll("input[data-n]")];
  const line = document.getElementById("line");
  function update() {
    const off = boxes.filter(b => !b.checked).map(b => b.dataset.n);
    const on = boxes.filter(b => b.checked).map(b => b.dataset.n);
    line.value = MODE === "drop"
      ? (off.length ? "go, drop " + off.join(" ") : "go")
      : (on.length ? "issue " + on.join(" ") : "issue none");
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

## Session list

- **Header**: the `<title>` and heading `Retro sessions`, then one line of scope (this project and its roots, or all projects; the window; the topic), then the totals: sessions, total size in MB, readers (one per session), and what was left out with the count (headless Codex runs from the finder's `skipped_exec`, this retro's own session, topic misses).
- **Rows**: one per session, newest first, numbered from 1. Each row: a checkbox, ticked; `#`; date; tool badge (`Claude` or `Codex`); title, or the first prompt cut to 80 characters; size; helper logs count. All projects: one group per project, its folder as the heading with the session count, rows numbered on across groups.
- `MODE = "drop"`.

## Report

- **Header**: the `<title>` and heading `Retro report`, the scope line from the session list, and `Read N of M`. Under it, each session not read and each read in part, by number and title, with the reason.
- **Patterns**: one card per pattern, most costly first, numbered from 1. Each card:
  - Title: the fix, short ("Add a check for unpushed worktrees").
  - Badges: the kind of finding, and strength: `Strong` (three or more sessions, or a costly moment), `Worth exploring` (two sessions), `Speculative` (the fix guess is the reader's, not seen in the repo).
  - Sessions: the numbers and dates of the sessions it came from.
  - Quotes: one blockquote per moment, each with its session number and `Where`.
  - Fix: one sentence. Where: the file it changes and the skill that owns it, as SKILL.md § Kinds of finding names.
  - A checkbox, not ticked.
- **One-time problems**: smaller cards after the patterns, numbered on from the last pattern, same parts, badge `One-time`.
- **Top pick**: one larger card at the end: the card number, its title, why it goes first in one sentence, and an anchor link to it.
- `MODE = "pick"`.

Style: plain, editorial, generous white space. One accent color; amber for `Worth exploring`, slate for `Speculative`. Quotes in a monospace font. No other interaction than the checkboxes and the Copy bar.
