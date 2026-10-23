# Decor that falls when what holds it is gone. A decor cell is static in
# the sim (material 12, it never moves), so moss whose rock was chewed
# away used to hang in the air. Here each piece of decor (the decor
# cells that touch, corners too, as the level was built) knows the rock
# cells round it that hold it. When a melt (a bite, the brush, crumbling
# rock: sim.gd melts) comes near a piece, the piece is read again from
# the sim's cells two ticks later, once the melt has landed: what of it
# is still joined through decor to living rock stays, and what is not
# comes loose as lumps, the cells in each square of PIECE cells a lump
# of its own, in their colours (the band's palette at their place, as
# drawn), falling, to be shoved, dragged and swallowed like any lump.
#
# The particles are made loose where they stand: a decor cell's particle
# sits at its own cell's index (sim.gd _write_rows), so each still
# there (read back: material 12 at its cell's centre) is rewritten as a
# bonded stone particle in the decor's skin bands, a chunk of its own,
# woken by a nudge down.
extends RefCounted

const CaveMap = preload("res://cave_map.gd")

const PIECE := 16              # Cells: a fallen piece of decor breaks into lumps of at most this square
const DELAY := 2               # Ticks after a melt before the piece is read: the melt lands on the next tick and is read back after it
const HOLDS := [CaveMap.CELL_ROCK, CaveMap.CELL_COPPER, CaveMap.CELL_HARD, CaveMap.CELL_BEDROCK, CaveMap.CELL_SHROOM,
		CaveMap.CELL_MOSS, CaveMap.CELL_CRUMBLE, CaveMap.CELL_THORN]

var sim: Node2D
var w := 0
var h := 0
var comp := PackedInt32Array()      # Per cell its piece, -1 for none
var pieces: Array = []              # Per piece {cells: PackedInt32Array, holds: PackedInt32Array, box: Rect2i, gone: bool}
var _due := {}                      # Piece -> ticks before it is read
var released := 0                   # Cells let fall since the build (tests read it)


# The pieces of the decor in the cells the sim was built from.
func build(sim_in: Node2D, kinds: PackedByteArray, width: int, height: int) -> void:
	sim = sim_in
	w = width
	h = height
	comp.resize(w * h)
	comp.fill(-1)
	pieces.clear()
	_due.clear()
	released = 0
	var holds := {}
	for k in HOLDS:
		holds[k] = true
	var n := kinds.size()
	var i := 0
	while i < n:
		if kinds[i] < CaveMap.CELL_DECOR or comp[i] >= 0:
			i += 1
			continue
		var id := pieces.size()
		var cells := PackedInt32Array()
		var hold := {}
		var q := PackedInt32Array([i])
		comp[i] = id
		var x0 := w
		var y0 := h
		var x1 := 0
		var y1 := 0
		while not q.is_empty():
			var c := q[q.size() - 1]
			q.resize(q.size() - 1)
			cells.append(c)
			var cx := c % w
			var cy := c / w
			x0 = mini(x0, cx)
			y0 = mini(y0, cy)
			x1 = maxi(x1, cx)
			y1 = maxi(y1, cy)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = cx + dx
					var ny: int = cy + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var m := ny * w + nx
					var k := kinds[m]
					if k >= CaveMap.CELL_DECOR:
						if comp[m] < 0:
							comp[m] = id
							q.append(m)
					elif holds.has(k):
						hold[m] = true
		pieces.append({"cells": cells, "holds": PackedInt32Array(hold.keys()), "box": Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), "gone": false})
		i += 1


# A melt of radius r (px) at p: the pieces near it are read DELAY ticks on.
func melted(p: Vector2, r: float) -> void:
	if pieces.is_empty():
		return
	var cell: float = sim.PIXEL_SZ
	var box := Rect2i(int(floor((p.x - r) / cell)) - 2, int(floor((p.y - r) / cell)) - 2, int(ceil(2.0 * r / cell)) + 5, int(ceil(2.0 * r / cell)) + 5)
	for id in pieces.size():
		var pc: Dictionary = pieces[id]
		if not pc.gone and (pc.box as Rect2i).intersects(box):
			_due[id] = DELAY


# After the sim's tick: the pieces due read, what came loose let fall.
func tick() -> void:
	if _due.is_empty():
		return
	var now: Array = []
	for id in _due.keys():
		_due[id] -= 1
		if _due[id] <= 0:
			now.append(id)
	for id in now:
		_due.erase(id)
		_check(id)


func _cls(i: int) -> int:
	return sim.cells.decode_u32(i * 4) & 255 if sim.cells.size() >= (i + 1) * 4 else 0


# The cells of piece id that stand: joined through living decor to
# living rock. The rest fall.
func _check(id: int) -> void:
	var pc: Dictionary = pieces[id]
	var alive := {}
	for c in pc.cells:
		var k := _cls(c)
		if k == 2:
			alive[c] = true
	if alive.is_empty():
		pc.gone = true
		return
	var held := {}
	var q := PackedInt32Array()
	for hc in pc.holds:
		var k := _cls(hc)
		if not (k == 2 or k == 5 or k == 6 or k == 7):
			continue
		var hx: int = hc % w
		var hy: int = hc / w
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var m: int = (hy + dy) * w + hx + dx
				if alive.has(m) and not held.has(m):
					held[m] = true
					q.append(m)
	while not q.is_empty():
		var c := q[q.size() - 1]
		q.resize(q.size() - 1)
		var cx := c % w
		var cy := c / w
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var m: int = (cy + dy) * w + cx + dx
				if alive.has(m) and not held.has(m):
					held[m] = true
					q.append(m)
	var loose: Array = []
	for c in alive:
		if not held.has(c):
			loose.append(c)
	if loose.is_empty():
		return
	_release(loose)
	if held.is_empty():
		pc.gone = true


# The cells' particles made lumps where they stand, a lump a square of
# PIECE cells (by the cell's square, so neighbours in one square bond).
func _release(cells: Array) -> void:
	var by := {}
	for c in cells:
		var key := Vector2i((int(c) % w) / PIECE, (int(c) / w) / PIECE)
		if not by.has(key):
			by[key] = []
		by[key].append(c)
	for key in by:
		_lump(by[key])


func _lump(cells: Array) -> void:
	var ps: float = sim.PIXEL_SZ
	# The particles still there: material 12 in a decor band, at their
	# cell's centre.
	var mine := {}
	for c in cells:
		var rec: PackedByteArray = sim.particle_record(c)
		if rec.is_empty():
			continue
		var mf := rec.decode_float(28)
		if int(floor(mf)) != sim.MAT_SHROOM:
			continue
		var band := int(floor((mf - floor(mf)) / sim.FRAC_BAND))
		if band < 0 or band > 31:
			continue
		var at := Vector2((int(c) % w + 0.5) * ps, (int(c) / w + 0.5) * ps)
		if Vector2(rec.decode_float(0), rec.decode_float(4)).distance_to(at) > 0.6:
			continue
		mine[c] = band
	if mine.is_empty():
		return
	var id: int = sim.loosen_cells(mine, w)
	if id > 0:
		released += mine.size()
