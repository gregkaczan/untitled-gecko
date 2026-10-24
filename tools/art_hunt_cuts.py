# Crops the sprites circled on the art hunt page's Downloaded tab out of
# their sheets: for each cut in docs/art_hunt/state.json, the pixels whose
# centre lies inside the outline and that are not see-through (the page's
# cutter.js takes the same ones), trimmed to their box. Writes them to
# docs/art_hunt/cuts/<use>/<sheet>_<id>.png and lists them in
# docs/art_hunt/cuts/cuts.json with their notes, ready to go into the game.
#
#   python3 -I tools/art_hunt_cuts.py
import json, os, re, shutil
from PIL import Image

SITE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'art_hunt')
OUT = os.path.join(SITE, 'cuts')


def inside(pts, x, y):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[j]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            c = not c
        j = i
    return c


def crop(im, pts):
    w, h = im.size
    px = im.load()
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    keep = [(x, y) for y in range(max(0, int(min(ys))), min(h, int(max(ys)) + 1))
            for x in range(max(0, int(min(xs))), min(w, int(max(xs)) + 1))
            if px[x, y][3] and inside(pts, x + 0.5, y + 0.5)]
    if not keep:
        return None, None
    x0, y0 = min(k[0] for k in keep), min(k[1] for k in keep)
    x1, y1 = max(k[0] for k in keep), max(k[1] for k in keep)
    out = Image.new('RGBA', (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    op = out.load()
    for x, y in keep:
        op[x - x0, y - y0] = px[x, y]
    return out, (x0, y0)


def main():
    state = json.load(open(os.path.join(SITE, 'state.json'), encoding='utf-8'))
    sheets = {s['id']: s for p in json.load(open(os.path.join(SITE, 'assets.json'), encoding='utf-8'))['packs'] for s in p['sheets']}
    cuts = sorted(state.get('cuts', {}).items(), key=lambda kv: kv[1].get('created', 0))
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    ims, listed = {}, []
    for cid, d in cuts:
        s = sheets.get(d.get('sheet'))
        if not s:
            print(f'{cid}: sheet {d.get("sheet")} is gone, skipped')
            continue
        if s['id'] not in ims:
            ims[s['id']] = Image.open(os.path.join(SITE, s['file'])).convert('RGBA')
        out, at = crop(ims[s['id']], d['pts'])
        if not out:
            continue
        use = d.get('use') or 'unsorted'
        os.makedirs(os.path.join(OUT, use), exist_ok=True)
        rel = f'{use}/{re.sub(r"[^a-z0-9]+", "-", s["id"].lower()).strip("-")}_{cid}.png'
        out.save(os.path.join(OUT, rel))
        listed.append({'id': cid, 'file': rel, 'use': use, 'notes': d.get('notes', ''), 'sheet': s['id'], 'at': at, 'size': out.size})
    with open(os.path.join(OUT, 'cuts.json'), 'w', encoding='utf-8') as f:
        json.dump(listed, f, indent=1, ensure_ascii=False)
    print(f'{len(listed)} cut(s) in {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
