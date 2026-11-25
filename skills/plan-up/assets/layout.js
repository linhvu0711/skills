// layout.js: where the plan page draws each Change map box, flow, and label.
// No page calls: build-page.py puts this file into the page, and the node
// tests in tests/layout.sh run it alone.
const PlanLayout = (() => {
  'use strict';
  const SIGN = { new: '+ ', removed: '− ' };
  const CW = 330, RH = 130, NW = 190, NH = 56, PAD = 34;
  const boxRect = (q, m) => ({ x1: q.cx - q.w / 2 - m, y1: q.cy - q.h / 2 - m, x2: q.cx + q.w / 2 + m, y2: q.cy + q.h / 2 + m });
  const overlap = (r, s) => Math.max(0, Math.min(r.x2, s.x2) - Math.max(r.x1, s.x1)) * Math.max(0, Math.min(r.y2, s.y2) - Math.max(r.y1, s.y1));
  const OFFSETS = [0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180, -180, 220, -220];
  const SPOTS = [0.5, 0.45, 0.55, 0.4, 0.6, 0.35, 0.65, 0.3, 0.7, 0.25, 0.75, 0.2, 0.8, 0.15, 0.85];

  // A map's boxes, group areas, flow paths, and labels. `textWidth(text, font)`
  // measures text as the page draws it.
  function map(m, textWidth) {
    const parts = m.parts || [], flows = m.flows || [];
    const W = (Math.max(0, ...parts.map((p) => p.x)) + 1) * CW + PAD * 2;
    const H = (Math.max(0, ...parts.map((p) => p.y)) + 1) * RH + PAD;
    const pos = {};
    for (const p of parts) pos[p.ref] = { cx: PAD + p.x * CW + CW / 2, cy: PAD / 2 + p.y * RH + RH / 2, w: NW, h: NH };
    // What a flow must keep clear of: every box, and every group title.
    const walls = parts.map((p) => ({ ref: p.ref, ...boxRect(pos[p.ref], 6) }));
    const byGroup = {};
    for (const p of parts) if (p.group) (byGroup[p.group] = byGroup[p.group] || []).push(pos[p.ref]);
    const groups = [];
    for (const [name, ps] of Object.entries(byGroup)) {
      const x1 = Math.min(...ps.map((q) => q.cx - q.w / 2)) - 14, x2 = Math.max(...ps.map((q) => q.cx + q.w / 2)) + 14;
      const y1 = Math.min(...ps.map((q) => q.cy - q.h / 2)) - 30, y2 = Math.max(...ps.map((q) => q.cy + q.h / 2)) + 14;
      const text = name.toUpperCase();
      const box = { x1: x1 + 8, y1: y1 + 4, x2: x1 + 16 + textWidth(text, '650 12px') + text.length * 0.48, y2: y1 + 26 };
      walls.push(box);
      groups.push({ name, x1, y1, x2, y2, title: { text, x: x1 + 12, y: y1 + 19, box } });
    }
    const clip = (q, tx, ty) => {
      const dx = tx - q.cx, dy = ty - q.cy;
      const k = Math.min(Math.abs((q.w / 2 + 4) / (dx || 1e-9)), Math.abs((q.h / 2 + 4) / (dy || 1e-9)));
      return [q.cx + dx * k, q.cy + dy * k];
    };
    const curve = (a, b, qx, qy) => {
      const [x1, y1] = clip(a, qx, qy), [x2, y2] = clip(b, qx, qy);
      const at = (t) => [(1 - t) ** 2 * x1 + 2 * (1 - t) * t * qx + t * t * x2, (1 - t) ** 2 * y1 + 2 * (1 - t) * t * qy + t * t * y2];
      return { d: `M${x1},${y1} Q${qx},${qy} ${x2},${y2}`, at, n: Math.ceil((Math.hypot(x2 - x1, y2 - y1) + Math.hypot(qx - (x1 + x2) / 2, qy - (y1 + y2) / 2)) / 6) };
    };
    // How much of a path runs through a wall or off the map; the flow's own two boxes do not count.
    const blocked = (c, f) => {
      let n = 0;
      for (let i = 1; i < c.n; i++) {
        const [x, y] = c.at(i / c.n);
        if (x < 0 || y < 0 || x > W || y > H) n++;
        for (const r of walls) if (r.ref !== f.from && r.ref !== f.to && x > r.x1 && x < r.x2 && y > r.y1 && y < r.y2) n++;
      }
      return n;
    };
    const segment = ([x1, y1], [x2, y2]) => ({ at: (t) => [x1 + (x2 - x1) * t, y1 + (y2 - y1) * t], n: Math.ceil(Math.hypot(x2 - x1, y2 - y1) / 6) });
    // A line through points, with round corners. `at` walks the line as drawn, corners included.
    const polyline = (pts) => {
      let d = `M${pts[0][0]},${pts[0][1]}`;
      const trace = [pts[0]];
      for (let i = 1; i < pts.length - 1; i++) {
        const [px, py] = pts[i - 1], [x, y] = pts[i], [nx, ny] = pts[i + 1];
        const r = Math.min(14, Math.hypot(x - px, y - py) / 2, Math.hypot(nx - x, ny - y) / 2);
        const u = (ax, ay) => { const l = Math.hypot(ax - x, ay - y) || 1; return [x + (ax - x) / l * r, y + (ay - y) / l * r]; };
        const [p1, p2] = [u(px, py), u(nx, ny)];
        d += ` L${p1.join(',')} Q${x},${y} ${p2.join(',')}`;
        trace.push(p1, [(p1[0] + 2 * x + p2[0]) / 4, (p1[1] + 2 * y + p2[1]) / 4], p2);
      }
      trace.push(pts.at(-1));
      const segs = trace.slice(1).map((q, i) => Math.hypot(q[0] - trace[i][0], q[1] - trace[i][1])), total = segs.reduce((x, y) => x + y, 0);
      const at = (t) => {
        let left = t * total, i = 0;
        while (i < segs.length - 1 && left > segs[i]) left -= segs[i++];
        const k = left / (segs[i] || 1);
        return [trace[i][0] + (trace[i + 1][0] - trace[i][0]) * k, trace[i][1] + (trace[i + 1][1] - trace[i][1]) * k];
      };
      return { d: d + ` L${pts.at(-1).join(',')}`, at };
    };
    // The lanes: lines across the whole map, on the half-cell grid, that touch no wall.
    const clear = (v, lo, hi) => !walls.some((r) => v > r[lo] && v < r[hi]);
    const laneX = [], laneY = [];
    for (let x = PAD; x <= W - PAD; x += CW / 2) if (clear(x, 'x1', 'x2')) laneX.push(x);
    for (let y = PAD / 2; y <= H - PAD / 2; y += RH / 2) if (clear(y, 'y1', 'y2')) laneY.push(y);
    // The shortest route along the lanes, with few turns: a short, clear straight leg from the first
    // box to a nearby lane crossing, lane to lane, and a short, clear leg into the second. None: null.
    const laneRoute = (f, a, b) => {
      const nx = laneX.length, xy = (n) => [laneX[n % nx], laneY[Math.floor(n / nx)]];
      const nodes = Array.from({ length: nx * laneY.length }, (_, n) => n);
      const leg = (q, n) => {
        const p = xy(n), s = clip(q, ...p);
        if (Math.abs(p[0] - q.cx) > CW || Math.abs(p[1] - q.cy) > RH || blocked(segment(s, p), f)) return Infinity;
        return 2 * Math.hypot(p[0] - s[0], p[1] - s[1]);
      };
      const into = new Map(nodes.map((n) => [n, leg(b, n)]).filter(([, c]) => c < Infinity));
      const cost = new Map(), back = new Map(), queue = [];
      for (const n of nodes) { const c = leg(a, n); if (c < Infinity) { cost.set(`${n}|-1`, c); queue.push([c, n, -1]); } }
      let best = null;
      while (queue.length) {
        queue.sort((u, v) => u[0] - v[0]);
        const [c, n, dir] = queue.shift();
        if (c > cost.get(`${n}|${dir}`)) continue;
        if (into.has(n) && (!best || c + into.get(n) < best[0])) best = [c + into.get(n), `${n}|${dir}`];
        const i = n % nx, j = Math.floor(n / nx);
        [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([di, dj], d) => {
          if (i + di < 0 || j + dj < 0 || i + di >= nx || j + dj >= laneY.length) return;
          const m = n + di + dj * nx, [x0, y0] = xy(n), [x1, y1] = xy(m);
          const nc = c + Math.hypot(x1 - x0, y1 - y0) + (dir >= 0 && dir !== d ? 40 : 0);
          if (nc < (cost.get(`${m}|${d}`) ?? Infinity)) { cost.set(`${m}|${d}`, nc); back.set(`${m}|${d}`, `${n}|${dir}`); queue.push([nc, m, d]); }
        });
      }
      if (!best) return null;
      const pts = [];
      for (let k = best[1]; k; k = back.get(k)) pts.unshift(xy(+k.split('|')[0]));
      const turns = pts.filter((p, i) => i === 0 || i === pts.length - 1 || (p[0] - pts[i - 1][0]) * (pts[i + 1][1] - p[1]) !== (p[1] - pts[i - 1][1]) * (pts[i + 1][0] - p[0]));
      return polyline([clip(a, ...turns[0]), ...turns, clip(b, ...turns.at(-1))]);
    };
    // A label as one line, then as two lines of near equal width.
    const layouts = (t) => {
      const words = t.split(' ');
      if (words.length < 2) return [[t]];
      const halves = words.slice(1).map((_, k) => [words.slice(0, k + 1).join(' '), words.slice(k + 1).join(' ')]);
      return [[t], halves.reduce((p, q) => (Math.max(...q.map((l) => textWidth(l, '12px'))) < Math.max(...p.map((l) => textWidth(l, '12px'))) ? q : p))];
    };
    const placed = [], drawn = [];
    for (const f of flows) {
      const a = pos[f.from], b = pos[f.to];
      if (!a || !b) continue;
      const c = f.change || 'same';
      const len = Math.hypot(b.cx - a.cx, b.cy - a.cy) || 1, mx = (a.cx + b.cx) / 2, my = (a.cy + b.cy) / 2;
      const curved = (off) => curve(a, b, mx - (b.cy - a.cy) / len * off, my + (b.cx - a.cx) / len * off);
      // A flow takes the gentlest curve that clears every wall; when none
      // does, it runs along the lanes; with no lane route either, the curve that crosses least.
      const tries = OFFSETS.map((off) => { const k = curved(off); return [k, blocked(k, f)]; });
      const path = tries.find(([, n]) => !n)?.[0] || laneRoute(f, a, b) || tries.reduce((p, q) => (q[1] < p[1] ? q : p))[0];
      // The label sits on its flow at the spot nearest the middle that covers no box, title, or other
      // label: on one line where one fits, else on two.
      const t = (f.layer ? f.layer + ' · ' : '') + (SIGN[c] || '') + (f.label || '');
      let spot, least = Infinity;
      search: for (const lines of layouts(t)) {
        const tw = Math.max(...lines.map((l) => textWidth(l, '12px'))) + 10, th = lines.length * 14 + 6;
        for (const s of SPOTS) {
          const [lx, ly] = path.at(s), r = { x1: lx - tw / 2, y1: ly - th / 2, x2: lx + tw / 2, y2: ly + th / 2 };
          const cover = [...walls, ...placed].reduce((sum, w) => sum + overlap(r, w), 0) + (r.x1 < 0 || r.x2 > W ? tw * 20 : 0);
          if (cover < least) { spot = { x: lx, y: ly, lines, box: r }; least = cover; }
          if (!cover) break search;
        }
      }
      placed.push(spot.box);
      drawn.push({ ...f, change: c, d: path.d, label: spot });
    }
    return {
      width: W, height: H, groups, flows: drawn,
      parts: parts.map((p) => ({ ...p, ...pos[p.ref], text: (SIGN[p.change || 'same'] || '') + p.name })),
    };
  }

  return { map };
})();
