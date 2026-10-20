# Cuts the decor stamps into pieces the editor's brush can lay: every
# stamp's connected parts (a cluster's single mushrooms, a clump and
# its sporophytes) as <name>_p<n>.png, and the carpets (the moss) into
# three slices with a role each, <name>_l.png, <name>_m.png and
# <name>_r.png (the left end, a middle, the right end), each cropped to
# its pixels, so a run of moss is an l, any number of m's and an r laid
# edge to edge. The editor groups a stamp with its pieces by the name
# before the take number (tests/scene_builder.gd stamp_group) and reads
# the role off the suffix (stamp_role). Old pieces are removed first.
#
#   python3 -I tools/decor_split.py decor/stamps
import os, sys, random
from collections import deque
from PIL import Image
folder = sys.argv[1]
random.seed(3)
SLICED = ('moss',)
MIN_PART = 6

def components(im):
    w, h = im.size; px = im.load(); seen = [[False] * w for _ in range(h)]; out = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 or seen[y][x]:
                continue
            comp = []; dq = deque([(x, y)]); seen[y][x] = True
            while dq:
                cx, cy = dq.popleft(); comp.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny][3]:
                            seen[ny][nx] = True; dq.append((nx, ny))
            out.append(comp)
    return out

def crop_pixels(im, pixels):
    xs = [p[0] for p in pixels]; ys = [p[1] for p in pixels]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    out = Image.new('RGBA', (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0)); op = out.load(); ip = im.load()
    for x, y in pixels:
        op[x - x0, y - y0] = ip[x, y]
    return out

def is_piece(name):
    last = name.split('_')[-1]
    return last in ('l', 'm', 'r') or (len(last) >= 2 and last[0] in 'ps' and last[1:].isdigit())

made = []
for f in sorted(os.listdir(folder)):
    if f.endswith('.png') and is_piece(f[:-4]):
        os.remove(os.path.join(folder, f))
names = sorted(f for f in os.listdir(folder) if f.endswith('.png'))
for f in names:
    name = f[:-4]
    im = Image.open(os.path.join(folder, f)).convert('RGBA')
    comps = [c for c in components(im) if len(c) >= MIN_PART]
    if len(comps) >= 2:
        for i, c in enumerate(comps):
            out = crop_pixels(im, c); out.save(os.path.join(folder, f'{name}_p{i}.png')); made.append((f'{name}_p{i}', out.size))
    if name.startswith(SLICED):
        w, h = im.size; px = im.load()
        xs = [x for y in range(h) for x in range(w) if px[x, y][3]]
        x0, x1 = min(xs), max(xs) + 1          # The columns the carpet spans, cut in thirds
        cuts = [x0] + [int(x0 + (x1 - x0) * k / 3 + random.randint(-2, 2)) for k in (1, 2)] + [x1]
        for i, role in enumerate('lmr'):
            pixels = [(x, y) for y in range(h) for x in range(cuts[i], cuts[i + 1]) if px[x, y][3]]
            if len(pixels) >= MIN_PART:
                out = crop_pixels(im, pixels); out.save(os.path.join(folder, f'{name}_{role}.png')); made.append((f'{name}_{role}', out.size))
for n, sz in made:
    print(f'{n:22s} {sz[0]:2d} x {sz[1]:2d}')
print(len(made), 'pieces')
