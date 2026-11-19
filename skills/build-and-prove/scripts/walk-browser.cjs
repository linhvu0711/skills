#!/usr/bin/env node
// walk-browser: the browser a walk films, on the repo's own Playwright.
//
//   walk-browser <url> [--viewport-size=<w>,<h>] [--storage <file>] [--clock <time>] [--log <file>]
//
// It opens Playwright's Chromium, headed, on a new, empty profile at the page
// size (1440,795 by default), with the saved login of --storage and a fixed
// clock at --clock, then waits until the browser closes. It appends one line
// per page error and failed request to the log, /tmp/walk-browser.log by
// default, which `box.sh close --out` copies next to the video:
//
//   error: <console error text> · <its location url>
//   error: Uncaught <name>: <message> · <page url>
//   request: <status> <url>             (a status of 400 or more)
//   request: <errorText> <url>          (a request that failed)
//
// It hides what is not the app's: /favicon.ico, which Chromium asks for on
// its own, and net::ERR_ABORTED, a request the page itself cancelled as it
// moved on. A Playwright `open` logs none of this, hence this starter.
//
// It cannot start: one `stop: <why>` line in the log and exit 1, so the
// walker fails the walk with the cause. Each line is appended at once, so the
// TERM of `box.sh close` loses none.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const usage = 'usage: walk-browser <url> [--viewport-size=<w>,<h>] [--storage <file>] [--clock <time>] [--log <file>]';
const opts = { size: '1440,795', storage: undefined, clock: undefined, log: '/tmp/walk-browser.log' };
const flags = { '--viewport-size': 'size', '--storage': 'storage', '--clock': 'clock', '--log': 'log' };

const oneLine = (text) => String(text).replace(/\s*\n\s*/g, ' ');
const write = (line) => fs.appendFileSync(opts.log, `${oneLine(line)}\n`);
const stop = (why) => {
  write(`stop: ${why}`);
  process.exit(1);
};

let url;
let bad = false;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  const [flag, inline] = args[i].split(/=(.*)/s, 2);
  if (flag in flags) {
    const value = inline !== undefined ? inline : args[++i];
    if (value === undefined) bad = true;
    else opts[flags[flag]] = value;
  } else if (url === undefined && !args[i].startsWith('--')) {
    url = args[i];
  } else {
    bad = true;
  }
}
const size = /^(\d+),(\d+)$/.exec(opts.size);
if (bad || url === undefined || !size) stop(usage);
const viewport = { width: Number(size[1]), height: Number(size[2]) };

// The repo's own Playwright, or one the setup script put on NODE_PATH.
function loadPlaywright() {
  const req = createRequire(path.join(process.cwd(), 'x.js'));
  for (const name of ['playwright', '@playwright/test']) {
    try {
      return req(name);
    } catch (err) {
      if (err.code !== 'MODULE_NOT_FOUND' || !String(err.message).includes(`'${name}'`)) throw err;
    }
  }
  stop(`no Playwright in ${process.cwd()}: the setup script installs it`);
}

const hidden = (u) => {
  try {
    return new URL(u).pathname === '/favicon.ico';
  } catch {
    return false;
  }
};

// Playwright also gives the first page as a context `page` event, so each
// page is watched once.
const watched = new WeakSet();
function watch(page) {
  if (watched.has(page)) return;
  watched.add(page);
  page.on('console', (m) => {
    const at = (m.location() || {}).url || page.url();
    if (m.type() === 'error' && !hidden(at)) write(`error: ${m.text()} · ${at}`);
  });
  page.on('pageerror', (e) => write(`error: Uncaught ${e.name}: ${e.message} · ${page.url()}`));
  page.on('response', (r) => {
    if (r.status() >= 400 && !hidden(r.url())) write(`request: ${r.status()} ${r.url()}`);
  });
  page.on('requestfailed', (r) => {
    const why = (r.failure() || {}).errorText || 'failed';
    if (why !== 'net::ERR_ABORTED' && !hidden(r.url())) write(`request: ${why} ${r.url()}`);
  });
}

async function main() {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ headless: false, args: ['--no-sandbox'] });
  const closed = new Promise((resolve) => browser.on('disconnected', resolve));
  const context = await browser.newContext({ viewport, storageState: opts.storage });
  if (opts.clock !== undefined) {
    if (!context.clock) stop('this Playwright has no clock: use 1.45 or newer');
    await context.clock.install({ time: opts.clock });
  }
  context.on('page', watch);
  const page = await context.newPage();
  watch(page);
  await page.goto(url);
  await closed;
}

main().catch((err) => stop(String((err && err.message) || err).split('\n')[0]));
