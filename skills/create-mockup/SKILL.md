---
name: create-mockup
description: "Build a clickable, final-fidelity HTML mock of an agreed UI change inside the app's real shell, with a floating state panel, and open it in the browser for review."
disable-model-invocation: true
argument-hint: "[feature or page]"
---

# Mockup

One interactive HTML page: the agreed feature, page, or revamp at final fidelity, inside the app's real shell, every in-scope control working, plus a floating **state panel** that flips each component through its states. The user reviews it and asks for changes until satisfied. Every change updates the same file and local URL.

## 1. Scope contract

Read the conversation and create `${CODEX_HOME:-$HOME/.codex}/artifacts/mockup/<slug>/`, then write `scope.md` there: screens, components, actions, and the states of each (loaded, loading, empty, error, disabled, invalid, submitting), plus the global ones the app has (toast, theme, role). Each line is one thing the user can click or see. "Billing page" is an intent; "plan card with an Upgrade button that opens a confirm dialog" is a line. Done when every line is concrete. When the conversation gives only an intent, stop, list what is missing, and name `/grill` as the way to settle it. Keep generated artifacts outside the repository unless the user asks for a repository path.

## 2. Visual truth

**Existing app.** Start with `DESIGN.md` and `PRODUCT.md` when the repo has them. They hold the settled tokens and product context, so copy from them first and read the code only for what they leave out. When they disagree with the code, the shipped code is the truth. Then read the real files and copy values, not impressions:

- Shell: root layout, sidebar, header, nav labels in order, active-item style, content width and padding.
- Tokens: colors, font family and scale, radius, shadows, spacing. Usually the tailwind config, `globals.css`, or a theme file.
- Primitives the scope uses: button, input, select, dropdown, tabs, table, dialog, toast, skeleton or spinner, empty state, error banner. Copy the app's own version of each, including its copy tone.
- Icons: the app's icon set, as inline SVG paths.
- Theme: both when the app ships both. Responsive: only when the app is. Roles: a role row when the app renders differently per role.

Write the findings to `tokens.md` next to `scope.md`. Nothing is written into the repo.

**From scratch.** No incumbent. Load `impeccable`, choose a direction from its relevant design guidance, and record it in `tokens.md`.

## 3. Build

Use `impeccable` for the visual implementation, then write one file at `${CODEX_HOME:-$HOME/.codex}/artifacts/mockup/<slug>/<slug>.html`. Keep that path for the life of the mock so follow-up changes update the same page.

- The real shell wraps the feature. Out-of-scope shell areas are present with real labels and stay static.
- Every scope line works: a dropdown opens and choosing changes what is shown; tabs switch; a form validates in the app's error style; a dialog opens, closes, and closes on Esc; a toast appears and dismisses; the active nav item is right; hover, focus, and disabled are styled.
- Data looks real: domain names, plausible numbers, the app's date and currency format.
- A multi-screen flow is one page with in-page screens, switched by the app's own navigation.
- State panel: inline `state-panel.js` (sibling of this file) in a `<script>` and init it with one row per scope line that has more than one state, plus the global rows. Rendering reads from the panel state. In-app actions that change a state call `StatePanel.set`, so the panel stays true.
- Keep the HTML self-contained. Inline local CSS, JavaScript, and SVG assets; use a remote CDN only when it is necessary and safe for the user's environment.

## 4. Verify

Serve the mockup directory on `127.0.0.1` (`python3 -m http.server 8765 --bind 127.0.0.1`) and open the page with the browser tools (Playwright in Claude Code, the in-app browser in Codex); `file://` is not the review path. If port 8765 is occupied, choose another available port without stopping the existing process. That browser is the agent's, not the user's: once the checks below pass, open the page in the user's own browser too, `open "<url>"` on macOS, `xdg-open "<url>"` on Linux, and again after every rebuild. Playwright in Claude Code writes `.playwright-mcp/` into the working directory; delete it when the check is done. Walk `scope.md` line by line: click it, flip its panel row through every option, read the console. Screenshot desktop, and mobile when the app is responsive. Fix everything in one batch, confirm with at most one more round. Done when every scope line and every panel option has been exercised with zero console errors. No browser tools: walk `scope.md` against the HTML statically, one render branch per panel row.

## 5. Deliver and iterate

Open `http://127.0.0.1:<port>/<slug>.html` in the browser and leave the finished page visible for the user. Copy the local URL to the clipboard when `pbcopy` exists. Reply with the local URL, the HTML file path, `scope.md` as a checklist, what data is fake, what is out of scope, and that the backtick key hides the panel.

On each change request, edit the same file, re-verify only the changed lines, reload the same local URL, and copy it again when `pbcopy` exists. A later session continues from the same file path. To publish the finished mock as a Claude artifact, run `/to-artifact <path>`.

**Headless host** (`command -v open xdg-open` finds neither): there is no browser to leave the page in. Skip the local URL. Publish the page with the `to-artifact` skill and reply with the artifact link in place of the URL. A change request republishes to the same artifact. Publish fails: say why, give the HTML file path, stop.
