/* StatePanel - floating, draggable, collapsible control panel for mock states.
 * Inline this whole file in a <script> tag inside the mock (artifacts cannot load local scripts).
 *
 * Usage:
 *   StatePanel.init({
 *     rows: [
 *       { id: 'table', label: 'Table',  options: ['loaded', 'loading', 'empty', 'error'] },
 *       { id: 'toast', label: 'Toast',  options: ['none', 'success', 'error'] },
 *       { id: 'theme', label: 'Theme',  options: ['light', 'dark'], value: 'dark' },
 *     ],
 *     onChange(state, changedId) { render(state) },   // called once at init and after every change
 *   })
 *   StatePanel.set('toast', 'success')   // the mock can drive a row (e.g. after a Save click)
 *   StatePanel.get()                     // { table: 'loaded', toast: 'none', theme: 'dark' }
 *
 * Every row is independent. First option is the default unless `value` is given.
 * Drag by the header. Collapse button folds it to a pill. Reset restores defaults.
 * Backtick (`) hides/shows the panel so it stays out of screenshots.
 */
window.StatePanel = (function () {
  var KEY = 'mockup-state-panel'
  var rows = [], state = {}, defaults = {}, onChange = function () {}
  var root, body, pill, hidden = false, collapsed = false

  var css = [
    '#sp-root{position:fixed;top:16px;right:16px;z-index:2147483000;width:280px;max-height:calc(100vh - 32px);',
    'display:flex;flex-direction:column;background:#1c1c1e;color:#f2f2f2;border:1px solid #3a3a3c;border-radius:10px;',
    'box-shadow:0 8px 24px rgba(0,0,0,.35);font:12px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;',
    'user-select:none;-webkit-user-select:none;overflow:hidden}',
    '#sp-root *{box-sizing:border-box;font:inherit;color:inherit}',
    '#sp-head{display:flex;align-items:center;gap:8px;padding:8px 10px;background:#2c2c2e;cursor:grab;border-bottom:1px solid #3a3a3c}',
    '#sp-head.sp-dragging{cursor:grabbing}',
    '#sp-title{flex:1;font-weight:600;letter-spacing:.02em}',
    '#sp-head button{background:#3a3a3c;border:0;border-radius:6px;padding:3px 8px;cursor:pointer;line-height:1.2}',
    '#sp-head button:hover{background:#48484a}',
    '#sp-body{overflow:auto;padding:8px 10px 10px}',
    '.sp-row{margin:0 0 8px}.sp-row:last-child{margin:0}',
    '.sp-label{display:block;margin:0 0 4px;color:#a1a1a6;font-size:11px;text-transform:uppercase;letter-spacing:.06em}',
    '.sp-opts{display:flex;flex-wrap:wrap;gap:4px}',
    '.sp-opt{background:#2c2c2e;border:1px solid #3a3a3c;border-radius:6px;padding:3px 8px;cursor:pointer}',
    '.sp-opt:hover{background:#3a3a3c}',
    '.sp-opt.sp-on{background:#0a84ff;border-color:#0a84ff;color:#fff}',
    '#sp-root.sp-collapsed{width:auto}#sp-root.sp-collapsed #sp-body{display:none}',
    '#sp-root.sp-collapsed #sp-head{border-bottom:0}#sp-root.sp-collapsed #sp-reset{display:none}',
    '#sp-root.sp-hidden{display:none}',
  ].join('')

  function h(tag, attrs, children) {
    var el = document.createElement(tag)
    for (var k in attrs || {}) {
      if (k === 'text') el.textContent = attrs[k]
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), attrs[k])
      else el.setAttribute(k, attrs[k])
    }
    ;(children || []).forEach(function (c) { el.appendChild(c) })
    return el
  }

  function load() { try { return JSON.parse(localStorage.getItem(KEY) || '{}') } catch (e) { return {} } }
  function save(patch) {
    try {
      var cur = load(); for (var k in patch) cur[k] = patch[k]
      localStorage.setItem(KEY, JSON.stringify(cur))
    } catch (e) {}
  }

  function renderRows() {
    body.innerHTML = ''
    rows.forEach(function (row) {
      var opts = row.options.map(function (opt) {
        return h('button', {
          class: 'sp-opt' + (state[row.id] === opt ? ' sp-on' : ''),
          type: 'button',
          text: opt,
          onclick: function () { set(row.id, opt) },
        })
      })
      body.appendChild(h('div', { class: 'sp-row' }, [
        h('span', { class: 'sp-label', text: row.label || row.id }),
        h('div', { class: 'sp-opts' }, opts),
      ]))
    })
    pill.textContent = collapsed ? '\u25B8' : '\u25BE'
  }

  function set(id, value, silent) {
    if (!(id in state) || state[id] === value) return
    state[id] = value
    renderRows()
    if (!silent) onChange(get(), id)
  }

  function get() { var out = {}; for (var k in state) out[k] = state[k]; return out }

  function reset() {
    var changed = false
    for (var k in defaults) if (state[k] !== defaults[k]) { state[k] = defaults[k]; changed = true }
    renderRows()
    if (changed) onChange(get(), null)
  }

  function setCollapsed(v) { collapsed = v; root.classList.toggle('sp-collapsed', v); save({ collapsed: v }); renderRows() }
  function setHidden(v) { hidden = v; root.classList.toggle('sp-hidden', v) }

  function clamp() {
    var r = root.getBoundingClientRect()
    var x = Math.min(Math.max(0, r.left), Math.max(0, window.innerWidth - r.width))
    var y = Math.min(Math.max(0, r.top), Math.max(0, window.innerHeight - r.height))
    root.style.left = x + 'px'; root.style.top = y + 'px'; root.style.right = 'auto'
    return { x: x, y: y }
  }

  function drag(head) {
    var sx, sy, ox, oy, moving = false
    head.addEventListener('pointerdown', function (e) {
      if (e.target.tagName === 'BUTTON') return
      var r = root.getBoundingClientRect()
      sx = e.clientX; sy = e.clientY; ox = r.left; oy = r.top; moving = true
      root.style.left = ox + 'px'; root.style.top = oy + 'px'; root.style.right = 'auto'
      head.classList.add('sp-dragging')
      head.setPointerCapture(e.pointerId)
    })
    head.addEventListener('pointermove', function (e) {
      if (!moving) return
      root.style.left = (ox + e.clientX - sx) + 'px'
      root.style.top = (oy + e.clientY - sy) + 'px'
    })
    function end(e) {
      if (!moving) return
      moving = false
      head.classList.remove('sp-dragging')
      try { head.releasePointerCapture(e.pointerId) } catch (_) {}
      save(clamp())
    }
    head.addEventListener('pointerup', end)
    head.addEventListener('pointercancel', end)
  }

  function init(cfg) {
    rows = cfg.rows || []
    onChange = cfg.onChange || onChange
    state = {}; defaults = {}
    rows.forEach(function (r) { defaults[r.id] = state[r.id] = ('value' in r) ? r.value : r.options[0] })

    document.head.appendChild(h('style', { text: css }))
    pill = h('button', { type: 'button', title: 'Collapse / expand', onclick: function () { setCollapsed(!collapsed) } })
    var head = h('div', { id: 'sp-head' }, [
      h('span', { id: 'sp-title', text: cfg.title || 'States' }),
      h('button', { id: 'sp-reset', type: 'button', text: 'Reset', onclick: reset }),
      pill,
    ])
    body = h('div', { id: 'sp-body' })
    root = h('div', { id: 'sp-root' }, [head, body])
    document.body.appendChild(root)

    var saved = load()
    if (typeof saved.x === 'number') { root.style.left = saved.x + 'px'; root.style.top = saved.y + 'px'; root.style.right = 'auto' }
    collapsed = !!saved.collapsed
    root.classList.toggle('sp-collapsed', collapsed)
    drag(head)
    window.addEventListener('resize', clamp)
    document.addEventListener('keydown', function (e) {
      if (e.key === '`' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)) setHidden(!hidden)
    })
    renderRows()
    clamp()
    onChange(get(), null)
  }

  return { init: init, set: set, get: get, reset: reset, hide: function () { setHidden(true) }, show: function () { setHidden(false) } }
})()
