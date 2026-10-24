// The page's saved state (picks, notes, reactions), with the small slice of
// the claude.ai db API the page uses: collection(), orderBy(), onSnapshot(),
// doc().set/update/delete. Served by tools/art_hunt_serve.py it loads
// docs/art_hunt/state.json and sends back only the documents that changed,
// so two open tabs never undo each other; opened as a plain file it reads
// state.json once and keeps changes in this browser's localStorage.
var LocalDb = (function () {
  var KEY = 'art_hunt_state';
  var state = {}, listeners = [], mode = 'server', saving = false, again = false;
  var pending = new Map(); // 'collection/id' -> {c, id, d}; d null deletes

  async function load() {
    try {
      var r = await fetch('api/state', { cache: 'no-store' });
      if (!r.ok) throw new Error(r.status);
      state = await r.json();
      return;
    } catch (e) {
      mode = 'local';
    }
    try { state = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { state = null; }
    if (!state) {
      try { state = await (await fetch('state.json', { cache: 'no-store' })).json(); } catch (e) { state = {}; }
    }
  }

  async function save() {
    if (saving) { again = true; return; }
    saving = true;
    try {
      if (mode === 'server') {
        var ops = Array.from(pending.values());
        pending.clear();
        if (ops.length) {
          var r = await fetch('api/ops', {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ops: ops }),
          }).catch(function (e) { return { ok: false }; });
          if (!r.ok) {
            ops.forEach(function (op) { var k = op.c + '/' + op.id; if (!pending.has(k)) pending.set(k, op); });
            throw new Error('save failed');
          }
        }
      } else {
        localStorage.setItem(KEY, JSON.stringify(state));
      }
    } catch (e) {
      console.error('art hunt: save failed', e);
    }
    saving = false;
    if (again) { again = false; save(); }
  }

  function notify() { listeners.slice().forEach(function (l) { l(); }); }

  function snapDoc(id, d) { return { id: id, exists: true, data: function () { return d; } }; }

  function collection(name) {
    function docs(order) {
      var c = state[name] || {};
      var arr = Object.keys(c).sort().map(function (id) { return snapDoc(id, c[id]); });
      if (order) arr.sort(function (a, b) {
        var x = a.data()[order], y = b.data()[order];
        return (x > y) - (x < y);
      });
      return arr;
    }
    function query(order) {
      return {
        orderBy: function (field) { return query(field); },
        onSnapshot: function (next) {
          var prev = new Set();
          function fire() {
            var list = docs(order), cur = new Set(list.map(function (d) { return d.id; }));
            var changes = list.map(function (d) { return { type: prev.has(d.id) ? 'modified' : 'added', doc: d }; });
            prev.forEach(function (id) { if (!cur.has(id)) changes.push({ type: 'removed', doc: snapDoc(id, {}) }); });
            prev = cur;
            next({ docs: list, size: list.length, empty: !list.length, docChanges: function () { return changes; } });
          }
          listeners.push(fire);
          setTimeout(fire, 0);
          return function () { listeners = listeners.filter(function (l) { return l !== fire; }); };
        },
        doc: function (id) {
          id = id || Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
          function bucket() { return state[name] || (state[name] = {}); }
          function mark() { var d = (state[name] || {})[id]; pending.set(name + '/' + id, { c: name, id: id, d: d === undefined ? null : d }); }
          return {
            id: id,
            set: async function (d) { bucket()[id] = JSON.parse(JSON.stringify(d)); mark(); notify(); await save(); },
            update: async function (d) { bucket()[id] = Object.assign({}, bucket()[id] || {}, JSON.parse(JSON.stringify(d))); mark(); notify(); await save(); },
            delete: async function () { delete bucket()[id]; mark(); notify(); await save(); },
          };
        },
      };
    }
    return query(null);
  }

  var ready = load();
  return { ready: ready, collection: collection, mode: function () { return mode; } };
})();

async function getDb() { await LocalDb.ready; return LocalDb; }
