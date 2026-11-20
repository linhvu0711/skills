# walk-browser.sh: the cases for this skill's browser starter, run by node on
# a fake Playwright. The repo's test.sh sources this file after test-lib.sh and
# runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# fake_playwright <mode>: a repo at $T/app whose node_modules holds a fake
# `playwright`. Its page, on goto, writes the options it got to
# $FAKE_PW_OPTS when that is set, then acts by mode: `events` emits one of
# each page event the starter logs or skips, `quiet` emits none, and both then
# close the browser; `nolaunch` makes chromium.launch throw.
fake_playwright() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/app/node_modules/playwright"
  export FAKE_PW_MODE="$1" FAKE_PW_OPTS="$T/opts.json"
  cat > "$T/app/node_modules/playwright/index.js" <<'EOF'
const fs = require('node:fs');
const { EventEmitter } = require('node:events');
const mode = process.env.FAKE_PW_MODE;
const got = {};
const msg = (type, text, url) => ({ type: () => type, text: () => text, location: () => ({ url }) });
const res = (status, url) => ({ status: () => status, url: () => url });
const req = (errorText, url) => ({ failure: () => ({ errorText }), url: () => url });
exports.chromium = {
  async launch(opts) {
    if (mode === 'nolaunch') {
      throw new Error("browserType.launch: Executable doesn't exist at /tmp/pb/ms-playwright/chrome\nRun npx playwright install");
    }
    got.launch = opts;
    const browser = new EventEmitter();
    browser.newContext = async (copts) => {
      got.context = copts;
      const context = new EventEmitter();
      context.clock = { install: async ({ time }) => { got.clock = time; } };
      context.newPage = async () => {
        const page = new EventEmitter();
        page.url = () => 'http://localhost:3000/';
        page.goto = async (url) => {
          got.goto = url;
          if (process.env.FAKE_PW_OPTS) fs.writeFileSync(process.env.FAKE_PW_OPTS, JSON.stringify(got));
          if (mode === 'events') {
            page.emit('console', msg('error', 'boom', 'http://localhost:3000/app.js'));
            page.emit('console', msg('log', 'hi', 'http://localhost:3000/app.js'));
            page.emit('pageerror', new TypeError('x is undefined'));
            page.emit('response', res(200, 'http://localhost:3000/'));
            page.emit('response', res(500, 'http://localhost:3000/api/wishes'));
            page.emit('response', res(404, 'http://localhost:3000/favicon.ico'));
            page.emit('requestfailed', req('net::ERR_ABORTED', 'http://localhost:3000/api/next'));
            page.emit('requestfailed', req('net::ERR_CONNECTION_REFUSED', 'http://localhost:4000/feed'));
          }
          setImmediate(() => browser.emit('disconnected'));
        };
        return page;
      };
      return context;
    };
    return browser;
  },
};
EOF
}

t_walk_browser_logs() {
  # Given
  fake_playwright events
  cd "$T/app"
  # When
  run node "$here/../scripts/walk-browser.cjs" http://localhost:3000/ --log "$T/walk.log"
  # Then
  eq exit 0 "$code"
  eq log "error: boom · http://localhost:3000/app.js
error: Uncaught TypeError: x is undefined · http://localhost:3000/
request: 500 http://localhost:3000/api/wishes
request: net::ERR_CONNECTION_REFUSED http://localhost:4000/feed" "$(cat "$T/walk.log")"
}

t_walk_browser_options() {
  # Given
  fake_playwright quiet
  cd "$T/app"
  # When
  run node "$here/../scripts/walk-browser.cjs" http://localhost:3000/ --viewport-size=390,664 \
    --storage /tmp/login.json --clock 2026-01-02T09:00:00Z --log "$T/walk.log"
  # Then
  eq exit 0 "$code"
  eq options '{"launch":{"headless":false,"args":["--no-sandbox"]},"context":{"viewport":{"width":390,"height":664},"storageState":"/tmp/login.json"},"clock":"2026-01-02T09:00:00Z","goto":"http://localhost:3000/"}' "$(cat "$T/opts.json")"
}

t_walk_browser_clean_page() {
  # Given
  fake_playwright quiet
  cd "$T/app"
  # When
  run node "$here/../scripts/walk-browser.cjs" http://localhost:3000/ --log "$T/walk.log"
  # Then
  eq exit 0 "$code"
  [ -f "$T/walk.log" ] || eq log "an empty file" "no file"
  eq log "" "$(cat "$T/walk.log")"
}

t_walk_browser_no_playwright() {
  # Given
  T="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$T/app"; cd "$T/app"
  export NODE_PATH=""
  # When
  run node "$here/../scripts/walk-browser.cjs" http://localhost:3000/ --log "$T/walk.log"
  # Then
  eq exit 1 "$code"
  eq log "stop: no Playwright in $T/app: the setup script installs it" "$(cat "$T/walk.log")"
}

t_walk_browser_no_launch() {
  # Given
  fake_playwright nolaunch
  cd "$T/app"
  # When
  run node "$here/../scripts/walk-browser.cjs" http://localhost:3000/ --log "$T/walk.log"
  # Then
  eq exit 1 "$code"
  eq log "stop: browserType.launch: Executable doesn't exist at /tmp/pb/ms-playwright/chrome" "$(cat "$T/walk.log")"
}

cases=(
  "logs the page's errors and failed requests|t_walk_browser_logs"
  "opens the page at the size, login, and clock it is given|t_walk_browser_options"
  "leaves an empty log when the page logs nothing|t_walk_browser_clean_page"
  "stops with a line when the repo has no Playwright|t_walk_browser_no_playwright"
  "stops with a line when the browser will not start|t_walk_browser_no_launch"
)
