#!/usr/bin/env node
// A Chrome window on Steamworks that Claude can read, so it can tell you what
// to click. You log in and click; the tool only reads the page, outlines an
// element, and (when asked) types into a field. It never clicks or submits.
//
//   node tools/steam_browser.cjs start           open the window (its own profile)
//   node tools/steam_browser.cjs read            the visible tab: headings, fields, buttons, numbered
//   node tools/steam_browser.cjs show <n|text>   outline element n (or the first with that text) in red
//   node tools/steam_browser.cjs fill <n> <val>  type into field n, pick an option, or tick a box (not saved)
//   node tools/steam_browser.cjs shot [file]     screenshot of the visible tab
//   node tools/steam_browser.cjs goto <url>      open a URL in the visible tab
//
// The profile lives in ~/.cache/underhum-steamworks-chrome and keeps the login.
// Delete that folder to log out for good.
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = 9333;
const PROFILE = path.join(os.homedir(), '.cache', 'underhum-steamworks-chrome');
const CHROME = process.env.CHROME || '/usr/bin/google-chrome';

function playwright() {
  const tries = ['playwright-core',
    path.join(os.homedir(), '.npm-global/lib/node_modules/@playwright/cli/node_modules/playwright-core')];
  for (const t of tries) { try { return require(t); } catch (e) {} }
  console.error('playwright-core not found: npm i -g playwright-core');
  process.exit(1);
}

