# A strand: a thread of the mycelium hung between two anchors, drawn
# from its decor sprite (myc_strand, a sagging line with drips under it).
# It is no hold and no wall: not cells in the sim, so the gecko and the
# creatures pass through it, and as they do they push it, and it sways
# and settles back. A rope of points the CPU runs (verlet, its two ends
# pinned where the sprite's ends meet rock); a bite across it cuts it
# there and each part hangs from its own anchor; an anchor whose rock is
# chewed away lets go, and a strand with neither end held falls and
# lies where it lands. The sprite rides the rope: baked once in its
# band's colours, drawn as a textured quad a link whose corners sit at
# the same places on the rope as at rest (draw_on, critter_layer.gd).
extends RefCounted

const DecorPalettes = preload("res://decor_palettes.gd")

const LINK := 4.0              # px between rope points
const GRAVITY := 300.0         # px/s^2: a light thread, it sags a little past its drawn line
const DAMP := 0.96             # Of the speed kept a tick: a brushed thread swings once or twice and stills
const ITERS := 6               # Constraint passes a tick
const PUSH_R := 7.0            # A body's reach round its centre that shoves the thread
const ANCHOR_REACH := 4.0      # Rock this near an end holds it
const REACH_UP := 120.0        # An end off the rock reaches this far up for it
const CHECK_T := 0.25          # s between the anchors' rock checks
const SLEEP_V := 0.02          # px a tick below which the rope is still
const SLEEP_T := 30            # Still ticks before it sleeps

var map: Node2D
var pts := PackedVector2Array()
var prev := PackedVector2Array()
var rest := PackedFloat32Array()    # Each link's length
var cut := PackedByteArray()        # 1 where link i (point i to i + 1) is broken
var pinned := PackedByteArray()     # 1 where a point is held: the two ends at first
var pin_at := PackedVector2Array()
var pixels: Array = []              # [t along the rope (px), offset across (px), colour index, cell x, cell y] each
var asleep := false
var _thread_col := Color(0, 0, 0, 0)   # The thread's commonest colour, for the links with no pixel
const PAD := 3                 # Empty cells round the baked texture: the quads reach a cell past the art
var _tex: ImageTexture         # The sprite at rest (draw_on)
var _origin := Vector2i.ZERO   # The texture's top left, in cells
var _rest := PackedVector2Array()
var _rest_n := PackedVector2Array()
var _n_lo := 0.0               # px across the rope the art reaches, each side (the drips one way)
var _n_hi := 0.0
var _bare := PackedByteArray() # 1 where a link has no art
var moved := true                   # Drawn again this frame
var _still := 0
var _check := 0.0


# The plan from a placed stamp's cells, [x, y, kind] each on the grid of
# cell px: the rope is the top cell of each column, left to right (the
# drips hang under it), resampled every LINK px; each pixel goes to the
# nearest place along it. {} for fewer than two columns.
static func plan(cells: Array, cell: float) -> Dictionary:
	var top := {}
	for c in cells:
		var x: int = c[0]
		top[x] = mini(top.get(x, 1 << 30), int(c[1]))
	var xs: Array = top.keys()
	xs.sort()
	if xs.size() < 2:
		return {}
	var line := PackedVector2Array()
	for x in xs:
		line.append((Vector2(x, top[x]) + Vector2(0.5, 0.5)) * cell)
	return {"strand": true, "cells": cells, "line": line, "cell": cell}


