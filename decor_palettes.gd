# The decor's palettes and the bands of the climb that pick one. A decor
# cell's kind holds a colour index (0 to 15) and a glow bit, never a
# colour: the band the cell lies in says which palette the index is
# read in, so each band of the cave keeps a pack's own colours and the
# same stamp laid in another band takes that band's colours, index for
# index (the new palettes run from dark to light, so it stays readable).
#
# A palette is a 16x1 PNG in decor/palettes/<name>.png; "sage" is the
# first decor palette, decor/palette.png. A stamp's home palette is the
# folder it sits in under decor/stamps (none: sage), and its pixels are
# matched to that palette's colours (tests/scene_builder.gd png_stamps).
#
# A level's bands: "bands": [[y, palette], ...] in its scene, each from
# its y (world px) down to the next one's; above the first, the first.
# Across BLEND px under a band's top the two palettes are dithered, a
# cell to a cell (render_write.glsl does the same on the GPU; sim.gd
# set_bands uploads them).
extends RefCounted

const PALETTES_DIR := "res://decor/palettes"
const SAGE := "res://decor/palette.png"
const MAX_BANDS := 8
const MAX_PALETTES := 8
const BLEND := 32.0
const DEFAULT := [[0.0, "sage"]]

static var _palettes := {}
static var _names: Array = []
static var _loaded := false
static var bands: Array = DEFAULT.duplicate(true)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_palettes["sage"] = _read(SAGE)
	_names.append("sage")
	var dir := DirAccess.open(PALETTES_DIR)
	if dir == null:
		return
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".png"):
			files.append(f.trim_suffix(".png"))
	files.sort()
	for n in files:
		if n == "sage":
			continue
		var cols := _read(PALETTES_DIR + "/" + n + ".png")
		if not cols.is_empty():
			_palettes[n] = cols
			_names.append(n)


# A palette file's 16 colours, read from the bytes (no import needed).
static func _read(path: String) -> Array[Color]:
	var out: Array[Color] = []
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return out
	img.convert(Image.FORMAT_RGBA8)
	for i in 16:
		out.append(img.get_pixel(mini(i, img.get_width() - 1), 0))
	return out


static func names() -> Array:
	_load()
	return _names


static func colours(name: String) -> Array[Color]:
	_load()
	var c: Array[Color] = _palettes.get(name, _palettes["sage"])
	return c


# The bands as a level gives them, sorted, at most MAX_BANDS, unknown
# palettes as sage; none or an empty list: one sage band.
static func set_bands(list: Array) -> void:
	_load()
	var out: Array = []
	for b in list:
		if b is Array and b.size() >= 2:
			out.append([float(b[0]), String(b[1]) if _palettes.has(String(b[1])) else "sage"])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if out.is_empty():
		out = DEFAULT.duplicate(true)
	bands = out.slice(0, MAX_BANDS)


# The bands for a level file: [[y, name], ...].
static func bands_json() -> Array:
	var out: Array = []
	for b in bands:
		out.append([int(round(b[0])), b[1]])
	return out


static func band_index(y: float) -> int:
	var k := 0
	for i in bands.size():
		if y >= bands[i][0]:
			k = i
	return k


# The palette a cell at cell (cx, cy) of size cell px reads its index in:
# its band's, or within BLEND under the band's top, the band above's
# for a share of the cells that shrinks with the depth (a hash of the
# cell, as render_write.glsl decor_pal).
static func palette_at(cx: int, cy: int, cell: float) -> String:
	var y := (cy + 0.5) * cell
	var k := band_index(y)
	if k > 0:
		var t: float = (y - bands[k][0]) / BLEND
		if t < 1.0 and _hash(cx, cy) > t:
			k -= 1
	return bands[k][1]


static func colour_at(index: int, cx: int, cy: int, cell: float) -> Color:
	return colours(palette_at(cx, cy, cell))[index & 15]


# The same hash as render_write.glsl band_hash.
static func _hash(cx: int, cy: int) -> float:
	var h := ((cx * 73856093) & 0xffffffff) ^ ((cy * 19349663) & 0xffffffff)
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65536.0


# The bands for the GPU (sim.gd O_PL): [count, 8 tops, 8 palette slots,
# 8 palettes of 16 packed RGBA8], the palettes the bands use, in order.
static func gpu_block() -> PackedByteArray:
	_load()
	var b := PackedByteArray()
	b.resize((17 + MAX_PALETTES * 16) * 4)
	var used: Array = []
	for band in bands:
		if not used.has(band[1]) and used.size() < MAX_PALETTES:
			used.append(band[1])
	b.encode_u32(0, bands.size())
	for i in bands.size():
		b.encode_float((1 + i) * 4, bands[i][0])
		b.encode_u32((9 + i) * 4, maxi(used.find(bands[i][1]), 0))
	for p in used.size():
		var cols := colours(used[p])
		for i in 16:
			var c: Color = cols[i]
			b.encode_u32((17 + p * 16 + i) * 4, c.r8 | (c.g8 << 8) | (c.b8 << 16) | (255 << 24))
	return b
