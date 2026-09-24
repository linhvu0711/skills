---
name: create-diagram
description: "Draw a code or architecture diagram as an interactive HTML page, built from facts found in the code, and open it in the browser for review. Use when the user asks to diagram, draw, map, or visualize how a feature, module, system, app, data model, request, or deployment works or fits together, or asks how the code will look after a planned change. Covers flowchart, sequence, state machine, class, ERD, data flow, component, deployment, C4, use case, activity, UI component tree, and dependency graph."
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

One page answers one question. The page is `assets/shell.html`: it draws nodes, edges, and groups from a `DATA` object and gives the reader pan, zoom, search, a detail panel with file paths, and a current/planned switch. The work is choosing the type, gathering facts from the code, and laying them out.

## 1. Frame

Write one line before anything else:

`Type: <type> · Question: <one sentence> · Scope: <feature, module, or system> · Mode: current | planned`

- Type comes from the table in `references/catalog.md`. Two types when the question has a structure half and a behavior half; never more.
- Mode is planned when the chat holds a plan or proposal, or the ask says "if we", "after", "with the new". Otherwise current.

Done when the line is written and `references/types/<type>.md` is loaded.

## 2. Gather

Collect facts with read-only explorer agents when the repository instructions require or authorize delegation. Give each agent one narrow question, the "Facts to collect" list from the type card, the scope, and this return shape: one line per node (`id · label · kind · path:line · note`) and one per edge (`from → to · verb · path:line`). Every fact points at a file. A fact with no file stays out. Gather directly when delegation is unavailable or unnecessary.

Planned mode: read the plan and mark what it adds, removes, or changes. Rules in `references/change-mode.md`.

Done when every node has a path, every edge has a verb, and the list fits the node budget on the type card. Over budget: cut by the catalog's order (single-edge nodes, then collapse a cluster, then split into two pages).

## 3. Lay out

Give each node grid coordinates by the layout rule on the type card. Flows read left to right; hierarchies and stacks read top to bottom. Siblings share a row or a column. An empty cell separates clusters.

Done when no two nodes share a cell and every edge crosses at most one other edge. Move nodes until that holds.

## 4. Build

1. Create `${CODEX_HOME:-$HOME/.codex}/artifacts/diagram/` when needed, then copy `assets/shell.html` there as `diagram-<slug>.html`. Keep generated artifacts outside the repository unless the user asks for a repository path.
2. Replace `const DATA = {};` with the object. Schema and a worked example: `references/page.md`.
3. Fill `title` (a product name), `question`, `scope` (repo · branch · commit · date), 2 to 4 `guide` lines, and `findings` for what the code showed that the user should know: cycles, dead paths, writes that bypass the machine, plan gaps.
4. When the project has a design system (tokens, theme file, `AGENTS.md` or `CLAUDE.md`), move the shell's `:root` tokens onto it; otherwise keep the shell unchanged. Use `impeccable` only when adapting the visual design, and only if it is installed.
5. Serve the artifact directory on `127.0.0.1` and open the page with the browser tools (Playwright in Claude Code, the in-app browser in Codex); `file://` is not the review path. Inspect it once, fix what the rendered page shows. That browser is the agent's, not the user's, so then open the finished page in the user's own browser: `open "<url>"` on macOS, `xdg-open "<url>"` on Linux, again after every rebuild. Playwright in Claude Code writes `.playwright-mcp/` into the working directory; delete it when the check is done. No browser tools: check the `DATA` object against `references/page.md` and the rendered node list statically, then `open` the page.

Done when the page shows every node in the fact list with its path in the panel.

## 5. Deliver and reply

Open `http://127.0.0.1:<port>/diagram-<slug>.html` in the browser and keep the local server running for follow-up changes. If port 8765 is occupied, choose another available port without stopping the existing process. Reply with the local URL, the HTML file path, the frame line, the guide lines, and the findings. The page carries the rest. To publish it as a Claude artifact, run `/to-artifact <path>`.

**Headless host** (`command -v open xdg-open` finds neither): there is no browser to leave the page in. Skip the local URL. Publish the page with the `to-artifact` skill and reply with the artifact link in place of the URL. A change request republishes to the same artifact. Publish fails: say why, give the HTML file path, stop.
