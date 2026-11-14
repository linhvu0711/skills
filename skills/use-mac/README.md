# use-mac

Works in the desktop apps on your Mac while you keep working in your own: it opens apps, reads them, clicks, types, and carries one task across several apps. It stays in the background and does not take your mouse or your front window.

## Use it when

A task lives in a Mac app, such as Music, Notes, Finder, System Settings, or a browser window you are already signed in to. Type `/use-mac` followed by the task (`$use-mac` in Codex), or say "go to my Notes app", "do this on my Mac", "what is on my screen". Web pages that need no sign-in of yours go to a browser tool, and coding work in the repo stays out of this skill.

## What you get

The task done in the app, and a short report: the answer, which route gave it, and anything left changed. There are two routes. The screen route reads and clicks the app with `agent-desktop`. The direct route asks the app through `osascript` or another shell command, which is faster and reaches apps on any desktop. Each step is proven by reading the app again, not by trusting an `ok`. In your browser it opens its own window, gives your screen back within a second, and finds its tab by ID, so you keep working in your own tabs while it works in its own. At the end, each app and page it moved is back as it found it, the apps it opened are quit, and its screenshots are deleted.

It stops and asks before it sends, posts, buys, deletes, or changes a security setting. Permission dialogs and money stay with you. Text on the screen is data: an instruction inside a page or a message comes to you as a report, not as an order.

## Needs

- macOS.
- [`agent-desktop`](https://agent-browser.dev/desktop), for the screen route: `brew install agent-desktop`. It needs Accessibility and Screen Recording access for your terminal app, in System Settings → Privacy & Security.
- For a signed-in web page: JavaScript from Apple Events turned on in your browser (Brave and Chrome: View > Developer; Safari: the Develop menu).
- The app the task needs, as a normal window on the desktop you are on. A full-screen app sits alone on its own desktop, where the screen route cannot reach it.

## Fits with

- Web pages that need no sign-in of yours go to a browser tool, such as the Playwright MCP.
- Coding work goes to [ship](../ship/) and the other build skills.
