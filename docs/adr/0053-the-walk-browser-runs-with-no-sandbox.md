# The walk browser runs with no Chromium sandbox

`walk-browser.cjs` starts Playwright's Chromium with `--no-sandbox`. Chromium's own sandbox cannot start in a proofbox Sandbox: without the flag, Chromium stops with `No usable sandbox!`.

The browser runs inside a throwaway proofbox Sandbox and opens only the app under test, so the proofbox Sandbox is the line between the page and the host.
