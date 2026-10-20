# World queries over the particle sim's per-pixel cell classes, with the
# bitmap map's API, so the gecko does not know which world it stands on.
# The geometry helpers (probe, rays, clearance) are inherited; only the
# cell tests and the edits change. Edits go to the GPU: a melt capsule
# deletes particles, a fill spawns them. Chunks (loose lumps) read back
# as 16 + their id per cell, so the gecko can tell a lump from the
# ground, trace the piece the tongue is stuck to, push it, drag it,
# break it and swallow it. Loose grains (sand, clay) read back as their
# own class: ground to the senses, no wall to a body burrowing through.
extends "res://cave_map.gd"

var sim: Node2D
var _slot := 0
var sense_coarse := false      # The senses on the 4 px fold (sim.cells4) instead of the sim's own cells


# The senses' grid: the sim's cells (2 px) or the same folded 2x2 to
# 4 px (cell_fold.glsl), the debug panel's choice. The chunk queries
# stay on the sim's grid.
func set_sense(cell: float) -> void:
	sense_coarse = cell >= sim.PIXEL_SZ * 1.5
	sim.fold_on = sense_coarse
	if sense_coarse:
		W = sim.RENDER_W / 2
		H = sim.RENDER_H / 2
		CELL = sim.PIXEL_SZ * 2.0
		sim.read_fold()
	else:
		W = sim.RENDER_W
		H = sim.RENDER_H
		CELL = sim.PIXEL_SZ


func _ready() -> void:
	pass


func _process(_dt: float) -> void:
	pass


func generate(seed_value: int) -> void:
	sim.build(seed_value)
	sim.tick()


# Rebuilds the particles from a cell map (a test scene built on a CaveMap).
func build_cells(kinds: PackedByteArray) -> void:
	sim.build(0, kinds)
	sim.tick()


