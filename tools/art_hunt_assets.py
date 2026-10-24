# Copies the downloaded art packs (kept as downloaded in art/packs) into docs/art_hunt/assets so the page's
# Downloaded tab can show them and you can lasso the sprites you want.
# Each source is a folder, a .zip (zips inside zips too), a loose .png or
# an animated .gif. Per pack it writes the sheets as PNGs; a folder of many
# same-sized files becomes one atlas and an animated gif one grid of its
# frames, both remembering where each part came from. Sheets drawn on a
# flat or checkered backdrop get that backdrop keyed out (only the part
# joined to the edge, so the same colour inside a sprite stays). Emission
# maps, PSDs and .aseprite files are left out. A .rar needs unrar, 7z or
# bsdtar on the PATH; without one, extract it to a folder of the same name
# next to it (the folder wins when both are there).
# Writes docs/art_hunt/assets.json, the list the page reads.
#
#   python3 -I tools/art_hunt_assets.py [sources...]   (default: art/packs)
import io, json, os, re, shutil, subprocess, sys, tempfile, zipfile
from collections import Counter, deque
from PIL import Image, ImageChops, ImageSequence

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SITE = os.path.join(REPO, 'docs', 'art_hunt')
PACKS = os.path.join(REPO, 'art', 'packs')
OUT = os.path.join(SITE, 'assets')
# Light maps, layered sources, and the Steam page's own images saved in the same folder
SKIP = re.compile(r'emiss|emmis|/_?psd/|/(library|hero|shortcut_icon|app_icon)_', re.I)
SCENERY = re.compile(r'background|sky|parallax', re.I)  # whole pictures: no backdrop to key
ATLAS_MIN = 6   # this many same-sized files in one folder make an atlas
GAP = 4


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-') or 'x'


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s.lower())]


def key_backdrop(im):
    # An opaque sheet: the colours that make up most of its border are the
    # backdrop; clear the region of them joined to the edge.
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()
    border = [px[x, y] for x in range(w) for y in (0, h - 1)] + [px[x, y] for y in range(h) for x in (0, w - 1)]
    if any(c[3] < 255 for c in border):
        return im, False
    count = Counter(border)
    bg = {c for c, n in count.items() if n >= len(border) * 0.2}
    if sum(count[c] for c in bg) < len(border) * 0.9:
        return im, False
    seen = bytearray(w * h)
    dq = deque((x, y) for x, y in ((x, 0) for x in range(w)) if px[x, y] in bg)
    dq.extend((x, h - 1) for x in range(w) if px[x, h - 1] in bg)
    dq.extend((0, y) for y in range(h) if px[0, y] in bg)
    dq.extend((w - 1, y) for y in range(h) if px[w - 1, y] in bg)
    for x, y in dq:
        seen[y * w + x] = 1
    while dq:
        x, y = dq.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] in bg:
                seen[ny * w + nx] = 1
                dq.append((nx, ny))
    return im, True


