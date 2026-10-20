# Decor takes from Retro Diffusion to stamps. `clean` keys the
# background out of raw takes (white or black, whichever the prompt
# asked for; the removal misses some) and makes every pixel opaque or
# clear. `palette` cuts 16 colours from a folder of cleaned takes
# (median cut) for a fresh set. `map` snaps cleaned takes to the
# palette in decor/palette.png, the one cave_map.gd DECOR_PALETTE and
# render_write.glsl DECOR_PAL hold, so a stamp's pixels are the cells
# the game draws. Then tools/decor_split.py cuts the pieces.
#
#   python3 -I tools/decor_process.py clean <raw_dir> decor/rd --key black --prefix moss
#   python3 -I tools/decor_process.py palette decor/rd decor/palette.png
#   python3 -I tools/decor_process.py map decor/rd decor/stamps
import sys, os, glob, argparse
from PIL import Image


def clean(raw, out, key, prefix):
    os.makedirs(out, exist_ok=True)
    files = sorted(glob.glob(os.path.join(raw, '*.png')) + glob.glob(os.path.join(raw, '*', '*.png')))
    for n, p in enumerate(files):
        im = Image.open(p).convert('RGBA')
        px = im.load(); w, h = im.size; keyed = 0; semi = 0
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                bg = (r >= 236 and g >= 236 and b >= 236) if key == 'white' else (r + g + b <= 18)
                if a > 0 and bg:
                    px[x, y] = (0, 0, 0, 0); keyed += 1
                elif 0 < a < 255:
                    px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0); semi += 1
        name = f'{prefix}_{n}' if prefix else os.path.splitext(os.path.basename(p))[0]
        cols = {px[x, y][:3] for y in range(h) for x in range(w) if px[x, y][3]}
        print(f'{name:16s} {w:2d}x{h:2d} colours {len(cols):3d} keyed {keyed:3d} semi {semi}')
        im.save(os.path.join(out, name + '.png'))


def load_palette(path):
    pi = Image.open(path).convert('RGB')
    return [pi.getpixel((i, 0)) for i in range(pi.size[0])]


def cut_palette(rd, out, n=16):
    allpix = []
    for p in sorted(glob.glob(os.path.join(rd, '*.png'))):
        allpix += [c[:3] for c in Image.open(p).convert('RGBA').getdata() if c[3]]
    strip = Image.new('RGB', (len(allpix), 1)); strip.putdata(allpix)
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[:n * 3]
    pal = sorted((tuple(pal[i:i + 3]) for i in range(0, n * 3, 3)), key=lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])
    pi = Image.new('RGB', (n, 1)); pi.putdata(pal); pi.save(out)
    print('palette', ' '.join('#%02x%02x%02x' % c for c in pal))


def map_stamps(rd, out, palette):
    os.makedirs(out, exist_ok=True)
    pal = load_palette(palette)

    def nearest(c):
        return min(pal, key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2)
    tot = 0.0; n = 0
    for p in sorted(glob.glob(os.path.join(rd, '*.png'))):
        name = os.path.splitext(os.path.basename(p))[0]
        o = Image.open(p).convert('RGBA'); px = o.load(); w, h = o.size; err = 0.0; k = 0
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a:
                    nr, ng, nb = nearest((r, g, b))
                    err += abs(nr - r) + abs(ng - g) + abs(nb - b); k += 1
                    px[x, y] = (nr, ng, nb, 255)
        tot += err; n += k
        print(f'mapped {name:16s} mean abs err per channel {err / max(k, 1) / 3:5.1f}')
        o.save(os.path.join(out, name + '.png'))
    print('overall mean abs err', round(tot / max(n, 1) / 3, 1))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('clean'); c.add_argument('raw'); c.add_argument('out'); c.add_argument('--key', choices=['white', 'black'], default='white'); c.add_argument('--prefix', default='')
    p = sub.add_parser('palette'); p.add_argument('rd'); p.add_argument('out')
    m = sub.add_parser('map'); m.add_argument('rd'); m.add_argument('out'); m.add_argument('--palette', default='decor/palette.png')
    a = ap.parse_args()
    if a.cmd == 'clean':
        clean(a.raw, a.out, a.key, a.prefix)
    elif a.cmd == 'palette':
        cut_palette(a.rd, a.out)
    else:
        map_stamps(a.rd, a.out, a.palette)
