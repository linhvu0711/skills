// page.cjs <page.html> <board.json>: runs the board page's script in node on
// a fake page and a fake fetch, so a test checks what the page fetches and
// draws, not its source text. The fake fetch answers board.json with the
// file's text and any other name with 404. After the first read settles, it
// prints one JSON line: {fetched, banner, hdot}.
'use strict'
const fs = require('fs')
const vm = require('vm')

const [page, board] = process.argv.slice(2)
const html = fs.readFileSync(page, 'utf8')
const script = html.slice(html.indexOf('<script>') + '<script>'.length, html.lastIndexOf('</script>'))

function element() {
  const classes = new Set()
  const attrs = {}
  return {
    textContent: '', innerHTML: '', className: '', style: {}, disabled: false,
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      toggle: (c, on) => ((on === undefined ? !classes.has(c) : on) ? classes.add(c) : classes.delete(c)),
      contains: (c) => classes.has(c),
    },
    setAttribute: (k, v) => { attrs[k] = String(v) },
    getAttribute: (k) => (k in attrs ? attrs[k] : null),
    focus: () => {},
  }
}

const els = {}
const document = {
  body: element(),
  activeElement: null,
  title: '',
  getElementById: (id) => els[id] || (els[id] = element()),
  querySelectorAll: () => [],
  querySelector: () => null,
  addEventListener: () => {},
}
const fetched = []
function fetch(name) {
  fetched.push(name)
  if (name === 'board.json') {
    const text = fs.readFileSync(board, 'utf8')
    return Promise.resolve({ status: 200, ok: true, text: () => Promise.resolve(text) })
  }
  return Promise.resolve({ status: 404, ok: false, text: () => Promise.resolve('') })
}

vm.runInNewContext(script, { document, fetch, setInterval: () => 0, console })
setTimeout(() => {
  const get = (id) => els[id] || element()
  process.stdout.write(JSON.stringify({ fetched, banner: get('banner').innerHTML, hdot: get('hdot').className }) + '\n')
}, 50)
