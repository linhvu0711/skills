# create-mockup

Builds a clickable HTML mock of a UI change, inside your app's real shell and at final look, so you can review it before anyone writes the real code.

## Use it when

You've agreed on a UI change and want to see and click it first. It only runs when you call it: `/create-mockup billing page` in Claude Code, `$create-mockup ...` in Codex.

If all you have is an intent ("a better billing page"), it stops and lists what it still needs to know. Settle that with [grill](../grill/) first.

## What you get

- One self-contained HTML page, opened in your browser at a local URL. Every control in scope works: dropdowns, tabs, dialogs, form errors, toasts.
- A floating state panel that flips each part through its states (loading, empty, error, disabled...). The backtick key hides it.
- `scope.md`, the checklist of what the mock covers, and `tokens.md`, the colors, fonts, and spacing it copied from your app.

Everything lives under `~/.codex/artifacts/mockup/<slug>/` (or `$CODEX_HOME` when set), outside your repo. Ask for a change and the same file and URL update.

## Needs

- `python3`, to serve the page on `127.0.0.1`.
- A browser, and `open` (macOS) or `xdg-open` (Linux).
- Optional: Playwright MCP in Claude Code (or the Codex in-app browser) so the agent can click through the mock itself; `pbcopy` to copy the URL; the `impeccable` skill for the visual design.
- On a machine with no browser, the `to-artifact` skill, which publishes the page instead.

## Fits with

- [grill](../grill/) settles the scope when the conversation holds only an intent.
- [discover-path](../discover-path/) suggests this skill when the open question is about UI.
