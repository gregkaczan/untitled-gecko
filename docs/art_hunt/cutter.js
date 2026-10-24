// The Downloaded tab: every sheet from the packs (assets.json, made by
// tools/art_hunt_assets.py) on a zoomable stage. Drag around sprites to
// circle them (or drag a box); each cut saves to the 'cuts' collection of
// state.json with its outline in sheet pixels, what it should become in the
// game, and a note. A pixel belongs to a cut when its centre lies inside the
// outline and it is not see-through; tools/art_hunt_cuts.py crops them the
// same way.
(function () {
  var root = document.getElementById('downloaded');
  var dataEl = document.getElementById('assets-data');
  if (!root || !dataEl) return;
  var DATA = JSON.parse(dataEl.textContent);
  var SHEETS = new Map();
  DATA.packs.forEach(function (p) { p.sheets.forEach(function (s) { s.pack = p; SHEETS.set(s.id, s); }); });

  var USES = [
    ['', 'Not sorted yet'],
    ['Replace what we have', [['moss', 'Moss carpet'], ['fern', 'Fern'], ['plant', 'Sprout'], ['cluster', 'Shroom cluster'], ['shroom_s', 'Small cap'], ['tall', 'Tall shroom'], ['vine_leaves', 'Vine leaves']]],
    ['New decor', [['hanging', 'Hangs from the ceiling'], ['floor', 'Stands on the floor'], ['wall', 'Grows on a wall'], ['crystal', 'Crystal or ore'], ['machine', 'Mine machinery'], ['prop', 'Other prop']]],
    ['Living', [['creature', 'Creature'], ['insect', 'Insect'], ['slime', 'Slime']]],
    ['Scenery', [['background', 'Background layer'], ['window', 'Window onto the shaft'], ['tiles', 'Terrain tiles']]],
  ];
  var USE_NAME = {};
  USES.forEach(function (g) { if (Array.isArray(g[1])) g[1].forEach(function (u) { USE_NAME[u[0]] = u[1]; }); else USE_NAME[g[0]] = g[1]; });
  function useOptions(sel) {
    return USES.map(function (g) {
      if (!Array.isArray(g[1])) return '<option value="' + g[0] + '"' + (sel === g[0] ? ' selected' : '') + '>' + g[1] + '</option>';
      return '<optgroup label="' + g[0] + '">' + g[1].map(function (u) {
        return '<option value="' + u[0] + '"' + (sel === u[0] ? ' selected' : '') + '>' + u[1] + '</option>';
      }).join('') + '</optgroup>';
    }).join('');
  }
  var HUES = ['#ffd166', '#06d6a0', '#ef476f', '#4cc9f0', '#f78c6b', '#b8f2e6', '#c77dff', '#90be6d'];
  var GAME_ZOOM = 4; // 1 art px = 4 screen px in the game

  var el = function (id) { return root.querySelector('#' + id); };
  var list = el('cut-sheets'), stage = el('cut-stage'), layer = el('cut-layer');
  var base = el('cut-base'), over = el('cut-over'), title = el('cut-title'), meta = el('cut-meta');
  var cutsBox = el('cut-list'), allBox = el('cut-all'), status = el('cut-status'), zoomOut = el('cut-zoom');
  var palBox = el('cut-pal'), bgSel = el('cut-bg');
  var bctx = base.getContext('2d'), octx = over.getContext('2d');

  var cuts = new Map();     // id -> doc data
  var images = new Map();   // sheet id -> {img, data (ImageData), pal (canvas)}
  var sheet = null, zoom = 2, tool = 'lasso', selected = null, path = null, col = null, db = null;
  var palette = null;

  // ---------- sheet list ----------
  list.innerHTML = DATA.packs.map(function (p) {
    return '<div class="cut-pack"><h3>' + esc(p.name) + '</h3>' +
      (p.licence ? '<details class="cut-lic"><summary>Licence</summary><pre>' + esc(p.licence) + '</pre></details>' : '') +
      p.sheets.map(function (s) {
        return '<button type="button" class="cut-sheet" data-id="' + esc(s.id) + '"><img src="' + esc(s.file) + '" alt="" loading="lazy">' +
          '<span class="t">' + esc(s.title.split('/').pop()) + '</span><span class="n" data-n="' + esc(s.id) + '"></span></button>';
      }).join('') + '</div>';
  }).join('');
  list.addEventListener('click', function (e) {
    var b = e.target.closest('.cut-sheet');
    if (b) open(b.dataset.id);
  });

  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }

  // ---------- images and the game palette ----------
  function loadImage(src) {
    return new Promise(function (ok, bad) { var i = new Image(); i.onload = function () { ok(i); }; i.onerror = bad; i.src = src; });
  }
  function pixels(img) {
    var c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    var x = c.getContext('2d'); x.drawImage(img, 0, 0);
    return x.getImageData(0, 0, img.width, img.height);
  }
  var palReady = loadImage('ref/palette.png').then(function (img) {
    var d = pixels(img).data; palette = [];
    for (var i = 0; i < img.width; i++) palette.push([d[i * 4], d[i * 4 + 1], d[i * 4 + 2]]);
  }).catch(function () { palette = null; });
  // The nearest palette colour, as the game picks it (scene_builder.gd _stamp_from_image)
  function toPalette(id) {
    var src = id.data, out = new ImageData(id.width, id.height), o = out.data, memo = new Map();
    for (var i = 0; i < src.length; i += 4) {
      if (src[i + 3] < 128) continue;
      var k = (src[i] << 16) | (src[i + 1] << 8) | src[i + 2], c = memo.get(k);
      if (!c) {
        var bd = Infinity;
        for (var j = 0; j < palette.length; j++) {
          var p = palette[j], d = (p[0] - src[i]) ** 2 + (p[1] - src[i + 1]) ** 2 + (p[2] - src[i + 2]) ** 2;
          if (d < bd) { bd = d; c = p; }
        }
        memo.set(k, c);
      }
      o[i] = c[0]; o[i + 1] = c[1]; o[i + 2] = c[2]; o[i + 3] = 255;
    }
    return out;
  }
  async function sheetImage(s) {
    var got = images.get(s.id);
    if (got) return got;
    var img = await loadImage(s.file);
    got = { img: img, data: pixels(img), pal: null };
    images.set(s.id, got);
    return got;
  }
  function usePal() { return palBox.checked && palette; }
  function source(got) {
    if (!usePal()) return got.img;
    if (!got.pal) {
      got.pal = document.createElement('canvas'); got.pal.width = got.data.width; got.pal.height = got.data.height;
      got.pal.getContext('2d').putImageData(toPalette(got.data), 0, 0);
    }
    return got.pal;
  }

  // ---------- the stage ----------
  function maxZoom(s) { return Math.max(1, Math.min(12, Math.floor(8000 / Math.max(s.w, s.h)))); }
  function fitZoom(s) { return Math.max(1, Math.min(maxZoom(s), 8, Math.floor((stage.clientWidth - 4) / s.w) || 1)); }
  async function open(id, keepZoom) {
    var s = SHEETS.get(id);
    if (!s) return;
    var changed = !sheet || sheet.id !== id;
    sheet = s;
    if (changed) selected = null;
    list.querySelectorAll('.cut-sheet').forEach(function (b) { b.setAttribute('aria-current', b.dataset.id === id ? 'true' : 'false'); });
    title.textContent = s.title;
    meta.textContent = s.w + 'x' + s.h + ' px' + (s.keyed ? ', backdrop keyed out' : '') + (s.parts ? ', ' + s.parts.length + ' parts' : '') + ' · ' + s.pack.name;
    try { localStorage.setItem('cut:sheet', id); } catch (e) {}
    if (changed && !keepZoom) zoom = fitZoom(s);
    await sheetImage(s);
    if (sheet !== s) return;
    draw();
    renderList();
  }
  function setZoom(z, anchor) {
    if (!sheet) return;
    z = Math.max(1, Math.min(maxZoom(sheet), z));
    if (z === zoom) return;
    var ax = anchor ? anchor.x : stage.clientWidth / 2, ay = anchor ? anchor.y : stage.clientHeight / 2;
    var ix = (stage.scrollLeft + ax) / zoom, iy = (stage.scrollTop + ay) / zoom;
    zoom = z;
    draw();
    stage.scrollLeft = ix * zoom - ax; stage.scrollTop = iy * zoom - ay;
  }
  function draw() {
    if (!sheet) return;
    var got = images.get(sheet.id);
    if (!got) return;
    var w = sheet.w * zoom, h = sheet.h * zoom;
    [base, over].forEach(function (c) { c.width = w; c.height = h; c.style.width = w + 'px'; c.style.height = h + 'px'; });
    layer.style.width = w + 'px'; layer.style.height = h + 'px';
    bctx.imageSmoothingEnabled = false;
    bctx.clearRect(0, 0, w, h);
    bctx.drawImage(source(got), 0, 0, w, h);
    zoomOut.textContent = zoom + 'x';
    overlay();
  }
  function sheetCuts() {
    var out = [];
    cuts.forEach(function (d, id) { if (sheet && d.sheet === sheet.id) out.push([id, d]); });
    out.sort(function (a, b) { return (a[1].created || 0) - (b[1].created || 0); });
    return out;
  }
  function polyPath(ctx, pts) {
    ctx.beginPath();
    pts.forEach(function (p, i) { var x = p[0] * zoom, y = p[1] * zoom; if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y); });
    ctx.closePath();
  }
  function overlay() {
    octx.clearRect(0, 0, over.width, over.height);
    sheetCuts().forEach(function (e, i) {
      var id = e[0], d = e[1], hue = HUES[i % HUES.length], on = id === selected;
      polyPath(octx, d.pts);
      octx.fillStyle = on ? 'rgba(255,255,255,.14)' : 'rgba(255,255,255,.05)';
      octx.fill();
      octx.lineWidth = on ? 3 : 2;
      octx.setLineDash(on ? [] : [6, 4]);
      octx.strokeStyle = on ? '#fff' : hue;
      octx.stroke();
      var b = bounds(d.pts);
      octx.setLineDash([]);
      octx.font = '600 12px "JetBrains Mono", monospace';
      var label = String(i + 1) + (d.use ? ' ' + (USE_NAME[d.use] || d.use) : '');
      var tw = octx.measureText(label).width + 8, lx = Math.max(0, b[0] * zoom), ly = Math.max(0, b[1] * zoom - 18);
      octx.fillStyle = on ? '#fff' : hue;
      octx.fillRect(lx, ly, tw, 17);
      octx.fillStyle = '#0c0f0b';
      octx.fillText(label, lx + 4, ly + 13);
    });
    if (path && path.pts.length > 1) {
      var pts = tool === 'box' ? boxPts(path.pts[0], path.pts[path.pts.length - 1]) : path.pts;
      polyPath(octx, pts);
      octx.setLineDash([]);
      octx.lineWidth = 2; octx.strokeStyle = '#fff'; octx.stroke();
      octx.lineWidth = 1; octx.strokeStyle = '#000'; octx.setLineDash([4, 4]); octx.stroke();
      octx.setLineDash([]);
    }
  }
  function boxPts(a, b) {
    var x0 = Math.floor(Math.min(a[0], b[0])), y0 = Math.floor(Math.min(a[1], b[1]));
    var x1 = Math.ceil(Math.max(a[0], b[0])), y1 = Math.ceil(Math.max(a[1], b[1]));
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
  }
  function bounds(pts) {
    var b = [Infinity, Infinity, -Infinity, -Infinity];
    pts.forEach(function (p) { b[0] = Math.min(b[0], p[0]); b[1] = Math.min(b[1], p[1]); b[2] = Math.max(b[2], p[0]); b[3] = Math.max(b[3], p[1]); });
    return b;
  }
  function inside(pts, x, y) {
    var c = false;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      var a = pts[i], b = pts[j];
      if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) c = !c;
    }
    return c;
  }
  function area(pts) {
    var s = 0;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) s += (pts[j][0] + pts[i][0]) * (pts[j][1] - pts[i][1]);
    return Math.abs(s / 2);
  }

  // The pixels a cut takes, trimmed to their box: {x, y, w, h, data}
  function crop(d, got) {
    var id = got.data, W = id.width, H = id.height, src = id.data;
    var b = bounds(d.pts), x0 = Math.max(0, Math.floor(b[0])), y0 = Math.max(0, Math.floor(b[1]));
    var x1 = Math.min(W - 1, Math.ceil(b[2])), y1 = Math.min(H - 1, Math.ceil(b[3]));
    var keep = [], minx = Infinity, miny = Infinity, maxx = -1, maxy = -1;
    for (var y = y0; y <= y1; y++) for (var x = x0; x <= x1; x++) {
      if (src[(y * W + x) * 4 + 3] === 0 || !inside(d.pts, x + 0.5, y + 0.5)) continue;
      keep.push(x, y);
      if (x < minx) minx = x; if (y < miny) miny = y; if (x > maxx) maxx = x; if (y > maxy) maxy = y;
    }
    if (maxx < 0) return null;
    var w = maxx - minx + 1, h = maxy - miny + 1, out = new ImageData(w, h);
    var from = usePal() ? (got.palData || (got.palData = toPalette(id))).data : src;
    for (var k = 0; k < keep.length; k += 2) {
      var si = (keep[k + 1] * W + keep[k]) * 4, oi = ((keep[k + 1] - miny) * w + keep[k] - minx) * 4;
      out.data[oi] = from[si]; out.data[oi + 1] = from[si + 1]; out.data[oi + 2] = from[si + 2]; out.data[oi + 3] = usePal() ? 255 : src[si + 3];
    }
    return { x: minx, y: miny, w: w, h: h, data: out };
  }
  function previewCanvas(c, maxW, maxH) {
    var z = Math.max(1, Math.min(GAME_ZOOM, Math.floor(maxW / c.w), Math.floor(maxH / c.h)));
    var small = document.createElement('canvas'); small.width = c.w; small.height = c.h;
    small.getContext('2d').putImageData(c.data, 0, 0);
    var big = document.createElement('canvas'); big.width = c.w * z; big.height = c.h * z;
    var x = big.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(small, 0, 0, big.width, big.height);
    big.title = c.w + 'x' + c.h + ' px at ' + z + 'x' + (z === GAME_ZOOM ? ' (game size)' : '');
    return { canvas: big, zoom: z };
  }

  // ---------- drawing ----------
  function at(e) {
    var r = over.getBoundingClientRect();
    return [Math.max(0, Math.min(sheet.w, (e.clientX - r.left) / zoom)), Math.max(0, Math.min(sheet.h, (e.clientY - r.top) / zoom))];
  }
  over.addEventListener('pointerdown', function (e) {
    if (!sheet || e.button !== 0) return;
    over.setPointerCapture(e.pointerId);
    path = { pts: [at(e)], sx: e.clientX, sy: e.clientY, far: 0 };
    e.preventDefault();
  });
  over.addEventListener('pointermove', function (e) {
    if (!path) return;
    var p = at(e), last = path.pts[path.pts.length - 1];
    path.far = Math.max(path.far, Math.hypot(e.clientX - path.sx, e.clientY - path.sy));
    if (Math.hypot((p[0] - last[0]) * zoom, (p[1] - last[1]) * zoom) >= 3) { path.pts.push(p); overlay(); }
  });
  over.addEventListener('pointerup', finish);
  over.addEventListener('pointercancel', function () { path = null; overlay(); });
  function finish(e) {
    if (!path) return;
    var p = path; path = null;
    if (p.far < 6) { pickAt(at(e)); return; }
    p.pts.push(at(e));
    var pts = tool === 'box' ? boxPts(p.pts[0], p.pts[p.pts.length - 1]) : simplify(p.pts);
    if (pts.length < 3 || area(pts) < 1) { overlay(); return; }
    var d = { sheet: sheet.id, pts: pts, use: '', notes: '', created: Date.now() };
    var got = images.get(sheet.id);
    if (!crop(d, got)) { status.textContent = 'Nothing there: that outline holds only see-through pixels.'; overlay(); return; }
    if (!col) { status.textContent = 'Not connected, so this cut cannot be saved. Start tools/art_hunt_serve.py and reload.'; overlay(); return; }
    var ref = col.doc();
    selected = ref.id;
    ref.set(d).catch(function () { status.textContent = 'Could not save that cut.'; });
  }
  function simplify(pts) {
    var out = [];
    pts.forEach(function (p) {
      var q = [Math.round(p[0] * 2) / 2, Math.round(p[1] * 2) / 2], l = out[out.length - 1];
      if (!l || l[0] !== q[0] || l[1] !== q[1]) out.push(q);
    });
    while (out.length > 300) out = out.filter(function (_, i) { return i % 2 === 0; });
    return out;
  }
  function pickAt(p) {
    var best = null, ba = Infinity;
    sheetCuts().forEach(function (e) { if (inside(e[1].pts, p[0], p[1])) { var a = area(e[1].pts); if (a < ba) { ba = a; best = e[0]; } } });
    select(best, true);
  }
  function select(id, scrollList) {
    selected = id;
    overlay();
    cutsBox.querySelectorAll('.cut').forEach(function (c) { c.classList.toggle('on', c.dataset.id === id); });
    if (id && scrollList) { var c = cutsBox.querySelector('.cut[data-id="' + id + '"]'); if (c) c.scrollIntoView({ block: 'nearest' }); }
  }
  function remove(id) {
    if (!col || !id) return;
    if (selected === id) selected = null;
    col.doc(id).delete().catch(function () { status.textContent = 'Could not remove that cut.'; });
  }

  // ---------- controls ----------
  root.querySelectorAll('[data-tool]').forEach(function (b) {
    b.addEventListener('click', function () {
      tool = b.dataset.tool;
      root.querySelectorAll('[data-tool]').forEach(function (x) { x.setAttribute('aria-pressed', x === b); });
    });
  });
  el('cut-in').addEventListener('click', function () { setZoom(zoom + 1); });
  el('cut-outz').addEventListener('click', function () { setZoom(zoom - 1); });
  el('cut-fit').addEventListener('click', function () { if (sheet) setZoom(fitZoom(sheet)); });
  stage.addEventListener('wheel', function (e) {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    var r = stage.getBoundingClientRect();
    setZoom(zoom + (e.deltaY < 0 ? 1 : -1), { x: e.clientX - r.left, y: e.clientY - r.top });
  }, { passive: false });
  palBox.addEventListener('change', function () { draw(); renderList(); renderAll(); });
  function setBg() { stage.dataset.bg = bgSel.value; try { localStorage.setItem('cut:bg', bgSel.value); } catch (e) {} }
  bgSel.addEventListener('change', setBg);
  try { bgSel.value = localStorage.getItem('cut:bg') || 'cave'; } catch (e) {}
  setBg();
  document.addEventListener('keydown', function (e) {
    if (root.hidden || e.target.closest('input, textarea, select')) return;
    if (e.key === 'Escape') { path = null; select(null); }
    else if ((e.key === 'Delete' || e.key === 'Backspace') && selected) { e.preventDefault(); remove(selected); }
    else if (e.key === '+' || e.key === '=') setZoom(zoom + 1);
    else if (e.key === '-') setZoom(zoom - 1);
    else if (e.key === 'l') root.querySelector('[data-tool=lasso]').click();
    else if (e.key === 'b') root.querySelector('[data-tool=box]').click();
  });

  // ---------- cut lists ----------
  var rows = new Map(); // id -> row element (this sheet's list)
  function renderList() {
    if (!sheet) return;
    var got = images.get(sheet.id), seen = new Set();
    sheetCuts().forEach(function (e, i) {
      var id = e[0], d = e[1], row = rows.get(id);
      seen.add(id);
      if (!row) {
        row = document.createElement('div');
        row.className = 'cut'; row.dataset.id = id;
        row.innerHTML = '<div class="cut-thumb"></div><div class="cut-fields">' +
          '<div class="cut-head"><b class="cut-n"></b><span class="cut-size"></span><button type="button" class="cut-del">Remove</button></div>' +
          '<label>Use as <select class="cut-use"></select></label>' +
          '<textarea class="cut-notes" rows="2" placeholder="Notes: which part, how to use it, recolour..."></textarea></div>';
        var sel = row.querySelector('.cut-use'), notes = row.querySelector('.cut-notes'), t = null;
        sel.addEventListener('change', function () { col.doc(id).update({ use: sel.value }); });
        notes.addEventListener('input', function () { clearTimeout(t); t = setTimeout(function () { col.doc(id).update({ notes: notes.value }); }, 600); });
        notes.addEventListener('blur', function () { clearTimeout(t); if (notes.value !== (cuts.get(id) || {}).notes) col.doc(id).update({ notes: notes.value }); });
        row.querySelector('.cut-del').addEventListener('click', function () { remove(id); });
        row.addEventListener('click', function (ev) { if (!ev.target.closest('select, textarea, button')) select(id); });
        rows.set(id, row);
      }
      row.style.setProperty('--hue', HUES[i % HUES.length]);
      row.querySelector('.cut-n').textContent = '#' + (i + 1);
      var sel = row.querySelector('.cut-use');
      if (sel.dataset.v !== (d.use || '')) { sel.innerHTML = useOptions(d.use || ''); sel.dataset.v = d.use || ''; }
      var notes = row.querySelector('.cut-notes');
      if (document.activeElement !== notes && notes.value !== (d.notes || '')) notes.value = d.notes || '';
      var c = got && crop(d, got), thumb = row.querySelector('.cut-thumb');
      var key = JSON.stringify(d.pts).length + ':' + d.pts.length + ':' + (usePal() ? 'p' : 'o');
      if (c && thumb.dataset.k !== key) {
        var pv = previewCanvas(c, 220, 200);
        thumb.replaceChildren(pv.canvas);
        thumb.dataset.k = key;
        row.querySelector('.cut-size').textContent = c.w + 'x' + c.h + ' px, shown ' + pv.zoom + 'x' + (pv.zoom === GAME_ZOOM ? ' (game size)' : '');
      }
      row.classList.toggle('on', id === selected);
      if (cutsBox.children[i] !== row) cutsBox.insertBefore(row, cutsBox.children[i] || null);
    });
    rows.forEach(function (row, id) { if (!seen.has(id)) { row.remove(); rows.delete(id); } });
    el('cut-empty').hidden = seen.size > 0;
  }
  async function renderAll() {
    var groups = new Map();
    cuts.forEach(function (d, id) {
      var k = d.use || '';
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push([id, d]);
    });
    el('cut-count').textContent = cuts.size;
    list.querySelectorAll('[data-n]').forEach(function (n) {
      var c = 0; cuts.forEach(function (d) { if (d.sheet === n.dataset.n) c++; });
      n.textContent = c ? c : '';
    });
    var order = [''].concat(Object.keys(USE_NAME).filter(function (k) { return k; }));
    var frag = document.createDocumentFragment();
    for (var k of order) {
      var g = groups.get(k);
      if (!g) continue;
      var box = document.createElement('div'); box.className = 'cut-group';
      box.innerHTML = '<h3>' + esc(USE_NAME[k] || k) + ' <span>' + g.length + '</span></h3><div class="cut-tiles"></div>';
      var tiles = box.querySelector('.cut-tiles');
      g.sort(function (a, b) { return (a[1].created || 0) - (b[1].created || 0); });
      for (var e of g) {
        var s = SHEETS.get(e[1].sheet);
        if (!s) continue;
        var got = await sheetImage(s).catch(function () { return null; });
        var c = got && crop(e[1], got);
        if (!c) continue;
        var b = document.createElement('button');
        b.type = 'button'; b.className = 'cut-tile'; b.dataset.id = e[0]; b.dataset.sheet = s.id;
        b.title = s.title + (e[1].notes ? '\n' + e[1].notes : '');
        b.appendChild(previewCanvas(c, 96, 96).canvas);
        tiles.appendChild(b);
      }
      frag.appendChild(box);
    }
    allBox.replaceChildren(frag);
  }
  allBox.addEventListener('click', function (e) {
    var b = e.target.closest('.cut-tile');
    if (!b) return;
    open(b.dataset.sheet).then(function () {
      select(b.dataset.id, true);
      var d = cuts.get(b.dataset.id);
      if (d) { var bb = bounds(d.pts); stage.scrollLeft = bb[0] * zoom - 40; stage.scrollTop = bb[1] * zoom - 40; }
      stage.scrollIntoView({ block: 'nearest' });
    });
  });

  // ---------- start ----------
  var first = null;
  try { first = localStorage.getItem('cut:sheet'); } catch (e) {}
  if (!SHEETS.has(first)) first = SHEETS.keys().next().value;
  var started = false;
  function start() { if (started || root.hidden) return; started = true; palReady.then(function () { open(first); }); }
  new MutationObserver(start).observe(root, { attributes: true, attributeFilter: ['hidden'] });
  start();

  (async function () {
    try { db = await getDb(); } catch (e) { db = null; }
    if (!db) { status.textContent = 'Saving is off in this view.'; return; }
    col = db.collection('cuts');
    var where = db.mode() === 'server' ? 'saved to docs/art_hunt/state.json' : 'saved in this browser only (start tools/art_hunt_serve.py to save to the repo)';
    col.orderBy('created').onSnapshot(function (snap) {
      cuts = new Map(snap.docs.map(function (d) { return [d.id, d.data()]; }));
      if (selected && !cuts.has(selected)) selected = null;
      status.textContent = cuts.size + (cuts.size === 1 ? ' cut, ' : ' cuts, ') + where + '.';
      overlay(); renderList(); renderAll();
    });
  })();
})();
