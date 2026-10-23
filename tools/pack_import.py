# Brings the bought and free packs' sprites into the game: the pieces the
# user circled on the art hunt page's Downloaded tab (docs/art_hunt,
# state.json "cuts", cut from the keyed sheets in assets/) made into
# decor stamps, each pack's colours into a palette of its own for the
# bands of the climb (decor_palettes.gd), and the creatures' sheets
# copied as they are.
#
#   python3 -I tools/pack_import.py manifest <art hunt dir>   # the cuts into decor/packs.json
#   python3 -I tools/pack_import.py build <art hunt dir> <Mycelium.zip>
#
# manifest takes each cut's outline from the page's state, in the order
# it was drawn, and gives it its name and use (TABLE below); build reads
# decor/packs.json and the sheets and writes
#   decor/palettes/<pack>.png      16 colours, dark to light: the pack's
#                                  own, the least used merged into their
#                                  nearest kin (Ward) when there are more
#   decor/stamps/<pack>/<name>.png the cut in its palette's colours, with
#                                  <name>.glow.png beside it where the
#                                  pack's emission map lights it
#   decor/critters/<name>.png      a creature's sheet (worm, jellyfish)
# Shrooms come in three heights: the stem's rows dropped or doubled
# evenly (takes 10 up short, 20 up tall), the cap kept to the pixel. Curtains are cut
# into a left end, a middle that tiles with itself and a right end (_l,
# _m, _r) for the editor's brush. Hanging art is stored upside down, its
# top as the bottom row, so a ceiling stamp (turned over) hangs it as
# drawn. The mycelium's near-black navy is lifted so its caps and stems
# read on the cave's dark, and a stem's navy half goes to the mid blue,
# so the stem reads as one line instead of dots.
import json, os, sys, zipfile, io, shutil
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
DECOR = os.path.join(ROOT, 'decor')
MANIFEST = os.path.join(DECOR, 'packs.json')

# Per sheet, per cut in the order drawn: [name, use, options]. Uses:
# shroom (a stamp the particle world makes a shroom that bends), plant
# (the same, a stem with leaves), strand (a rope between two anchors),
# carpet (cut into l, m, r), stamp (decor that stands), critter (a
# creature's sheet, whole). Options: lit (glows where it is pale),
# hang (stored upside down), stem (the mycelium stem fix).
TABLE = {
    'mycelium/mycelium-enviorement': [
        ['myc_shroom_0', 'shroom', 'stem'], ['myc_shroom_1', 'shroom', 'stem'], ['myc_shroom_2', 'shroom', 'stem'],
        ['myc_shroom_3', 'shroom', 'stem'], ['myc_shroom_4', 'shroom', 'stem'], ['myc_shroom_5', 'shroom', 'stem'],
        ['myc_shroom_6', 'shroom', 'stem'],
        ['myc_strand_0', 'strand', 'hang'], ['myc_strand_1', 'strand', 'hang'], ['myc_strand_2', 'strand', 'hang'],
        ['myc_strand_3', 'strand', 'hang'],
        ['myc_glim_0', 'stamp', 'lit'], ['myc_glim_1', 'stamp', 'lit'], ['myc_glim_2', 'stamp', 'lit'], ['myc_glim_3', 'stamp', 'lit'],
        ['myc_leaf_0', 'stamp', 'lit'], ['myc_leaf_1', 'stamp', 'lit'],
        ['myc_tuft_0', 'stamp', ''], ['myc_tuft_1', 'stamp', ''],
    ],
    'mycelium/mycelium-ground': [
        ['myc_grass_0', 'stamp', ''], ['myc_grass_1', 'stamp', ''], ['myc_grass_2', 'stamp', ''], ['myc_grass_3', 'stamp', ''],
    ],
    # The 16 px mushrooms: the base (the brown stalk) and its kin, the
    # thin brown caps, one group; the orange ones another; the spotted
    # one and the puffball alone.
    '16x16-shrooms/16x16-shrooms': [
        ['warm_brown_0', 'shroom', ''], ['warm_puff_0', 'stamp', ''], ['warm_orange_0', 'shroom', 'lit'],
        ['warm_orange_1', 'shroom', 'lit'], ['warm_brown_1', 'shroom', ''], ['warm_brown_2', 'shroom', ''],
        ['warm_orange_2', 'shroom', 'lit'], ['warm_spot_0', 'shroom', ''],
    ],
    'climbing-plants-pack/list': [
        ['garden_moss_0', 'carpet', 'hang'], ['garden_roots_0', 'carpet', 'hang'],
        ['garden_plant_0', 'plant', 'hang'], ['garden_plant_1', 'plant', ''], ['garden_plant_2', 'plant', ''],
        ['garden_plant_3', 'plant', ''], ['garden_plant_4', 'plant', ''],
    ],
    'worm-walk/worm-walk': [['worm', 'critter', '']],
    'jellyfish-sprite-sheet/jellyfish-sprite-sheet': [['jelly', 'critter', '']],
}
PACK_OF = {'mycelium': 'mycelium', '16x16-shrooms': 'warm', 'climbing-plants-pack': 'garden'}
EMISSION = {'mycelium/mycelium-enviorement': 'Mycelium/enviorement_emmision.png', 'mycelium/mycelium-ground': 'Mycelium/ground_emission.png'}
LIFT = {(12, 15, 34): (26, 33, 62), (8, 10, 20): (19, 24, 46), (3, 10, 20): (16, 26, 42), (3, 13, 20): (16, 28, 42), (0, 17, 29): (14, 30, 46)}
STEM_BLUE = (32, 53, 84)


