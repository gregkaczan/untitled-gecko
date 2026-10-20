# World queries over the particle sim's per-pixel cell classes, with the
# bitmap map's API, so the gecko does not know which world it stands on.
# The geometry helpers (probe, rays, clearance) are inherited; only the
# cell tests and the edits change. Edits go to the GPU: a melt capsule
# deletes particles, a fill spawns them. Chunks (loose lumps) read back
# as 16 + their id per cell, so the gecko can tell a lump from the
# ground, trace the piece the tongue is stuck to, push it, drag it,
# break it and swallow it.
extends "res://cave_map.gd"

var sim: Node2D
var _slot := 0


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


func _cls(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 2
	var c: PackedByteArray = sim.cells
	if c.size() < W * H * 4:
		return 0
	return c.decode_u32((y * W + x) * 4)


func is_solid(x: int, y: int) -> bool:
	var c := _cls(x, y)
	if c >= sim.CT_CHUNK:
		return not ignore_chunks
	return c == 2 or c == 3


func is_water(x: int, y: int) -> bool:
	return _cls(x, y) == 1


# The chunk whose particle fills this cell, or -1 for the ground and air.
func chunk_at(x: int, y: int) -> int:
	var c := _cls(x, y)
	return c - sim.CT_CHUNK if c >= sim.CT_CHUNK else -1


func chunk_at_world(p: Vector2) -> int:
	return chunk_at(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


# The connected piece of chunk id round p: the centres (world px) of the
# cells of that id reachable from the one nearest p, eight-connected, up
# to limit of them. Empty when none of its cells is within two of p.
func chunk_piece(id: int, p: Vector2, limit := 400) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var start := Vector2i(-1, -1)
	var best := INF
	for y in range(cy - 2, cy + 3):
		for x in range(cx - 2, cx + 3):
			if chunk_at(x, y) != id:
				continue
			var d := p.distance_squared_to(Vector2((x + 0.5) * CELL, (y + 0.5) * CELL))
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
		out.append(Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var m := Vector2i(c.x + dx, c.y + dy)
				if seen.has(m) or chunk_at(m.x, m.y) != id:
					continue
				seen[m] = true
				queue.append(m)
	return out


# Chew and brush share four melt slots in turn, so several bites in one
# tick all land.
func erase_circle(p: Vector2, radius: float) -> void:
	sim.melt_circle(p, radius, _slot)
	_slot = (_slot + 1) % 4


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


# Loose sand on the air within radius of p.
func spawn_sand(p: Vector2, radius: float) -> void:
	sim.spawn_sand_disc(p, radius)


func fill_circle(p: Vector2, radius: float) -> void:
	sim.fill_circle(p, radius)


func fill_rect(r: Rect2) -> void:
	sim.fill_rect(r)


func copper_rect(r: Rect2) -> void:
	sim.fill_rect(r, sim.MAT_COPPER)