def gif_grid(im):
    # The frames that differ, cropped to the box where anything moves (a
    # store preview's logo and caption stay still), laid out in a grid.
    frames, seen = [], set()
    for f in ImageSequence.Iterator(im):
        fr = f.convert('RGBA')
        k = fr.tobytes()
        if k not in seen:
            seen.add(k)
            frames.append(fr)
    box = None
    for fr in frames[1:]:
        b = ImageChops.difference(fr, frames[0]).getbbox(alpha_only=False)
        if b:
            box = b if not box else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    box = box or (0, 0) + frames[0].size
    cells = [key_backdrop(fr.crop(box))[0] for fr in frames]
    cw, ch = cells[0].size
    cols = max(1, min(len(cells), 1600 // (cw + GAP)))
    rows = (len(cells) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * (cw + GAP) - GAP, rows * (ch + GAP) - GAP), (0, 0, 0, 0))
    parts = []
    for i, c in enumerate(cells):
        x, y = (i % cols) * (cw + GAP), (i // cols) * (ch + GAP)
        sheet.paste(c, (x, y))
        parts.append({'name': f'frame {i}', 'x': x, 'y': y, 'w': cw, 'h': ch})
    return sheet, parts


def atlas(files):
    ims = [(n, Image.open(io.BytesIO(b)).convert('RGBA')) for n, b in files]
    cw, ch = ims[0][1].size
    cols = max(1, min(len(ims), 1200 // (cw + GAP)))
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * (cw + GAP) - GAP, rows * (ch + GAP) - GAP), (0, 0, 0, 0))
    parts = []
    for i, (n, im) in enumerate(ims):
        x, y = (i % cols) * (cw + GAP), (i // cols) * (ch + GAP)
        sheet.paste(im, (x, y))
        parts.append({'name': os.path.basename(n), 'x': x, 'y': y, 'w': cw, 'h': ch})
    return sheet, parts


def walk_zip(data, prefix=''):
    # Yields (path, bytes) of every file, opening zips inside the zip.
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            b = z.read(info)
            if info.filename.lower().endswith('.zip'):
                yield from walk_zip(b, prefix + info.filename[:-4] + '/')
            else:
                yield prefix + info.filename, b


def walk_dir(root):
    for r, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(r, f)
            with open(p, 'rb') as fh:
                yield os.path.relpath(p, root), fh.read()


def unrar(path):
    tmp = tempfile.mkdtemp()
    for cmd in (['unrar', 'x', '-o+', '-inul', path, tmp + '/'], ['7z', 'x', '-y', '-o' + tmp, path], ['bsdtar', '-xf', path, '-C', tmp]):
        if shutil.which(cmd[0]) and subprocess.run(cmd, capture_output=True).returncode == 0:
            return tmp
    shutil.rmtree(tmp)
    return None


def sources(args):
    # (pack name, [(path inside pack, bytes)])
    for a in args:
        a = os.path.expanduser(a)
        if os.path.isdir(a) and any(f.lower().endswith(('.zip', '.rar', '.png', '.gif')) for f in os.listdir(a)) and not all(
                f.lower().endswith(('.png', '.gif')) for f in os.listdir(a) if os.path.isfile(os.path.join(a, f))):
            # A downloads folder: each archive or loose image is its own pack
            for f in sorted(os.listdir(a)):
                yield from sources([os.path.join(a, f)])
        elif os.path.isdir(a):
            yield os.path.basename(a.rstrip('/')), list(walk_dir(a))
        elif a.lower().endswith('.zip'):
            with open(a, 'rb') as fh:
                yield os.path.basename(a)[:-4], list(walk_zip(fh.read()))
        elif a.lower().endswith('.rar') and os.path.isdir(a[:-4]):
            continue
        elif a.lower().endswith('.rar'):
            tmp = unrar(a)
            if not tmp:
                print(f'skipped {a}: no unrar, 7z or bsdtar; extract it to a folder and pass that')
                continue
            yield os.path.basename(a)[:-4], list(walk_dir(tmp))
            shutil.rmtree(tmp)
        elif a.lower().endswith(('.png', '.gif')):
            with open(a, 'rb') as fh:
                yield os.path.splitext(os.path.basename(a))[0], [(os.path.basename(a), fh.read())]


def licence(files):
    for n, b in files:
        if re.search(r'licen[cs]e|readme', n, re.I) and n.lower().endswith('.txt'):
            return b.decode('utf-8', 'replace').strip()[:1200]
    return ''


def main(args):
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    packs, taken = [], set()
    for name, files in sources(args):
        pslug = slug(name)
        while pslug in taken:
            pslug += '-2'
        imgs = sorted(((n, b) for n, b in files if n.lower().endswith(('.png', '.gif')) and not SKIP.search('/' + n)), key=lambda t: natural(t[0]))
        if not imgs:
            continue
        taken.add(pslug)
        os.makedirs(os.path.join(OUT, pslug))
        sheets, used = [], set()
        # Folders with many files of one size become one atlas
        by_dir = {}
        for n, b in imgs:
            if n.lower().endswith('.png'):
                by_dir.setdefault((os.path.dirname(n), Image.open(io.BytesIO(b)).size), []).append((n, b))
        groups = {k: v for k, v in by_dir.items() if len(v) >= ATLAS_MIN}
        for (d, size), group in groups.items():
            sheet, parts = atlas(group)
            sheets.append((f'{os.path.basename(d) or name} ({len(group)} files)', sheet, parts, False))
            used.update(n for n, _ in group)
        for n, b in imgs:
            if n in used:
                continue
            im = Image.open(io.BytesIO(b))
            if getattr(im, 'n_frames', 1) > 1:
                sheet, parts = gif_grid(im)
                sheets.append((os.path.basename(n) + f' ({len(parts)} frames)', sheet, parts, True))
            else:
                sheet, keyed = (im.convert('RGBA'), False) if SCENERY.search(n) else key_backdrop(im)
                sheets.append((n, sheet, None, keyed))
        out = []
        for title, sheet, parts, keyed in sheets:
            f = slug(os.path.splitext(title)[0])[:60]
            while any(s['file'].endswith('/' + f + '.png') for s in out):
                f += '-2'
            rel = f'assets/{pslug}/{f}.png'
            sheet.save(os.path.join(SITE, rel))
            s = {'id': f'{pslug}/{f}', 'title': title, 'file': rel, 'w': sheet.width, 'h': sheet.height}
            if parts:
                s['parts'] = parts
            if keyed:
                s['keyed'] = True
            out.append(s)
        packs.append({'slug': pslug, 'name': name, 'licence': licence(files), 'sheets': out})
        print(f'{name}: {len(out)} sheet(s)')
    with open(os.path.join(SITE, 'assets.json'), 'w', encoding='utf-8') as f:
        json.dump({'packs': packs}, f, indent=1, ensure_ascii=False)


if __name__ == '__main__':
    main(sys.argv[1:] or [PACKS])
