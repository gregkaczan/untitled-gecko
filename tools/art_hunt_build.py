# art_hunt_build.py [site_dir] : docs/art_hunt/data.json + assets.json + ref/ + img/ -> index.html
# Serve it with tools/art_hunt_serve.py so picks, notes and reactions save to state.json.
import sys, json, os, glob, html, datetime
from PIL import Image

site = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'art_hunt')
data = json.load(open(f'{site}/data.json'))
E = html.escape
assets = json.load(open(f'{site}/assets.json')) if os.path.exists(f'{site}/assets.json') else {'packs': []}
n_sheets = sum(len(p['sheets']) for p in assets['packs'])
assets_json = json.dumps(assets, ensure_ascii=False).replace('</', '<\\/')

REF = [
    ('cluster_0', 'shroom cluster'), ('cluster_2', 'shroom cluster'),
    ('shroom_s_0', 'small cap'), ('tall_a_0', 'tall shroom'), ('tall_b_0', 'tall shroom'),
    ('fern_0', 'fern'), ('plant_0', 'sprout'), ('vine_leaves_0', 'vine leaves'),
    ('moss_1', 'white moss'), ('moss_4', 'white moss'),
    ('gecko_stand_1x', 'gecko (drawn by code)'),
]
ZOOM = 4

def ref_html():
    out = []
    for name, label in REF:
        w, h = Image.open(f'{site}/ref/{name}.png').size
        out.append(f'<figure class="sprite"><div class="well"><img src="ref/{name}.png" width="{w*ZOOM}" height="{h*ZOOM}" alt="{E(label)}"></div>'
                   f'<figcaption>{E(label)}<span>{w}x{h}</span></figcaption></figure>')
    return '\n'.join(out)

def palette_html():
    im = Image.open(f'{site}/ref/palette.png').convert('RGB')
    return ''.join(f'<i style="background:#{"%02x%02x%02x" % im.getpixel((x, 0))}"></i>' for x in range(im.width))

FIT = {'strong': 'Close match', 'partial': 'Partial', 'off': 'Off target'}
LOOK = {'match': 'Current look', 'wild': 'Free pick'}

ICON = {
    'up': '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3zM7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"/></svg>',
    'down': '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 15v4a3 3 0 0 0 3 3l4-9V2H5.72a2 2 0 0 0-2 1.7l-1.38 9a2 2 0 0 0 2 2.3zm7-13h2.67A2.31 2.31 0 0 1 22 4v7a2.31 2.31 0 0 1-2.33 2H17"/></svg>',
    'maybe': '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>',
    'heart': '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>',
}
LABEL = {'up': 'Thumbs up', 'down': 'Thumbs down', 'heart': 'Heart', 'maybe': 'Maybe'}

def react_html(key):
    return ('<div class="react" data-react="' + key + '">'
            + ''.join(f'<button type="button" class="r-{v}" data-v="{v}" aria-label="{LABEL[v]}" title="{LABEL[v]}" aria-pressed="false" disabled>{ICON[v]}</button>'
                      for v in ('up', 'down', 'heart', 'maybe')) + '</div>')

def slugify(s):
    import re
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')[:60]

def card(p, tab):
    imgs = sorted(glob.glob(f'{site}/img/{p["slug"]}_[0-9].png'))
    shots = ''.join(f'<img src="img/{os.path.basename(f)}" loading="lazy" alt="{E(p["name"])} screenshot">' for f in imgs)
    covers = ''.join(f'<li>{E(c)}</li>' for c in p['covers'])
    sc = p.get('scale')
    scale = (f'<figure class="scale"><div class="scalebox"><img src="img/{E(sc["img"])}" alt="same zoom comparison"></div>'
             f'<figcaption>{E(sc["caption"])}</figcaption></figure>') if sc else ''
    return f'''<article class="pack fit-{p["fit"]}" id="{tab}-{E(p["slug"])}">
  <header><div><h3><a href="{E(p["url"])}">{E(p["name"])}</a></h3><p class="by">by {E(p["artist"])}</p></div>
  <div class="chips">{react_html("pack:" + p["slug"])}<span class="look">{LOOK[p.get("track", "match")]}</span><span class="chip">{FIT[p["fit"]]}</span></div></header>
  {scale}
  <div class="shots">{shots}</div>
  <div class="body">
    <p class="notes">{E(p["notes"])}</p>
    <dl>
      <dt>Price</dt><dd>{E(p["price"])}</dd>
      <dt>License</dt><dd>{E(p["license"])}</dd>
      <dt>Grid</dt><dd>{E(p["size"])}</dd>
      <dt>Commission</dt><dd>{E(p["commission"])}</dd>
    </dl>
    <ul class="covers">{covers}</ul>
  </div>
</article>'''

def row(p, tab):
    return (f'<tr><td><a href="#{tab}-{E(p["slug"])}" data-jump>{E(p["name"])}</a><span class="sub">{E(p["artist"])}</span></td>'
            f'<td><span class="chip fit-{p["fit"]}">{FIT[p["fit"]]}</span></td><td>{E(p["price"])}</td>'
            f'<td>{E(p["size"])}</td><td>{E(p["commission"])}</td></tr>')