func setup(map_in: Node2D, pl: Dictionary) -> bool:
	map = map_in
	var line: PackedVector2Array = (pl.line as PackedVector2Array).duplicate()
	# Each end is an anchor: one not on rock reaches straight up to the
	# rock over it (a thread drawn a little short of its ceiling), within
	# REACH_UP.
	for e in [line.size() - 1, 0]:   # The far end first: an insert at the front would move it
		if _rock_near(line[e]):
			continue
		var d := 2.0
		while d <= REACH_UP:
			if map.rock_world(line[e] + Vector2(0.0, -d)):
				var top := line[e] + Vector2(0.0, -d + ANCHOR_REACH * 0.5)
				if e == 0:
					line.insert(0, top)
				else:
					line.append(top)
				break
			d += 2.0
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var n := maxi(int(round(total / LINK)), 2) + 1
	var arc := PackedFloat32Array()
	for i in n:
		pts.append(_along(line, total * i / (n - 1)))
		arc.append(total * i / (n - 1))
	prev = pts.duplicate()
	rest.resize(n - 1)
	for i in n - 1:
		rest[i] = pts[i].distance_to(pts[i + 1])
	cut.resize(n - 1)
	cut.fill(0)
	pinned.resize(n)
	pinned.fill(0)
	pin_at = pts.duplicate()
	for i in [0, n - 1]:
		if _rock_near(pts[i]):
			pinned[i] = 1
	var cell: float = pl.cell
	for c in pl.cells:
		var p := (Vector2(c[0], c[1]) + Vector2(0.5, 0.5)) * cell
		var best := INF
		var rec: Array = []
		for i in n - 1:
			var ab := pts[i + 1] - pts[i]
			var l2 := ab.length_squared()
			var t := clampf((p - pts[i]).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d := p.distance_squared_to(pts[i] + ab * t)
			if d < best:
				best = d
				var along := ab.normalized() if l2 > 0.0 else Vector2.RIGHT
				var off := p - (pts[i] + ab * t)
				rec = [i + t, off.dot(along), Vector2(-along.y, along.x).dot(off), int(c[2]) - 16, int(c[0]), int(c[1])]
		pixels.append(rec)
	_bake_texture(cell)
	return not pixels.is_empty()


# The sprite as a texture for draw_on: its pixels in their band's colours
# where they lie at rest, with a border of PAD empty cells; each point's
# rest place and normal (the texture's frame), how far across the rope
# the art reaches, and which links have no pixel (an end's reach up to
# its rock, drawn as a line of the thread's colour).
func _bake_texture(cell: float) -> void:
	if pixels.is_empty():
		return
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for px in pixels:
		lo = Vector2i(mini(lo.x, px[4]), mini(lo.y, px[5]))
		hi = Vector2i(maxi(hi.x, px[4]), maxi(hi.y, px[5]))
	_origin = lo - Vector2i(PAD, PAD)
	var img := Image.create(hi.x - lo.x + 1 + 2 * PAD, hi.y - lo.y + 1 + 2 * PAD, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_n_lo = 0.0
	_n_hi = 0.0
	var has := PackedByteArray()
	has.resize(pts.size())
	for px in pixels:
		img.set_pixel(int(px[4]) - _origin.x, int(px[5]) - _origin.y, DecorPalettes.colour_at(int(px[3]), int(px[4]), int(px[5]), cell))
		_n_lo = minf(_n_lo, float(px[2]))
		_n_hi = maxf(_n_hi, float(px[2]))
		has[clampi(int(floor(px[0])), 0, pts.size() - 2)] = 1
	_n_lo -= cell
	_n_hi += cell
	_tex = ImageTexture.create_from_image(img)
	_rest = pts.duplicate()
	_rest_n = _normals(_rest)
	_bare = PackedByteArray()
	_bare.resize(pts.size())
	for i in pts.size() - 1:
		_bare[i] = 0 if has[i] == 1 else 1
	_thread_col = _thread_colour(cell)


static func _normals(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	out.resize(n)
	for i in n:
		var t := p[mini(i + 1, n - 1)] - p[maxi(i - 1, 0)]
		t = t.normalized() if t.length_squared() > 0.0001 else Vector2.RIGHT
		out[i] = Vector2(-t.y, t.x)
	return out


# The strand on the GPU (critter_layer.gd): a quad a whole link, from
# _n_lo to _n_hi across the rope at each end, its texture coordinates
# the same places on the rope at rest, so the art bends with the rope;
# a link with no art (an end's reach) a line of the thread's colour.
func draw_on(c: CanvasItem, cell: float) -> void:
	if _tex == null:
		return
	var nrm := _normals(pts)
	var size := Vector2(_tex.get_size()) * cell
	var o := Vector2(_origin) * cell
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for i in pts.size() - 1:
		if cut[i] == 1:
			continue
		if _bare[i] == 1:
			c.draw_line(pts[i], pts[i + 1], _thread_col, cell)
			continue
		var q := PackedVector2Array([pts[i] + nrm[i] * _n_lo, pts[i + 1] + nrm[i + 1] * _n_lo, pts[i + 1] + nrm[i + 1] * _n_hi, pts[i] + nrm[i] * _n_hi])
		var r := [_rest[i] + _rest_n[i] * _n_lo, _rest[i + 1] + _rest_n[i + 1] * _n_lo, _rest[i + 1] + _rest_n[i + 1] * _n_hi, _rest[i] + _rest_n[i] * _n_hi]
		var uv := PackedVector2Array()
		for p in r:
			uv.append(((p as Vector2) - o) / size)
		c.draw_primitive(q, white, uv, _tex)


func _rock_near(p: Vector2) -> bool:
	for d in [Vector2(0, -ANCHOR_REACH), Vector2(-ANCHOR_REACH, 0), Vector2(ANCHOR_REACH, 0), Vector2(0, ANCHOR_REACH), Vector2.ZERO]:
		if map.rock_world(p + d):
			return true
	return false


# One tick: bodies is [[centre, radius], ...] that push it.
func step(dt: float, bodies: Array) -> void:
	_check -= dt
	if _check <= 0.0:
		_check = CHECK_T
		for i in pts.size():
			if pinned[i] == 1 and not _rock_near(pin_at[i]):
				pinned[i] = 0
				asleep = false
	# Only the bodies within the rope's box can touch it.
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	var near: Array = []
	for b in bodies:
		if box.grow(float(b[1]) + PUSH_R).has_point(b[0]):
			near.append(b)
	bodies = near
	var pushed := false
	for b in bodies:
		var c: Vector2 = b[0]
		var r: float = b[1] + PUSH_R
		for i in pts.size():
			if pinned[i] == 0 and pts[i].distance_squared_to(c) < r * r:
				pushed = true
				break
	if asleep and not pushed:
		moved = false
		return
	asleep = false
	var g := Vector2(0.0, GRAVITY) * dt * dt
	for i in pts.size():
		if pinned[i] == 1:
			pts[i] = pin_at[i]
			prev[i] = pin_at[i]
			continue
		var v := (pts[i] - prev[i]) * DAMP
		prev[i] = pts[i]
		var nxt := pts[i] + v + g
		if map.rock_world(nxt):
			nxt = pts[i]
			prev[i] = pts[i]
		pts[i] = nxt
	for b in bodies:
		var c: Vector2 = b[0]
		var r: float = b[1] + PUSH_R
		for i in pts.size():
			if pinned[i] == 1:
				continue
			var d := pts[i] - c
			if d.length_squared() < r * r and d.length_squared() > 0.0001:
				pts[i] = c + d.normalized() * r
	for _k in ITERS:
		for i in pts.size() - 1:
			if cut[i] == 1:
				continue
			var a := pts[i]
			var b := pts[i + 1]
			var d := b - a
			var l := d.length()
			if l < 0.0001:
				continue
			var diff := (l - rest[i]) / l
			var wa := 0.0 if pinned[i] == 1 else 1.0
			var wb := 0.0 if pinned[i + 1] == 1 else 1.0
			if wa + wb == 0.0:
				continue
			pts[i] = a + d * diff * wa / (wa + wb)
			pts[i + 1] = b - d * diff * wb / (wa + wb)
	var most := 0.0
	for i in pts.size():
		most = maxf(most, pts[i].distance_squared_to(prev[i]))
	moved = most > SLEEP_V * SLEEP_V or pushed
	_still = 0 if moved else _still + 1
	if _still > SLEEP_T:
		asleep = true


func _thread_colour(cell: float) -> Color:
	var count := {}
	for px in pixels:
		if absf(px[2]) < cell * 0.75:
			var c := DecorPalettes.colour_at(int(px[3]), int(px[4]), int(px[5]), cell)
			count[c] = count.get(c, 0) + 1
	var best := Color(0.5, 0.8, 0.9)
	var n := 0
	for c in count:
		if count[c] > n:
			n = count[c]
			best = c
	return best


# A bite of radius r at p: the links it crosses are cut. True when it cut.
func bite(p: Vector2, r: float) -> bool:
	var hit := false
	for i in pts.size() - 1:
		if cut[i] == 0 and _seg_dist(p, pts[i], pts[i + 1]) <= r:
			cut[i] = 1
			hit = true
	if hit:
		asleep = false
	return hit


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
	return p.distance_to(a + ab * t)


static func _along(line: PackedVector2Array, dist: float) -> Vector2:
	for i in line.size() - 1:
		var l := line[i].distance_to(line[i + 1])
		if dist <= l and l > 0.0:
			return line[i].lerp(line[i + 1], dist / l)
		dist -= l
	return line[line.size() - 1]