async function page() {
  const { chromium } = playwright();
  let browser;
  try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`); }
  catch (e) { console.error('The Steamworks window is not open. Run: node tools/steam_browser.cjs start'); process.exit(1); }
  const pages = browser.contexts().flatMap(c => c.pages()).filter(p => !p.url().startsWith('devtools://'));
  for (const p of pages) {
    if (await p.evaluate(() => document.visibilityState === 'visible').catch(() => false)) return p;
  }
  if (!pages.length) { console.error('No tab open.'); process.exit(1); }
  return pages[pages.length - 1];
}

// Runs in the page: numbers every visible field, button and link, and describes them.
function scan() {
  const vis = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const labelOf = el => {
    if (el.id) { const l = document.querySelector(`label[for="${CSS.escape(el.id)}"]`); if (l) return clean(l.innerText); }
    if (el.getAttribute('aria-label')) return clean(el.getAttribute('aria-label'));
    const wrap = el.closest('label'); if (wrap) return clean(wrap.innerText);
    let n = el, hops = 0;
    while (n && hops < 4) {   // the nearest text before the field
      let p = n.previousElementSibling;
      while (p) { const t = clean(p.innerText); if (t) return t.slice(-80); p = p.previousElementSibling; }
      n = n.parentElement; hops++;
    }
    return clean(el.placeholder || el.name || '');
  };
  document.querySelectorAll('[data-uh]').forEach(e => e.removeAttribute('data-uh'));
  const out = { url: location.href, title: document.title, headings: [], items: [] };
  document.querySelectorAll('h1,h2,h3,.page_title,.section_title').forEach(h => {
    if (vis(h)) { const t = clean(h.innerText); if (t && !out.headings.includes(t)) out.headings.push(t.slice(0, 100)); } });
  let n = 0;
  const els = document.querySelectorAll('input,select,textarea,button,a[href],[role=button],[onclick],.btn_medium,.btnv6_blue_hoverfade');
  const seen = new Set();
  for (const el of els) {
    if (seen.has(el) || !vis(el)) continue;
    seen.add(el);
    const tag = el.tagName.toLowerCase();
    const type = (el.type || '').toLowerCase();
    if (tag === 'input' && type === 'hidden') continue;
    const it = {};
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      it.kind = tag === 'select' ? 'select' : (type === 'checkbox' || type === 'radio') ? type : 'field';
      it.label = labelOf(el).slice(0, 90);
      if (type === 'password') it.value = '(hidden)';
      else if (it.kind === 'select') { it.value = clean(el.options[el.selectedIndex]?.text); it.options = [...el.options].map(o => clean(o.text)).slice(0, 12); }
      else if (it.kind === 'checkbox' || it.kind === 'radio') it.value = el.checked ? 'on' : 'off';
      else it.value = clean(el.value).slice(0, 60);
      if (el.required || /\*\s*$/.test(it.label)) it.required = true;
    } else {
      it.kind = tag === 'a' ? 'link' : 'button';
      it.label = clean(el.innerText || el.value || el.getAttribute('aria-label') || el.title).slice(0, 70);
      if (!it.label) continue;
    }
    it.n = ++n;
    el.setAttribute('data-uh', it.n);
    out.items.push(it);
  }
  return out;
}

function mark(sel) {
  document.querySelectorAll('[data-uh-mark]').forEach(e => { e.style.outline = e.dataset.uhOld || ''; e.removeAttribute('data-uh-mark'); });
  document.getElementById('uh-tip')?.remove();
  const el = document.querySelector(sel);
  if (!el) return false;
  el.dataset.uhOld = el.style.outline;
  el.setAttribute('data-uh-mark', '1');
  el.style.outline = '4px solid #ff2d55';
  el.style.outlineOffset = '3px';
  el.scrollIntoView({ block: 'center', behavior: 'instant' });
  const r = el.getBoundingClientRect();
  const tip = document.createElement('div');
  tip.id = 'uh-tip'; tip.textContent = '◀ here';
  Object.assign(tip.style, { position: 'fixed', zIndex: 2147483647, background: '#ff2d55', color: '#fff',
    font: 'bold 14px sans-serif', padding: '3px 8px', borderRadius: '4px', pointerEvents: 'none',
    left: Math.min(innerWidth - 80, r.right + 10) + 'px', top: Math.max(0, r.top + r.height / 2 - 12) + 'px' });
  document.body.appendChild(tip);
  return true;
}

async function main() {
  const [cmd, ...args] = process.argv.slice(2);
  if (cmd === 'start') {
    fs.mkdirSync(PROFILE, { recursive: true });
    const url = args[0] || 'https://partner.steamgames.com/';
    spawn(CHROME, [`--remote-debugging-port=${PORT}`, '--remote-debugging-address=127.0.0.1', `--user-data-dir=${PROFILE}`,
      '--no-first-run', '--no-default-browser-check', '--new-window', url], { detached: true, stdio: 'ignore' }).unref();
    console.log(`Opened ${url} in its own Chrome profile. Log in there.`);
    return;
  }
  const p = await page();
  if (cmd === 'read') {
    const r = await p.evaluate(scan);
    console.log(`URL   ${r.url}\nTITLE ${r.title}`);
    if (r.headings.length) console.log('HEADINGS\n  ' + r.headings.slice(0, 25).join('\n  '));
    console.log('ITEMS');
    for (const it of r.items) {
      let line = `  [${it.n}] ${it.kind.padEnd(8)} ${it.label}`;
      if ('value' in it) line += `  = ${JSON.stringify(it.value)}`;
      if (it.options) line += `  options: ${it.options.join(' | ')}`;
      if (it.required) line += '  (required)';
      console.log(line);
    }
  } else if (cmd === 'show') {
    const q = args.join(' ');
    if (/^\d+$/.test(q)) { if (!await p.evaluate(mark, `[data-uh="${q}"]`)) console.log('No item ' + q + '; run read again.'); else console.log('Outlined item ' + q); }
    else {
      const all = p.getByText(q, { exact: false });
      let loc = null;
      for (let i = 0; i < await all.count(); i++) {   // the first visible match, not a hidden copy
        if (await all.nth(i).isVisible()) { loc = all.nth(i); break; }
      }
      if (!loc) { console.log('Nothing visible with that text.'); process.exit(0); }
      await loc.evaluate(el => el.setAttribute('data-uh-find', '1'));
      await p.evaluate(mark, '[data-uh-find="1"]');
      await p.evaluate(() => document.querySelectorAll('[data-uh-find]').forEach(e => e.removeAttribute('data-uh-find')));
      console.log('Outlined: ' + q);
    }
  } else if (cmd === 'fill') {
    const [n, ...rest] = args; const val = rest.join(' ');
    const loc = p.locator(`[data-uh="${n}"]`);
    if (!await loc.count()) { console.log('No item ' + n + '; run read again.'); process.exit(0); }
    const tag = await loc.evaluate(el => el.tagName.toLowerCase() + ':' + (el.type || ''));
    if (tag.startsWith('select')) await loc.selectOption({ label: val });
    else if (/checkbox|radio/.test(tag)) await (/^(on|yes|1|true)$/i.test(val) ? loc.check() : loc.uncheck());
    else await loc.fill(val);
    await p.evaluate(mark, `[data-uh="${n}"]`);
    console.log(`Filled item ${n}. Nothing is saved until you click the page's own save button.`);
  } else if (cmd === 'shot') {
    const f = args[0] || path.join(os.tmpdir(), 'steamworks.png');
    await p.screenshot({ path: f });
    console.log(f);
  } else if (cmd === 'goto') {
    await p.goto(args[0]);
    console.log('Opened ' + p.url());
  } else {
    console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 17).join('\n'));
  }
  process.exit(0);
}
main().catch(e => { console.error(e.message); process.exit(1); });