order = {'strong': 0, 'partial': 1, 'off': 2}
packs = sorted(data['packs'], key=lambda p: order[p['fit']])
TABS = [
    ('flora', 'Flora', 'Mushrooms, moss, ferns, vines and sprouts: what the decor stamps hold now.'),
    ('mine', 'Mine & machinery', 'Tiles and props for the GDD\'s derelict mine: machinery halls, pipes, scaffolds, smelters, ruins.'),
    ('crystals', 'Crystals & ore', 'Crystal clusters and ore veins. The first ore in the GDD is copper, glowing faintly in black ash.'),
    ('decor', 'Decor & props', 'Anything that makes a cave busy: roots, webs, lichen, drips, rubble, nests, eggs, husks, old machinery bits, animated clutter.'),
    ('insects', 'Insects', 'Ambient bugs at gecko-food size: crawlers on floors, walls and ceilings, fliers, swarms, and some that glow.'),
    ('slimes', 'Slimes', 'Slimes that merge and glow when they eat, engulf and drag down. Our slimes may stay procedural metaballs, so these are style reference too.'),
    ('creatures', 'Creatures', 'The ecosystem at gecko scale and up: haulers, grazers, glow slugs, cave fauna and the large animals that are dangerous the way animals are.'),
    ('bg', 'Backgrounds & windows', 'Parallax layers for the far wall, and vistas for the windows: holes in the far wall onto a hazy, lit great shaft with machinery in silhouette. Never the sky, only its light.'),
]
def panel(key):
    ps = [p for p in packs if key in p.get('themes', [])]
    gap = data.get('gaps', {}).get(key)
    gap = f'<p class="gap"><b>Gap:</b> {E(gap)}</p>' if gap else ''
    if not ps:
        return '<p class="status">Search in progress. Packs will appear here.</p>'
    return (gap + '<div class="tablebox"><table><thead><tr><th>Pack</th><th>Fit</th><th>Price</th><th>Grid</th><th>Commission</th></tr></thead><tbody>'
            + ''.join(row(p, key) for p in ps) + '</tbody></table></div><div class="packs">' + ''.join(card(p, key) for p in ps) + '</div>')
def count(key):
    return sum(key in p.get('themes', []) for p in packs)
artists = data.get('artists', [])
art_artists = [a for a in artists if a.get('kind') != 'music']
composers = [a for a in artists if a.get('kind') == 'music']
music = data.get('music', [])

def music_html(m):
    def link(u, label):
        return f'<a href="{E(u)}">{E(label)}</a>' if u else ''
    return (f'<article class="track fit-{E(m.get("fit", "partial"))}"><header><div><h3>{link(m["url"], m["title"])}</h3>'
            f'<p class="by">by {E(m["composer"])}</p></div><div class="chips">{react_html("music:" + slugify(m["title"]))}<span class="look">{E(m.get("use", ""))}</span>'
            f'<span class="chip">{FIT[m.get("fit", "partial")]}</span></div></header>'
            f'<div class="body"><p class="notes">{E(m["notes"])}</p><dl>'
            f'<dt>Price</dt><dd>{E(m["price"])}</dd><dt>License</dt><dd>{E(m["license"])}</dd>'
            f'<dt>Length</dt><dd>{E(m.get("length", ""))}</dd><dt>Listen</dt><dd>{link(m.get("listen", ""), "Listen")}</dd>'
            f'<dt>Commission</dt><dd>{E(m.get("commission", ""))}</dd></dl></div></article>')

def artist_html(a):
    return (f'<li><a href="{E(a["url"])}">{E(a["name"])}</a> <span class="sub">{E(a["where"])}</span>'
            f'<p>{E(a["notes"])}</p></li>')

stamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Underhum Art Hunt</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Pixelify+Sans:wght@500;700&family=Atkinson+Hyperlegible:wght@400;700&family=JetBrains+Mono:wght@400;600&display=swap">
<style>
/* Layout: a cave-dark single column; our reference sprites on top, then the shortlist, then one card per pack. Dark only, on purpose: the art is judged on the game's own near-black. */
:root {{
  --cave: #0c0f0b; --rock: #161b14; --ledge: #222a1e; --line: #33402c;
  --moss: #b5cd9b; --bone: #e9ecdf; --dim: #95a08a;
  --good: #9fd38a; --mid: #e3c66d; --off: #b9826f; --heart: #e8798f;
  --display: "Pixelify Sans", ui-monospace, monospace;
  --body: "Atkinson Hyperlegible", system-ui, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, monospace;
  color-scheme: dark;
}}
body {{ background: var(--cave); color: var(--bone); font: 15px/1.55 var(--body); }}
.wrap {{ max-width: 1180px; margin: 0 auto; padding-block: 32px 64px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  display: grid; gap: 40px; }}
h1, h2, h3 {{ font-family: var(--display); font-weight: 700; text-wrap: balance; margin: 0; }}
h1 {{ font-size: 2.4rem; color: var(--moss); letter-spacing: .02em; }}
h2 {{ font-size: 1.35rem; color: var(--moss); margin-bottom: 14px; }}
h3 {{ font-size: 1.15rem; }}
a {{ color: var(--bone); text-decoration-color: var(--line); text-underline-offset: 3px; }}
a:hover {{ text-decoration-color: var(--moss); }}
a:focus-visible {{ outline: 2px solid var(--moss); outline-offset: 2px; }}
p {{ margin: 0; max-width: 68ch; }}
.lede {{ display: grid; gap: 10px; }}
.status {{ font: 13px/1.4 var(--mono); color: var(--dim); }}
.spec {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 4px; }}
.spec span {{ font: 12px var(--mono); border: 1px solid var(--line); padding: 3px 8px; color: var(--dim); }}
.spec b {{ color: var(--bone); font-weight: 600; }}
.refs {{ display: flex; flex-wrap: wrap; gap: 14px; align-items: flex-end; }}
.sprite {{ margin: 0; display: grid; gap: 6px; justify-items: center; }}
.sprite .well {{ background: var(--rock); padding: 10px; display: grid; place-items: end center; min-height: 80px; }}
.sprite img, .shots img {{ image-rendering: pixelated; }}
.sprite figcaption {{ font: 12px var(--mono); color: var(--dim); display: grid; justify-items: center; }}
.sprite figcaption span {{ color: var(--bone); }}
.palette {{ display: flex; margin-top: 14px; max-width: 480px; }}
.palette i {{ flex: 1; height: 18px; }}
.tablebox {{ overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; min-width: 720px; font-size: 14px; }}
th {{ text-align: left; font: 600 11px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--dim); padding: 8px 10px; border-bottom: 1px solid var(--line); }}
td {{ padding: 10px; border-bottom: 1px solid var(--ledge); vertical-align: top; }}
.sub {{ display: block; color: var(--dim); font-size: 13px; }}
.chip {{ font: 600 11px var(--mono); letter-spacing: .06em; text-transform: uppercase; padding: 3px 8px; white-space: nowrap; border: 1px solid currentColor; }}
.fit-strong .chip, .chip.fit-strong {{ color: var(--good); }}
.fit-partial .chip, .chip.fit-partial {{ color: var(--mid); }}
.fit-off .chip, .chip.fit-off {{ color: var(--off); }}
.packs {{ display: grid; gap: 22px; }}
.pack {{ background: var(--rock); border-left: 3px solid var(--line); display: grid; }}
.pack.fit-strong {{ border-left-color: var(--good); }}
.pack.fit-partial {{ border-left-color: var(--mid); }}
.pack header {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; padding: 16px 18px 10px; }}
.by {{ color: var(--dim); font-size: 13px; }}
.shots {{ display: flex; gap: 6px; overflow-x: auto; padding: 0 18px 12px; }}
.shots img {{ height: 240px; width: auto; max-width: none; flex: none; background: var(--cave); }}
.body {{ display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr); gap: 10px 28px; padding: 4px 18px 18px; }}
.notes {{ grid-column: 1; }}
dl {{ grid-column: 2; grid-row: 1 / span 2; margin: 0; display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 4px 12px; font-size: 13.5px; }}
dt {{ font: 600 11px/1.9 var(--mono); letter-spacing: .06em; text-transform: uppercase; color: var(--dim); }}
dd {{ margin: 0; }}
.covers {{ grid-column: 1; list-style: none; padding: 0; margin: 0; display: flex; flex-wrap: wrap; gap: 6px; }}
.covers li {{ font: 12px var(--mono); background: var(--ledge); padding: 2px 8px; color: var(--moss); }}
.scale {{ margin: 0 18px 14px; display: grid; gap: 6px; }}
.scalebox {{ overflow-x: auto; }}
.scalebox img {{ image-rendering: pixelated; max-width: none; height: auto; width: auto; display: block; }}
.scale figcaption {{ font-size: 13px; color: var(--dim); max-width: 90ch; }}
.tabs {{ display: flex; flex-wrap: wrap; gap: 6px; position: sticky; top: env(safe-area-inset-top, 0px); background: var(--cave); padding-block: 10px; z-index: 5; border-bottom: 1px solid var(--line); }}
.tabs button {{ font: 600 13px var(--mono); color: var(--dim); background: var(--rock); border: 1px solid var(--ledge); padding: 7px 12px; cursor: pointer; display: inline-flex; gap: 8px; align-items: baseline; }}
.tabs button span {{ color: var(--dim); font-weight: 400; font-size: 11px; }}
.tabs button[aria-selected="true"] {{ color: var(--cave); background: var(--moss); border-color: var(--moss); }}
.tabs button[aria-selected="true"] span {{ color: var(--rock); }}
.tabs button:focus-visible {{ outline: 2px solid var(--moss); outline-offset: 2px; }}
.panel {{ scroll-margin-top: 64px; }}
.pack {{ scroll-margin-top: 64px; }}
.gap {{ border-left: 3px solid var(--mid); padding: 6px 12px; background: var(--rock); color: var(--bone); font-size: 14px; }}
.gap b {{ color: var(--mid); }}
.chips {{ display: flex; gap: 6px; flex-wrap: wrap; justify-content: flex-end; }}
.look {{ font: 11px var(--mono); color: var(--dim); padding: 3px 8px; background: var(--ledge); white-space: nowrap; }}
.top-tabs {{ display: flex; gap: 0; border-bottom: 2px solid var(--line); }}
.top-tabs button {{ font: 700 1.5rem var(--display); color: var(--dim); background: none; border: 0; border-bottom: 3px solid transparent; margin-bottom: -2px; padding: 6px 22px 8px 0; cursor: pointer; display: inline-flex; gap: 10px; align-items: baseline; }}
.top-tabs button span {{ font: 400 12px var(--mono); color: var(--dim); }}
.top-tabs button[aria-selected="true"] {{ color: var(--moss); border-bottom-color: var(--moss); }}
.top-tabs button:focus-visible {{ outline: 2px solid var(--moss); outline-offset: 2px; }}
.top-panel {{ display: grid; gap: 28px; }}
.now {{ display: grid; gap: 10px; }}
.now summary {{ font: 700 1.1rem var(--display); color: var(--moss); cursor: pointer; }}
[hidden] {{ display: none !important; }}
.jump {{ display: flex; flex-wrap: wrap; gap: 8px 20px; font: 600 13px var(--mono); position: sticky; top: env(safe-area-inset-top, 0px); background: var(--cave); padding-block: 10px; z-index: 5; border-bottom: 1px solid var(--ledge); }}
.jump a {{ text-decoration: none; color: var(--moss); }}
.eyebrow {{ font: 600 11px var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--dim); }}
section {{ display: grid; gap: 14px; scroll-margin-top: 48px; }}
section h2 {{ margin-bottom: 0; }}
.subtabs {{ display: flex; gap: 0; border-bottom: 1px solid var(--line); }}
.subtabs button {{ font: 600 13px var(--mono); background: none; border: 0; border-bottom: 2px solid transparent; color: var(--dim); padding: 8px 14px; cursor: pointer; display: inline-flex; gap: 8px; align-items: baseline; }}
.subtabs button span {{ font-weight: 400; font-size: 11px; }}
.subtabs button[aria-selected="true"] {{ color: var(--moss); border-bottom-color: var(--moss); }}
.subtabs button:focus-visible {{ outline: 2px solid var(--moss); outline-offset: 2px; }}