# A cell's class on the senses' grid. A crumb (CT_CRUMB added) reads
# as air: the body walks through a speck and the sim loosens it.
func _cls(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 2
	var c: PackedByteArray = sim.cells4 if sense_coarse else sim.cells
	if c.size() < W * H * 4:
		return 0
	var v := c.decode_u32((y * W + x) * 4)
	return 0 if v >= sim.CT_CRUMB else v


# A cell of the sim's own grid, whatever the senses' grid: the chunk
# queries count a lump's cells, and the thresholds on them (gecko.gd)
# are in these.
func _cls_full(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= sim.RENDER_W or y >= sim.RENDER_H:
		return 2
	var c: PackedByteArray = sim.cells
	if c.size() < sim.RENDER_W * sim.RENDER_H * 4:
		return 0
	var v := c.decode_u32((y * sim.RENDER_W + x) * 4)
	return 0 if v >= sim.CT_CRUMB else v


func is_solid(x: int, y: int) -> bool:
	var c := _cls(x, y)
	if c >= sim.CT_CHUNK:
		return not ignore_chunks
	if c == sim.CT_LOOSE:
		return not ignore_loose
	return c == sim.CT_SOLID or c == sim.CT_SLICK or c == sim.CT_CRUMBLE


# A loose grain's cell (sand, clay, the stone of a broken lump).
func is_loose(x: int, y: int) -> bool:
	return _cls(x, y) == sim.CT_LOOSE


func loose_at_world(p: Vector2) -> bool:
	return is_loose(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func is_water(x: int, y: int) -> bool:
	return _cls(x, y) == 1


func slick_world(p: Vector2) -> bool:
	return _cls(int(floor(p.x / CELL)), int(floor(p.y / CELL))) == sim.CT_SLICK


func crumble_world(p: Vector2) -> bool:
	return _cls(int(floor(p.x / CELL)), int(floor(p.y / CELL))) == sim.CT_CRUMBLE


func lava_near(p: Vector2, n: int) -> bool:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if _cls(x, y) == 3:
				return true
	return false


# Crumbling rock gives way to grains: the ground within radius is
# melted and sand poured into the hole a moment later (the readback
# must see the cells empty first).
func crumble(p: Vector2, radius: float) -> void:
	sim.melt_circle(p, radius, _slot, false)
	_slot = (_slot + 1) % 4
	get_tree().create_timer(0.05).timeout.connect(func() -> void: sim.spawn_sand_disc(p, radius * 0.8))


func wake(p: Vector2, radius: float) -> void:
	sim.wake_circle(p, radius)


func add_current(r: Rect2, dir: Vector2, speed: float) -> void:
	super.add_current(r, dir, speed)
	sim.set_currents(currents)


func clear_currents() -> void:
	super.clear_currents()
	sim.set_currents(currents)


# The chunk whose particle fills this cell of the sim's grid, or -1 for
# the ground and air.
func chunk_at(x: int, y: int) -> int:
	var c := _cls_full(x, y)
	return c - sim.CT_CHUNK if c >= sim.CT_CHUNK else -1


func chunk_at_world(p: Vector2) -> int:
	return chunk_at(int(floor(p.x / sim.PIXEL_SZ)), int(floor(p.y / sim.PIXEL_SZ)))


# The connected piece of chunk id round p: the centres (world px) of the
# cells of that id reachable from the one nearest p, eight-connected, up
# to limit of them. Empty when none of its cells is within two of p.
func chunk_piece(id: int, p: Vector2, limit := 1600) -> PackedVector2Array:
	var out := PackedVector2Array()
	var fc: float = sim.PIXEL_SZ
	var cx := int(floor(p.x / fc))
	var cy := int(floor(p.y / fc))
	var start := Vector2i(-1, -1)
	var best := INF
	for y in range(cy - 2, cy + 3):
		for x in range(cx - 2, cx + 3):
			if chunk_at(x, y) != id:
				continue
			var d := p.distance_squared_to(Vector2((x + 0.5) * fc, (y + 0.5) * fc))
			if d < best:
				best = d
				start = Vector2i(x, y)
	if start.x < 0:
		return out
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size() and out.size() < limit:
		var c: Vector2i = queue[i]
		i += 1
		out.append(Vector2((c.x + 0.5) * fc, (c.y + 0.5) * fc))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var m := Vector2i(c.x + dx, c.y + dy)
				if seen.has(m) or chunk_at(m.x, m.y) != id:
					continue
				seen[m] = true
				queue.append(m)
	return out


# Chew and brush share four melt slots in turn, so several bites in one
# tick all land. A bite takes what the material gives (all of rock, a
# part of hard rock, none of bedrock); the brush (force) takes anything.
func erase_circle(p: Vector2, radius: float, force := false) -> void:
	sim.melt_circle(p, radius, _slot, force)
	_slot = (_slot + 1) % 4


# The body's push on loose grains: two capsules along it, every tick.
func body_capsules(a0: Vector2, a1: Vector2, ra: float, b0: Vector2, b1: Vector2, rb: float) -> void:
	sim.set_body_capsules(a0, a1, ra, b0, b1, rb)


func pull_chunk(id: int, tip: Vector2, dir: Vector2, speed: float) -> void:
	sim.pull_chunk(id, tip, dir, speed)


func eat_chunk(id: int, p: Vector2, radius: float) -> void:
	sim.eat_chunk(id, p, radius)


func break_circle(p: Vector2, radius: float) -> void:
	sim.break_circle(p, radius)


# A lump of stone (a boulder, or a stone when small) or of clay, about
# p, on the air there.
func spawn_boulder(p: Vector2, radius: float) -> int:
	return sim.spawn_chunk_disc(p, radius, sim.MAT_STONE)


func spawn_clay(p: Vector2, radius: float) -> int:
	return sim.spawn_chunk_disc(p, radius, sim.MAT_CLAY)


# A vine hanging from top, length px (sim.gd). The chunk id, 0 for none.
func spawn_vine(top: Vector2, length: float) -> int:
	return sim.spawn_vine(top, length)


# Loose sand on the air within radius of p.
func spawn_sand(p: Vector2, radius: float) -> void:
	sim.spawn_sand_disc(p, radius)


# Ambience (ambience.gd): a drop of water falling from p, and a puff of
# n wisps at p drifting with vel.
func spawn_drop(p: Vector2) -> void:
	sim.spawn_drop(p)


func spawn_puff(p: Vector2, n: int, vel: Vector2, spread: float, life: float) -> void:
	sim.spawn_puff(p, n, vel, spread, life)


func fill_circle(p: Vector2, radius: float) -> void:
	sim.fill_circle(p, radius)


func fill_rect(r: Rect2) -> void:
	sim.fill_rect(r)


func copper_rect(r: Rect2) -> void:
	sim.fill_rect(r, sim.MAT_COPPER)


func material_rect(r: Rect2, kind: int) -> void:
	if kind == CELL_GAS:
		return
	sim.fill_rect(r, sim.material_of(kind), sim.frac_of(kind))


func material_circle(p: Vector2, radius: float, kind: int) -> void:
	if kind == CELL_GAS:
		return
	sim.fill_circle(p, radius, sim.material_of(kind), sim.frac_of(kind))
