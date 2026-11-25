# create-diagram

Draws a diagram of your code as an interactive HTML page, built only from facts it finds in the code, and opens it in your browser.

## Use it when

You want to see how something fits together: "diagram the checkout flow", "map how auth works", "draw the data model for orders", "what will this look like after the refactor?". `/create-diagram`, or just ask. It picks the type from your question: flowchart, sequence, state machine, class, ERD, data flow, component, deployment, C4, use case, activity, UI component tree, or dependency graph.

## What you get

One page that answers one question. Before the page opens, a check reads its data and names each arrow or step that points at a box that is not there, each box or step with no label, each id used twice or left out, and a diagram with more boxes than its type allows. You can pan, zoom, and search it, and clicking a box shows the `file:line` it came from. The reply names the question, how to read the picture, and what the code showed that you should know, for example:

```
Type: sequence · Question: What happens when a shopper checks out? · Scope: shop-api · Mode: current
Findings: inventory-svc is called twice per order, once by cart and once by payment.
```

Ask about a planned change and the page gets a switch between the current code, the planned code, and a diff of the two. The page lives under `~/.codex/artifacts/diagram/` (or `$CODEX_HOME` when set), outside your repo.

## Needs

- A browser, and `open` (macOS) or `xdg-open` (Linux).
- `python3`, for the data check.
- A way to serve a folder on `127.0.0.1`, such as `python3 -m http.server`.
- Optional: a hidden browser the agent can drive, playwright-cli run by `npx @playwright/cli` or your harness's own, per `../../shared/harness.md`, so the agent can check the page itself. Ask to watch and it opens a window. Also the `impeccable` skill to match your design system.
- On a machine with no browser, the `to-artifact` skill, which publishes the page instead.

## Fits with

- [discover-path](../discover-path/) suggests this skill when a question is about how code is built.

## Credits

Thanks to [humanlayer/skills](https://github.com/humanlayer/skills) for the `show-me` skill, which gave us the idea (MIT license). No text was copied.