.picks {{ display: grid; gap: 10px; }}
.pick {{ display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr); gap: 12px; background: var(--rock); border-left: 3px solid var(--line); padding: 12px; }}
.pick-left {{ display: grid; gap: 8px; align-content: start; min-width: 0; }}
.pick input, .pick textarea {{ width: 100%; box-sizing: border-box; background: var(--cave); color: var(--bone); border: 1px solid var(--ledge); padding: 8px 10px; font: 14px/1.45 var(--body); }}
.pick input {{ font-family: var(--mono); font-size: 13px; }}
.pick textarea {{ resize: vertical; min-height: 76px; }}
.pick input:focus, .pick textarea:focus {{ outline: 2px solid var(--moss); outline-offset: 0; border-color: var(--moss); }}
.pick-actions {{ display: flex; gap: 14px; align-items: center; font: 12px var(--mono); }}
.pick-actions .open {{ color: var(--moss); }}
.pick-actions .remove {{ background: none; border: 0; color: var(--dim); font: inherit; cursor: pointer; padding: 0; }}
.pick-actions .remove:hover, .pick-actions .remove:focus-visible {{ color: var(--off); }}
.add {{ justify-self: start; font: 600 13px var(--mono); background: var(--moss); color: var(--cave); border: 0; padding: 9px 16px; cursor: pointer; }}
.add:disabled {{ opacity: .5; cursor: default; }}
.add:focus-visible {{ outline: 2px solid var(--bone); outline-offset: 2px; }}
.sr {{ position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }}
.track {{ background: var(--rock); border-left: 3px solid var(--line); display: grid; }}
.track.fit-strong {{ border-left-color: var(--good); }}
.track.fit-partial {{ border-left-color: var(--mid); }}
.track header {{ display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; padding: 16px 18px 6px; }}
@media (max-width: 720px) {{ .pick {{ grid-template-columns: minmax(0, 1fr); }} }}
.react {{ display: inline-flex; gap: 2px; }}
.react button {{ background: none; border: 0; padding: 4px; cursor: pointer; color: var(--dim); line-height: 0; }}
.react button:disabled {{ cursor: default; opacity: .35; }}
.react svg {{ width: 17px; height: 17px; fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }}
.react button:not(:disabled):hover {{ color: var(--bone); }}
.react button:focus-visible {{ outline: 2px solid var(--moss); outline-offset: 1px; }}
.react .r-up[aria-pressed="true"] {{ color: var(--good); }}
.react .r-up[aria-pressed="true"] svg, .react .r-down[aria-pressed="true"] svg, .react .r-heart[aria-pressed="true"] svg {{ fill: currentColor; }}
.react .r-down[aria-pressed="true"] {{ color: var(--off); }}
.react .r-heart[aria-pressed="true"] {{ color: var(--heart); }}
.react .r-maybe[aria-pressed="true"] {{ color: var(--mid); }}
.react .r-maybe[aria-pressed="true"] svg {{ stroke-width: 2.6; }}
.no-react .react {{ display: none; }}
.chips {{ align-items: center; }}
.pick-left .react {{ justify-self: start; }}
.pick-player:empty {{ display: none; }}
.pick-player audio {{ width: 100%; max-width: 560px; height: 40px; display: block; color-scheme: dark; }}
.filter input[type=range] {{ width: 140px; accent-color: var(--moss); }}
.pick-player iframe.bc {{ border: 0; width: 100%; max-width: 560px; height: 120px; display: block; }}
.pick-player iframe.yt {{ border: 0; width: 100%; max-width: 420px; aspect-ratio: 16 / 9; display: block; }}
.pick-bar {{ display: flex; flex-wrap: wrap; gap: 8px 20px; align-items: center; justify-content: space-between; }}
.filter {{ font: 12px var(--mono); color: var(--dim); display: inline-flex; gap: 8px; align-items: center; }}
.filter select {{ background: var(--rock); color: var(--bone); border: 1px solid var(--ledge); padding: 5px 8px; font: 13px var(--mono); }}
.pick-group {{ font: 600 12px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--moss); margin: 14px 0 0; padding-bottom: 4px; border-bottom: 1px solid var(--ledge); }}
.pick-group[hidden], .pick[hidden] {{ display: none; }}
.pick-info {{ display: none; }}
.pick.fixed .pick-info {{ display: grid; gap: 2px; }}
.pick.fixed input, .pick.fixed label[for^="u-"] {{ display: none; }}
.pick-title {{ font-weight: 700; color: var(--bone); }}
.pick-meta {{ font: 12px var(--mono); color: var(--dim); }}
.pick.fixed {{ padding: 10px 12px; }}
.pick.fixed textarea {{ min-height: 52px; }}
.artists {{ list-style: none; padding: 0; margin: 0; display: grid; gap: 14px; }}
.artists p {{ color: var(--dim); font-size: 14px; }}
.cutter {{ display: grid; grid-template-columns: 230px minmax(0, 1fr); gap: 18px; align-items: start; }}
.cut-sheets {{ position: sticky; top: 8px; max-height: calc(100vh - 16px); overflow: auto; display: grid; gap: 14px; padding-right: 4px; }}
.cut-pack h3 {{ font: 600 12px var(--mono); letter-spacing: .06em; text-transform: uppercase; color: var(--moss); }}
.cut-lic summary {{ font: 11px var(--mono); color: var(--dim); cursor: pointer; }}
.cut-lic pre {{ white-space: pre-wrap; font: 11px/1.4 var(--mono); color: var(--dim); margin: 4px 0 6px; }}
.cut-sheet {{ display: grid; grid-template-columns: 44px minmax(0, 1fr) auto; gap: 8px; align-items: center; width: 100%; text-align: left; background: var(--rock); border: 1px solid var(--ledge); color: var(--bone); padding: 4px 6px; margin-top: 4px; cursor: pointer; font: 12px var(--mono); }}
.cut-sheet img {{ width: 44px; height: 32px; object-fit: contain; image-rendering: pixelated; background: var(--cave); }}
.cut-sheet .t {{ overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }}
.cut-sheet .n {{ color: var(--cave); background: var(--moss); padding: 0 6px; font-weight: 600; }}
.cut-sheet .n:empty {{ display: none; }}
.cut-sheet[aria-current="true"] {{ border-color: var(--moss); background: var(--ledge); }}
.cut-sheet:focus-visible, .seg button:focus-visible, .cut-tile:focus-visible {{ outline: 2px solid var(--moss); outline-offset: 1px; }}
.bench {{ display: grid; gap: 10px; min-width: 0; }}
.cut-bar {{ display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px 16px; align-items: end; }}
.cut-bar h3 {{ overflow-wrap: anywhere; }}
.cut-tools {{ display: flex; flex-wrap: wrap; gap: 8px 14px; align-items: center; }}
.seg {{ display: inline-flex; align-items: center; border: 1px solid var(--ledge); }}
.seg button {{ background: var(--rock); color: var(--bone); border: 0; padding: 6px 10px; font: 600 12px var(--mono); cursor: pointer; }}
.seg button[aria-pressed="true"] {{ background: var(--moss); color: var(--cave); }}
.seg output {{ font: 12px var(--mono); padding: 0 8px; color: var(--dim); min-width: 3ch; text-align: center; }}
.cut-hint {{ font-size: 13px; color: var(--dim); }}
.cut-hint kbd {{ font: 11px var(--mono); border: 1px solid var(--line); padding: 0 4px; color: var(--bone); }}
.cut-stage {{ overflow: auto; max-height: 72vh; border: 1px solid var(--line); background: var(--cave); }}
.cut-stage[data-bg="check"] {{ background: repeating-conic-gradient(#2a2f28 0 25%, #1c201b 0 50%) 0 0 / 16px 16px; }}
.cut-stage[data-bg="light"] {{ background: #cfd3c6; }}
.cut-layer {{ position: relative; }}
.cut-layer canvas {{ position: absolute; left: 0; top: 0; image-rendering: pixelated; }}
#cut-over {{ cursor: crosshair; touch-action: none; }}
.cut-list {{ display: grid; gap: 8px; }}
.cut {{ display: grid; grid-template-columns: minmax(0, 240px) minmax(0, 1fr); gap: 12px; background: var(--rock); border-left: 3px solid var(--hue, var(--line)); padding: 10px; }}
.cut.on {{ outline: 1px solid var(--bone); }}
.cut-thumb {{ display: grid; place-items: center; background: var(--cave); min-height: 60px; padding: 6px; }}
.cut-thumb canvas, .cut-tile canvas {{ image-rendering: pixelated; display: block; }}
.cut-fields {{ display: grid; gap: 6px; align-content: start; }}
.cut-head {{ display: flex; gap: 10px; align-items: baseline; font: 12px var(--mono); color: var(--dim); }}
.cut-head b {{ color: var(--hue); }}
.cut-del {{ margin-left: auto; background: none; border: 0; color: var(--dim); font: 12px var(--mono); cursor: pointer; }}
.cut-del:hover, .cut-del:focus-visible {{ color: var(--off); }}
.cut label {{ font: 12px var(--mono); color: var(--dim); display: flex; gap: 8px; align-items: center; }}
.cut select, .cut textarea {{ background: var(--cave); color: var(--bone); border: 1px solid var(--ledge); padding: 5px 8px; font: 13px var(--body); }}
.cut textarea {{ width: 100%; box-sizing: border-box; resize: vertical; }}
.cut select:focus, .cut textarea:focus {{ outline: 2px solid var(--moss); outline-offset: 0; }}
.cut-group h3 {{ font: 600 12px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--moss); margin: 12px 0 6px; }}
.cut-group h3 span {{ color: var(--dim); }}
.cut-tiles {{ display: flex; flex-wrap: wrap; gap: 6px; }}
.cut-tile {{ background: var(--rock); border: 1px solid var(--ledge); padding: 6px; cursor: pointer; display: grid; place-items: center; min-width: 40px; min-height: 40px; }}
.cut-tile:hover {{ border-color: var(--moss); }}
@media (max-width: 820px) {{ .cutter {{ grid-template-columns: minmax(0, 1fr); }} .cut-sheets {{ position: static; max-height: 260px; }} .cut {{ grid-template-columns: minmax(0, 1fr); }} }}
@media (max-width: 720px) {{
  .body {{ grid-template-columns: minmax(0, 1fr); }}
  dl, .notes, .covers {{ grid-column: 1; grid-row: auto; }}
  .shots img {{ height: 180px; }}
  h1 {{ font-size: 1.9rem; }}
}}
</style>
<div class="wrap">
<header class="lede">
  <h1>Underhum Art Hunt</h1>
  <p>Human-made art and music that could replace the Retro Diffusion placeholders: packs to buy, music to license, and artists and composers to commission.</p>
  <p class="status">{E(data["status"])} Updated {stamp}.</p>
</header>

<nav class="top-tabs" role="tablist" aria-label="Sections" data-group="top">
  <button role="tab" id="top-art" aria-controls="art">Art<span>{len(packs)} packs</span></button>
  <button role="tab" id="top-music" aria-controls="music">Music<span>{len(music)} researched</span></button>
  <button role="tab" id="top-downloaded" aria-controls="downloaded">Downloaded<span>{n_sheets} sheets</span></button>
</nav>

<div class="top-panel" id="art" role="tabpanel" aria-labelledby="top-art">
<details class="now" open>
  <summary>What we have now</summary>
  <p>The current Retro Diffusion sprites at {ZOOM}x, which is how big they are on screen (1 art pixel = 1 terrain cell = 2 world px = 4 screen px).</p>
  <div class="spec">
    <span><b>12 to 32 px</b> per sprite</span><span><b>side view</b></span><span><b>flat colour</b>, 2 to 4 shades</span>
    <span><b>coloured outlines</b>, not black</span><span><b>16-colour</b> sage palette</span><span>reads like a <b>16x16 tile</b> set</span>
  </div>
  <div class="refs" style="margin-top:18px">{ref_html()}</div>
  <div class="palette" title="decor/palette.png">{palette_html()}</div>
</details>
<div class="tabs" role="tablist" aria-label="Art themes" data-group="art">
  {"".join(f'<button role="tab" id="tab-{k}" aria-controls="{k}">{E(n)}<span>{count(k)}</span></button>' for k, n, _ in TABS)}
  <button role="tab" id="tab-artists" aria-controls="artists">Artists<span>{len(art_artists)}</span></button>
</div>
{"".join(f'<section class="panel" role="tabpanel" id="{k}" aria-labelledby="tab-{k}"><h2>{E(n)}</h2><p>{E(intro)}</p>{panel(k)}</section>' for k, n, intro in TABS)}
<section class="panel" role="tabpanel" id="artists" aria-labelledby="tab-artists">
  <h2>Artists to commission</h2>
  <ul class="artists">{"".join(artist_html(a) for a in art_artists)}</ul>
</section>
</div>

<div class="top-panel" id="music" role="tabpanel" aria-labelledby="top-music">
<div class="tabs" role="tablist" aria-label="Music" data-group="music">
  <button role="tab" id="tab-my-picks" aria-controls="my-picks">My picks</button>
  <button role="tab" id="tab-research" aria-controls="research">Research<span>{len(music)}</span></button>
  <button role="tab" id="tab-composers" aria-controls="composers">Composers<span>{len(composers)}</span></button>
</div>
<section class="panel" role="tabpanel" id="my-picks" aria-labelledby="tab-my-picks">
  <h2>My picks</h2>
  <p>Paste a link on the left and write notes on the right. YouTube links get a player; each row saves as you type, and Claude can read the list.</p>
  <div class="pick-bar"><p class="status" id="picks-status">Connecting to saved picks...</p>
    <label class="filter">Show <select id="pick-filter"><option value="all">All</option><option value="up">Thumbs up</option><option value="heart">Hearted</option><option value="maybe">Maybe</option><option value="down">Thumbs down</option><option value="none">Not rated yet</option><option value="notes">With notes</option></select></label>
    <label class="filter">Volume <input type="range" id="pick-volume" min="0" max="1" step="0.05" value="0.8"></label></div>
  <div class="picks" id="picks"></div>
  <button type="button" class="add" id="add-pick" disabled>Add a row</button>
</section>
<section class="panel" role="tabpanel" id="research" aria-labelledby="tab-research">
  <h2>Research</h2>
  <p>Royalty-free music by human composers that could fit the climb: deep ambient for the bands, machinery rooms, nests, the ending. No AI music.</p>
  {"<div class='packs'>" + "".join(music_html(m) for m in music) + "</div>" if music else "<p class='status'>Search in progress. Tracks will appear here.</p>"}
</section>
<section class="panel" role="tabpanel" id="composers" aria-labelledby="tab-composers">
  <h2>Composers to commission</h2>
  <ul class="artists">{"".join(artist_html(a) for a in composers)}</ul>
</section>
</div>

<div class="top-panel" id="downloaded" role="tabpanel" aria-labelledby="top-downloaded">
<section>
  <h2>Downloaded packs</h2>
  <p>Every sheet from the packs kept in art/packs. Drag around a sprite to circle it, or switch to Box and drag a rectangle. Only the visible pixels inside the outline are taken. Pick what each cut should become and add a note, and Claude puts them into the game.</p>
  <p class="cut-hint">Click a cut to select it; <kbd>Delete</kbd> removes it, <kbd>Esc</kbd> lets go. <kbd>Ctrl</kbd> + wheel or <kbd>+</kbd> <kbd>-</kbd> zoom, <kbd>L</kbd> lasso, <kbd>B</kbd> box. Game palette shows the colours the game would snap them to.</p>
</section>
<div class="cutter">
  <nav class="cut-sheets" id="cut-sheets" aria-label="Sheets"></nav>
  <div class="bench">
    <div class="cut-bar">
      <div><h3 id="cut-title">Pick a sheet</h3><p class="status" id="cut-meta"></p></div>
      <div class="cut-tools">
        <span class="seg" aria-label="Tool"><button type="button" data-tool="lasso" aria-pressed="true">Lasso</button><button type="button" data-tool="box" aria-pressed="false">Box</button></span>
        <span class="seg" aria-label="Zoom"><button type="button" id="cut-outz" aria-label="Zoom out">-</button><output id="cut-zoom">1x</output><button type="button" id="cut-in" aria-label="Zoom in">+</button><button type="button" id="cut-fit">Fit</button></span>
        <label class="filter"><input type="checkbox" id="cut-pal"> Game palette</label>
        <label class="filter">Backdrop <select id="cut-bg"><option value="cave">Cave</option><option value="check">Checker</option><option value="light">Light</option></select></label>
      </div>
    </div>
    <div class="cut-stage" id="cut-stage"><div class="cut-layer" id="cut-layer"><canvas id="cut-base"></canvas><canvas id="cut-over"></canvas></div></div>
    <p class="status" id="cut-status">Connecting to saved cuts...</p>
    <h3>Cuts on this sheet</h3>
    <p class="status" id="cut-empty">None yet. Drag around a sprite to circle it.</p>
    <div class="cut-list" id="cut-list"></div>
  </div>
</div>
<section>
  <h2>All cuts <span class="status" id="cut-count">0</span></h2>
  <p>Grouped by what they should become. Click one to find it on its sheet.</p>
  <div id="cut-all"></div>
</section>
</div>
<script type="application/json" id="assets-data">{assets_json}</script>
<script>
// Tabs: each tablist with data-group switches its own panels; a hash names any panel and opens the tabs leading to it.
(function () {{
  function activate(btn, save) {{
    var list = btn.closest('[role=tablist]');
    list.querySelectorAll('[role=tab]').forEach(function (b) {{
      var on = b === btn;
      b.setAttribute('aria-selected', on);
      document.getElementById(b.getAttribute('aria-controls')).hidden = !on;
    }});
    if (save) {{ try {{ localStorage.setItem('tab:' + list.dataset.group, btn.getAttribute('aria-controls')); }} catch (e) {{}} }}
  }}
  function open(id) {{
    var btn = document.querySelector('[role=tab][aria-controls="' + id + '"]');
    if (!btn) return;
    var outer = btn.closest('.top-panel');
    if (outer) open(outer.id);
    activate(btn, true);
  }}
  document.querySelectorAll('[role=tablist][data-group] [role=tab]').forEach(function (b) {{
    b.addEventListener('click', function () {{
      activate(b, true);
      try {{ history.replaceState(null, '', '#' + b.getAttribute('aria-controls')); }} catch (e) {{}}
    }});
  }});
  document.querySelectorAll('[role=tablist][data-group]').forEach(function (l) {{
    var saved = null;
    try {{ saved = localStorage.getItem('tab:' + l.dataset.group); }} catch (e) {{}}
    activate((saved && l.querySelector('[aria-controls="' + saved + '"]')) || l.querySelector('[role=tab]'), false);
  }});
  var h = location.hash.slice(1);
  if (h) open(h);
}})();
</script>
<script src="store.js"></script>
<script src="cutter.js"></script>
<script>
var REACT_TPL = {json.dumps(react_html('KEY'))};
(async function () {{
  var map = new Map();
  var db = null;
  try {{ db = await getDb(); }} catch (e) {{ db = null; }}
  if (!db) {{ document.body.classList.add('no-react'); return; }}
  var col = db.collection('reactions');
  function paint(el) {{
    var s = map.get(el.dataset.react) || {{}};
    el.querySelectorAll('button').forEach(function (b) {{
      var v = b.dataset.v;
      b.disabled = false;
      b.setAttribute('aria-pressed', v === 'heart' ? !!s.heart : s.vote === v);
    }});
  }}
  function paintAll() {{ document.querySelectorAll('[data-react]').forEach(paint); }}
  window.__react = {{ paintAll: paintAll, state: function (k) {{ return map.get(k); }} }};
  var busy = new Map();
  document.addEventListener('click', async function (ev) {{
    var b = ev.target.closest('[data-react] button');
    if (!b) return;
    var key = b.closest('[data-react]').dataset.react;
    var s = Object.assign({{ vote: null, heart: false }}, map.get(key) || {{}});
    if (b.dataset.v === 'heart') s.heart = !s.heart;
    else s.vote = s.vote === b.dataset.v ? null : b.dataset.v;
    map.set(key, s);
    document.querySelectorAll('[data-react="' + key + '"]').forEach(paint);
    if (window.__pickFilter) window.__pickFilter();
    if (busy.get(key)) {{ busy.set(key, 'again'); return; }}
    busy.set(key, true);
    while (true) {{
      var cur = map.get(key);
      try {{ await col.doc(key).set({{ vote: cur.vote, heart: cur.heart, updated: Date.now() }}); }} catch (e) {{}}
      if (busy.get(key) === 'again') {{ busy.set(key, true); continue; }}
      break;
    }}
    busy.delete(key);
  }});
  col.onSnapshot(function (snap) {{
    snap.docChanges().forEach(function (c) {{
      if (busy.get(c.doc.id)) return;
      if (c.type === 'removed') map.delete(c.doc.id); else map.set(c.doc.id, c.doc.data());
    }});
    paintAll();
    if (window.__pickFilter) window.__pickFilter();
  }}, function () {{}});
  paintAll();
}})();
</script>
<script>
(async function () {{
  var list = document.getElementById('picks');
  var add = document.getElementById('add-pick');
  var status = document.getElementById('picks-status');
  var db = null;
  try {{ db = await getDb(); }} catch (e) {{ db = null; }}
  if (!db) {{ status.textContent = 'Saving is not available.'; return; }}
  var where = db.mode() === 'server' ? 'saved to docs/art_hunt/state.json' : 'saved in this browser only (run tools/art_hunt_serve.py to save to the repo)';
  var col = db.collection('music_picks');
  var rows = new Map();
  var focusNext = null;

  function ytEmbed(u) {{
    var m = /(?:youtu\\.be\\/|[?&]v=|embed\\/|shorts\\/)([\\w-]{{11}})/.exec(u || '');
    return m ? 'https://www.youtube-nocookie.com/embed/' + m[1] : '';
  }}
  function bcLarge(embed) {{ return embed.replace('/size=small/', '/size=large/tracklist=false/artwork=small/'); }}
  var volInput = document.getElementById('pick-volume');
  try {{ var savedVol = localStorage.getItem('art_hunt_volume'); if (savedVol !== null) volInput.value = savedVol; }} catch (e) {{}}
  function volume() {{ return Number(volInput.value); }}
  volInput.addEventListener('input', function () {{
    list.querySelectorAll('audio').forEach(function (a) {{ a.volume = volume(); }});
    try {{ localStorage.setItem('art_hunt_volume', volInput.value); }} catch (e) {{}}
  }});
  // one track at a time; when one ends, the next visible track plays
  list.addEventListener('play', function (e) {{
    list.querySelectorAll('audio').forEach(function (a) {{ if (a !== e.target) a.pause(); }});
  }}, true);
  list.addEventListener('ended', function (e) {{
    var all = Array.prototype.filter.call(list.querySelectorAll('audio'), function (a) {{ return a.closest('.pick').offsetParent !== null; }});
    var next = all[all.indexOf(e.target) + 1];
    if (next) {{ next.closest('.pick').scrollIntoView({{ block: 'center', behavior: 'smooth' }}); next.play(); }}
  }}, true);
  function isLink(u) {{ return /^https?:\\/\\//i.test(u || ''); }}

  function makeRow(id, v) {{
    var ref = col.doc(id);
    var el = document.createElement('div');
    el.className = 'pick';
    el.innerHTML = '<div class="pick-left"><div class="pick-info"><div class="pick-title"></div><div class="pick-meta"></div></div><div class="pick-player"></div>' +
      '<label class="sr" for="u-' + id + '">Link</label>' +
      '<input id="u-' + id + '" type="url" placeholder="https://www.youtube.com/watch?v=..." autocomplete="off">' +
      '<div class="pick-actions"><a class="open" target="_blank" rel="noopener">Open link</a>' +
      '<button type="button" class="remove">Remove</button></div>' + REACT_TPL.replace('KEY', 'pick:' + id) + '</div>' +
      '<div class="pick-right"><label class="sr" for="n-' + id + '">Notes</label>' +
      '<textarea id="n-' + id + '" rows="3" placeholder="What fits: mood, where in the game, what to ask the composer"></textarea></div>';
    var url = el.querySelector('input'), notes = el.querySelector('textarea');
    var open = el.querySelector('.open'), remove = el.querySelector('.remove');
    var row = {{ el: el, url: url, notes: notes, open: open, timer: 0, saving: false, dirty: false, key: 'pick:' + id, group: v.group || 'Added by you' }};
    if (v.title) {{
      el.classList.add('fixed');
      el.querySelector('.pick-title').textContent = v.title;
      el.querySelector('.pick-meta').textContent = [v.release, v.dur].filter(Boolean).join(' · ');
      open.textContent = 'Listen';
    }}
    var slot = el.querySelector('.pick-player'), shownSrc = '';
    function player() {{
      var u = url.value.trim();
      var bc = !!v.embed && u === v.url;
      // Bandcamp rows play in the browser's own player (timeline and volume) through the local
      // server's stream lookup; without the server, Bandcamp's large embed (timeline, no volume)
      var src = bc ? (db.mode() === 'server' ? 'api/bc-stream?u=' + encodeURIComponent(u) : bcLarge(v.embed)) : ytEmbed(u);
      if (src === shownSrc) return;
      shownSrc = src; slot.textContent = '';
      if (!src) return;
      if (bc && db.mode() === 'server') {{
        var au = document.createElement('audio');
        au.controls = true; au.preload = 'none'; au.src = src; au.volume = volume();
        au.addEventListener('error', function () {{ slot.textContent = ''; slot.appendChild(frame(bcLarge(v.embed))); }}, {{ once: true }});
        slot.appendChild(au);
        return;
      }}
      slot.appendChild(frame(src));
    }}
    function frame(src) {{
      var fr = document.createElement('iframe');
      fr.loading = 'lazy'; fr.src = src; fr.title = v.title || 'Player';
      fr.className = src.indexOf('bandcamp') >= 0 ? 'bc' : 'yt';
      if (fr.className === 'yt') {{ fr.allow = 'encrypted-media; picture-in-picture; fullscreen'; fr.allowFullscreen = true; }}
      return fr;
    }}
    url.addEventListener('change', player);
    row.player = player;
    function sync() {{
      var ok = isLink(url.value.trim());
      open.hidden = !ok;
      if (ok) open.href = url.value.trim();
    }}
    async function save() {{
      if (row.saving) {{ row.dirty = true; return; }}
      row.saving = true;
      try {{
        await ref.update({{ url: url.value.trim(), notes: notes.value }});
        status.textContent = 'Saved.';
      }} catch (e) {{
        status.textContent = e && e.code === 'invalid_argument' ? 'This view can read picks but not change them.' : 'Could not save just now; your text is still here.';
      }}
      row.saving = false;
      if (row.dirty) {{ row.dirty = false; save(); }}
    }}
    function queue() {{ sync(); clearTimeout(row.timer); row.timer = setTimeout(save, 700); status.textContent = 'Saving...'; }}
    url.addEventListener('input', queue);
    notes.addEventListener('input', queue);
    url.addEventListener('blur', function () {{ if (row.timer) {{ clearTimeout(row.timer); row.timer = 0; save(); }} }});
    notes.addEventListener('blur', function () {{ if (row.timer) {{ clearTimeout(row.timer); row.timer = 0; save(); }} }});
    var armed = 0;
    remove.addEventListener('click', async function () {{
      if (!armed) {{
        remove.textContent = 'Click again to remove';
        armed = setTimeout(function () {{ armed = 0; remove.textContent = 'Remove'; }}, 3000);
        return;
      }}
      clearTimeout(armed);
      try {{ await ref.delete(); }} catch (e) {{ status.textContent = 'Could not remove that row.'; return; }}
      try {{ await db.collection('reactions').doc('pick:' + id).delete(); }} catch (e) {{}}
    }});
    row.sync = sync;
    return row;
  }}

  var heads = new Map();
  var filter = document.getElementById('pick-filter');
  function applyFilter() {{
    var f = filter.value, st = window.__react ? window.__react.state : function () {{ return null; }};
    var shown = new Map();
    rows.forEach(function (row) {{
      var s = st(row.key) || {{}};
      var ok = f === 'all' || (f === 'up' && s.vote === 'up') || (f === 'heart' && s.heart) || (f === 'maybe' && s.vote === 'maybe') ||
        (f === 'down' && s.vote === 'down') || (f === 'none' && !s.vote && !s.heart) || (f === 'notes' && row.notes.value.trim());
      row.el.hidden = !ok;
      if (ok) shown.set(row.group, true);
    }});
    heads.forEach(function (h, g) {{ h.hidden = !shown.get(g); }});
  }}
  window.__pickFilter = applyFilter;
  filter.addEventListener('change', applyFilter);
  col.orderBy('created').onSnapshot(function (snap) {{
    var seen = new Set(), usedHeads = new Set(), prev = null, at = 0;
    // move a node only when it is out of place, so a focused field keeps its focus
    function place(node) {{ if (list.children[at] !== node) list.insertBefore(node, list.children[at] || null); at++; }}
    snap.docs.forEach(function (d) {{
      seen.add(d.id);
      var v = d.data() || {{}};
      var row = rows.get(d.id);
      if (!row) {{ row = makeRow(d.id, v); rows.set(d.id, row); }}
      var g = v.group || 'Added by you';
      if (g && g !== prev) {{
        var h = heads.get(g);
        if (!h) {{ h = document.createElement('h3'); h.className = 'pick-group'; h.textContent = g; heads.set(g, h); }}
        place(h); usedHeads.add(g);
      }}
      prev = g;
      if (document.activeElement !== row.url && !row.timer && row.url.value !== (v.url || '')) row.url.value = v.url || '';
      if (document.activeElement !== row.notes && !row.timer && row.notes.value !== (v.notes || '')) row.notes.value = v.notes || '';
      row.sync(); row.player();
      place(row.el);
    }});
    rows.forEach(function (row, id) {{ if (!seen.has(id)) {{ row.el.remove(); rows.delete(id); }} }});
    heads.forEach(function (h, g) {{ if (!usedHeads.has(g)) {{ h.remove(); heads.delete(g); }} }});
    if (window.__react) window.__react.paintAll();
    applyFilter();
    if (focusNext && rows.has(focusNext)) {{ rows.get(focusNext).url.focus(); focusNext = null; }}
    add.disabled = false;
    status.textContent = snap.empty ? 'No picks yet. Add the first row.' : snap.size + (snap.size === 1 ? ' pick' : ' picks') + ', ' + where + '.';
  }}, function (e) {{
    status.textContent = 'Picks stopped updating. Reload the page to reconnect.';
  }});

  add.addEventListener('click', async function () {{
    add.disabled = true;
    var ref = col.doc();
    focusNext = ref.id;
    try {{ await ref.set({{ url: '', notes: '', created: Date.now() }}); }}
    catch (e) {{ status.textContent = e && e.code === 'quota_exceeded' ? 'The list is full; remove a row first.' : 'Could not add a row in this view.'; focusNext = null; }}
    add.disabled = false;
  }});
}})();
</script>
</div>
'''
open(f'{site}/index.html', 'w').write(page.replace('<div class="wrap">', '</head><body><div class="wrap">', 1) + '</body></html>\n')
print('ok', len(packs), 'packs')
