# A strand: a thread of the mycelium hung between two anchors, drawn
# from its decor sprite (myc_strand, a sagging line with drips under it).
# It is no hold and no wall: not cells in the sim, so the gecko and the
# creatures pass through it, and as they do they push it, and it sways
# and settles back. A rope of points the CPU runs (verlet, its two ends
# pinned where the sprite's ends meet rock); a bite across it cuts it
# there and each part hangs from its own anchor; an anchor whose rock is
# chewed away lets go, and a strand with neither end held falls and
# lies where it lands. Each pixel of the sprite rides the rope at its
# place along it and its offset across it, drawn on the 2 px grid in its
# band's palette (critters.gd _draw).
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
	return not pixels.is_empty()


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
	var pushed := false
	for b in bodies:
		var c: Vector2 = b[0]
		var r: float = b[1] + PUSH_R
		for i in pts.size():
			if pinned[i] == 0 and pts[i].distance_squared_to(c) < r * r:
				pushed = true
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


# The pixels where the rope has them now: [cell x, cell y, colour] each
# on the 2 px grid. A pixel on a cut link's far side rides the point
# past the cut, so the parts come apart cleanly; the thread itself is
# drawn as a line along each whole link, so a stretched or turned rope
# shows no gaps.
func draw_cells(cell: float) -> Array:
	var out := {}
	if _thread_col.a == 0.0:
		_thread_col = _thread_colour(cell)
	for px in pixels:
		var t: float = px[0]
		var i := clampi(int(floor(t)), 0, pts.size() - 2)
		var f := t - i
		if cut[i] == 1:
			i = i + 1 if f >= 0.5 else i
			f = 0.0
			i = mini(i, pts.size() - 2)
		var a := pts[i]
		var b := pts[i + 1]
		var along := (b - a).normalized() if a.distance_squared_to(b) > 0.0001 else Vector2.RIGHT
		var n := Vector2(-along.y, along.x)
		var at := a.lerp(b, f) + along * float(px[1]) + n * float(px[2])
		var col := DecorPalettes.colour_at(int(px[3]), int(px[4]), int(px[5]), cell)
		out[Vector2i(int(floor(at.x / cell)), int(floor(at.y / cell)))] = col
		if absf(px[2]) < cell * 0.75 and cut[i] == 0:
			# On the thread: the cells between this one and the next point.
			var steps := int(ceil(a.distance_to(b) / cell))
			for s in steps:
				var q := a.lerp(b, float(s) / steps) + n * float(px[2])
				var k := Vector2i(int(floor(q.x / cell)), int(floor(q.y / cell)))
				if not out.has(k):
					out[k] = col
	# The links with no pixel of their own (an end's reach up to its rock)
	# in the thread's colour.
	for i in pts.size() - 1:
		if cut[i] == 1:
			continue
		var steps := int(ceil(pts[i].distance_to(pts[i + 1]) / cell))
		for s in steps + 1:
			var q := pts[i].lerp(pts[i + 1], float(s) / maxi(steps, 1))
			var k := Vector2i(int(floor(q.x / cell)), int(floor(q.y / cell)))
			if not out.has(k):
				out[k] = _thread_col
	var arr: Array = []
	for k in out:
		arr.append([k.x, k.y, out[k]])
	return arr
