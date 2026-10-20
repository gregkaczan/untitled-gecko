import sys, os, glob
from PIL import Image
raw, out = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(out, 'raw'), exist_ok=True)
os.makedirs(os.path.join(out, 'stamps'), exist_ok=True)
imgs = {}
for p in sorted(glob.glob(os.path.join(raw, '*', '*.png'))):
    im = Image.open(p).convert('RGBA')
    name = os.path.splitext(os.path.basename(p))[0]
    px = im.load(); w, h = im.size; fixed = 0; semi = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and r >= 236 and g >= 236 and b >= 236:
                px[x, y] = (0, 0, 0, 0); fixed += 1
            elif 0 < a < 255:
                px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0); semi += 1
    cols = {px[x, y][:3] for y in range(h) for x in range(w) if px[x, y][3]}
    print(f"{name:16s} {w:2d}x{h:2d} colours {len(cols):3d} white_fixed {fixed:2d} semi {semi}")
    imgs[name] = im
    im.save(os.path.join(out, 'raw', name + '.png'))
allpix = [c[:3] for im in imgs.values() for c in im.getdata() if c[3]]
print('union colours', len(set(allpix)), 'pixels', len(allpix))
strip = Image.new('RGB', (len(allpix), 1)); strip.putdata(allpix)
q = strip.quantize(colors=16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal = q.getpalette()[:48]
pal = [tuple(pal[i:i + 3]) for i in range(0, 48, 3)]
pal.sort(key=lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])
def nearest(c):
    return min(pal, key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2)
tot = 0.0; n = 0
for name, im in imgs.items():
    o = im.copy(); px = o.load(); w, h = o.size; err = 0.0; k = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a:
                nr, ng, nb = nearest((r, g, b))
                err += abs(nr - r) + abs(ng - g) + abs(nb - b); k += 1
                px[x, y] = (nr, ng, nb, 255)
    tot += err; n += k
    print(f"mapped {name:16s} mean abs err per channel {err / max(k, 1) / 3:5.1f}")
    o.save(os.path.join(out, 'stamps', name + '.png'))
print('overall mean abs err', round(tot / n / 3, 1))
pi = Image.new('RGB', (16, 1)); pi.putdata(pal); pi.save(os.path.join(out, 'palette.png'))
print('palette', ' '.join('#%02x%02x%02x' % c for c in pal))