def inside(pts, x, y):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[j]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            c = not c
        j = i
    return c


def crop(im, pts, glow=None):
    # The pixels whose centre lies inside the outline and that are not
    # see-through (the page's cutter takes the same), trimmed to their box.
    w, h = im.size
    px = im.load()
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    keep = [(x, y) for y in range(max(0, int(min(ys))), min(h, int(max(ys)) + 1))
            for x in range(max(0, int(min(xs))), min(w, int(max(xs)) + 1))
            if px[x, y][3] and inside(pts, x + 0.5, y + 0.5)]
    x0, y0 = min(k[0] for k in keep), min(k[1] for k in keep)
    x1, y1 = max(k[0] for k in keep), max(k[1] for k in keep)
    out = Image.new('RGBA', (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
    gout = Image.new('RGBA', out.size, (0, 0, 0, 0))
    op, gp = out.load(), gout.load()
    gl = glow.load() if glow else None
    for x, y in keep:
        op[x - x0, y - y0] = px[x, y]
        if gl and gl[x, y][3] > 0 and sum(gl[x, y][:3]) > 300:
            gp[x - x0, y - y0] = (255, 255, 255, 255)
    return out, gout


def colours(im):
    out = {}
    for y in range(im.height):
        for x in range(im.width):
            p = im.getpixel((x, y))
            if p[3] > 127:
                out[p[:3]] = out.get(p[:3], 0) + 1
    return out


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def palette(counts):
    # At most 16 of the pack's own colours: while there are more, the
    # pair cheapest to merge (Ward: the weights' product over their sum
    # times the distance squared) goes into the heavier one. Returns the
    # palette, dark to light, and each colour's stand-in.
    cols = {c: n for c, n in counts.items()}
    into = {c: c for c in cols}
    while len(cols) > 16:
        best = None
        ks = list(cols)
        for i in range(len(ks)):
            for j in range(i + 1, len(ks)):
                a, b = ks[i], ks[j]
                d = sum((a[k] - b[k]) ** 2 for k in range(3))
                cost = cols[a] * cols[b] / (cols[a] + cols[b]) * d
                if best is None or cost < best[0]:
                    best = (cost, a, b)
        _, a, b = best
        keep, gone = (a, b) if cols[a] >= cols[b] else (b, a)
        cols[keep] += cols.pop(gone)
        for c, t in into.items():
            if t == gone:
                into[c] = keep
    pal = sorted(cols, key=lum)
    while len(pal) < 16:
        pal.append(pal[-1])
    return pal, into


def recolour(im, into):
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] > 127:
                c = into.get(p[:3], p[:3])
                px[x, y] = (c[0], c[1], c[2], 255)
            else:
                px[x, y] = (0, 0, 0, 0)
    return out


def widths(im):
    w = []
    px = im.load()
    for y in range(im.height):
        xs = [x for x in range(im.width) if px[x, y][3]]
        w.append((max(xs) - min(xs) + 1) if xs else 0)
    return w


def cap_rows(im):
    # The rows from the top down to the cap's lowest, as shroom.gd plan
    # finds the cap from the foot up: the first row past the first two
    # three wider than the one under it or 3/4 of the widest.
    w = widths(im)[::-1]
    widest = max(w)
    for r in range(2, len(w)):
        if w[r] >= w[r - 1] + 3 or w[r] >= -(-widest * 3 // 4):
            return im.height - r
    return 0


def stem_fix(im):
    # The stem's dark half to the mid blue, under the cap.
    out = im.copy()
    px = out.load()
    for y in range(cap_rows(im), out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] and lum(p) < 30:
                px[x, y] = STEM_BLUE + (255,)
    return out


def lift(im):
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            p = px[x, y]
            if p[3] and p[:3] in LIFT:
                px[x, y] = LIFT[p[:3]] + (255,)
    return out


def stem_height(im, f, glow):
    # The stem's rows (under the cap) dropped or repeated evenly to f of
    # their count: a shorter or a taller one of the same shroom.
    top = cap_rows(im)
    stem = list(range(top, im.height))
    n = max(2, int(round(len(stem) * f)))
    rows = list(range(top)) + [stem[min(len(stem) - 1, int(i * len(stem) / n))] for i in range(n)]
    out = Image.new('RGBA', (im.width, len(rows)), (0, 0, 0, 0))
    gout = Image.new('RGBA', out.size, (0, 0, 0, 0))
    for y, r in enumerate(rows):
        out.paste(im.crop((0, r, im.width, r + 1)), (0, y))
        gout.paste(glow.crop((0, r, im.width, r + 1)), (0, y))
    return out, gout


def tiling_cut(im):
    # A carpet's columns cut into a left end, a middle and a right end,
    # the middle's two edges as alike as can be found, so middles laid
    # edge to edge run on without a seam.
    px = im.load()
    w, h = im.size
    def col(x):
        return [px[x, y] if px[x, y][3] else None for y in range(h)]
    def diff(a, b):
        s = 0
        for p, q in zip(a, b):
            if (p is None) != (q is None):
                s += 300
            elif p is not None:
                s += sum(abs(p[k] - q[k]) for k in range(3))
        return s
    best = None
    for a in range(w // 5, w // 2):
        for b in range(a + max(8, w // 4), w - w // 5):
            d = diff(col(a), col(b))
            if best is None or d < best[0]:
                best = (d, a, b)
    _, a, b = best
    return [(0, a), (a, b), (b, w)]


def halve(im):
    # Half the size, each 2x2 block its commonest opaque colour (opaque
    # when two or more of its four are), so the outline and the eye
    # survive the shrink better than a blend would leave them.
    w, h = (im.width + 1) // 2, (im.height + 1) // 2
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            got = {}
            for dy in (0, 1):
                for dx in (0, 1):
                    sx, sy = 2 * x + dx, 2 * y + dy
                    if sx < im.width and sy < im.height and px[sx, sy][3] > 127:
                        got[px[sx, sy]] = got.get(px[sx, sy], 0) + 1
            if sum(got.values()) >= 2:
                # The darkest colour wins a tie: the outline and the eye.
                out.putpixel((x, y), max(got, key=lambda c: (got[c], -lum(c))))
    return out


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)


def bbox(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def manifest(hunt):
    state = json.load(open(os.path.join(hunt, 'state.json'), encoding='utf-8'))
    cuts = sorted(state.get('cuts', {}).items(), key=lambda kv: kv[1].get('created', 0))
    seen = {}
    out = []
    for cid, d in cuts:
        sheet = d['sheet']
        if sheet not in TABLE:
            print('no use for', sheet)
            continue
        k = seen.get(sheet, 0)
        seen[sheet] = k + 1
        if k >= len(TABLE[sheet]):
            print('extra cut on', sheet, cid)
            continue
        name, use, opts = TABLE[sheet][k]
        out.append({'id': cid, 'sheet': sheet, 'pts': d['pts'], 'name': name, 'use': use, 'opts': opts, 'notes': d.get('notes', '')})
    json.dump({'cuts': out}, open(MANIFEST, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    print(len(out), 'cuts in', os.path.normpath(MANIFEST))


def build(hunt, zip_path):
    man = json.load(open(MANIFEST, encoding='utf-8'))['cuts']
    sheets = {s['id']: s for p in json.load(open(os.path.join(hunt, 'assets.json'), encoding='utf-8'))['packs'] for s in p['sheets']}
    zf = zipfile.ZipFile(zip_path) if zip_path else None
    ims, glows, made = {}, {}, {}
    for c in man:
        sh = c['sheet']
        if sh not in ims:
            ims[sh] = Image.open(os.path.join(hunt, sheets[sh]['file'])).convert('RGBA')
            glows[sh] = Image.open(io.BytesIO(zf.read(EMISSION[sh]))).convert('RGBA') if (zf and sh in EMISSION) else None
        im, gl = crop(ims[sh], c['pts'], glows[sh])
        if 'stem' in c['opts']:
            im = stem_fix(im)
        if sh.startswith('mycelium'):
            im = lift(im)
        if 'lit' in c['opts'] and gl.getbbox() is None:
            # Lit with no emission there: its pale half glows.
            px, gp = im.load(), gl.load()
            ls = sorted(lum(px[x, y]) for y in range(im.height) for x in range(im.width) if px[x, y][3])
            cut = ls[len(ls) // 2] if ls else 255
            for y in range(im.height):
                for x in range(im.width):
                    if px[x, y][3] and lum(px[x, y]) >= cut and lum(px[x, y]) > 90:
                        gp[x, y] = (255, 255, 255, 255)
        made[c['name']] = (c, im, gl)
    # The palettes, one a pack, from every cut of it.
    packs = {}
    for name, (c, im, gl) in made.items():
        pk = PACK_OF.get(c['sheet'].split('/')[0])
        if pk:
            packs.setdefault(pk, {})
            for col, n in colours(im).items():
                packs[pk][col] = packs[pk].get(col, 0) + n
    into = {}
    for pk, counts in packs.items():
        pal, into[pk] = palette(counts)
        img = Image.new('RGB', (16, 1))
        for i, col in enumerate(pal):
            img.putpixel((i, 0), col)
        save(img, os.path.join(DECOR, 'palettes', pk + '.png'))
        print(f'palette {pk}: {len(counts)} colours into {len(set(into[pk].values()))}')
    for pk in packs:
        d = os.path.join(DECOR, 'stamps', pk)
        if os.path.isdir(d):
            shutil.rmtree(d)
    crit = os.path.join(DECOR, 'critters')
    for name, (c, im, gl) in made.items():
        if c['use'] == 'critter':
            if c['sheet'].startswith('jellyfish'):
                # The whole sheet: its frames are a grid of 32 px cells.
                im = ims[c['sheet']]
            elif name == 'worm':
                # The first of the walk's three frames (64 px each): the
                # body's squeeze comes from the long slug's pulse.
                im = bbox(im.crop((0, 0, min(im.width, 60), im.height)))
            save(im, os.path.join(crit, name + '.png'))
            print(f'critter {name:18s} {im.size[0]} x {im.size[1]}')
            if name == 'worm':
                small = halve(im)
                save(small, os.path.join(crit, 'worm_small.png'))
                print(f'critter {"worm_small":18s} {small.size[0]} x {small.size[1]}')
            continue
        pk = PACK_OF[c['sheet'].split('/')[0]]
        im = recolour(im, into[pk])
        if 'hang' in c['opts']:
            im = im.transpose(Image.FLIP_TOP_BOTTOM)
            gl = gl.transpose(Image.FLIP_TOP_BOTTOM)
        folder = os.path.join(DECOR, 'stamps', pk)
        outs = []
        if c['use'] == 'carpet':
            for (a, b), role in zip(tiling_cut(im), 'lmr'):
                outs.append((f'{name}_{role}', im.crop((a, 0, b, im.height)), gl.crop((a, 0, b, im.height))))
            outs.append((name, im, gl))
        elif c['use'] == 'shroom':
            # Takes 0 to 9 as drawn, 10 up the short ones, 20 up the tall.
            base, take = name.rsplit('_', 1)
            for f, add in [(0.6, 10), (1.0, 0), (1.6, 20)]:
                s_im, s_gl = (im, gl) if add == 0 else stem_height(im, f, gl)
                outs.append((f'{base}_{int(take) + add}', s_im, s_gl))
        else:
            outs.append((name, im, gl))
        for n, o, g in outs:
            bb = o.getbbox()
            o, g = o.crop(bb), g.crop(bb)
            save(o, os.path.join(folder, n + '.png'))
            if g.getbbox():
                save(g, os.path.join(folder, n + '.glow.png'))
            print(f'{pk:8s} {n:18s} {o.size[0]:3d} x {o.size[1]:3d}{"  glows" if g.getbbox() else ""}')


if __name__ == '__main__':
    if len(sys.argv) >= 3 and sys.argv[1] == 'manifest':
        manifest(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == 'build':
        build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        print(__doc__ if __doc__ else open(__file__).read().split('import')[0])
