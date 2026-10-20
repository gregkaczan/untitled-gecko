# Cave map: a CPU bitmap of solid cells standing in for the GPU particle
# world during the gecko spike. One cell is a 4x4 px block on screen, the
# same grid the particle sim renders at, so swapping in the live readback
# later changes only how `solid` gets filled. Queries: probe() finds the
# nearest solid and the surface normal around a point, solid_near() checks
# one anchor. Edits: erase_circle() and fill_circle() for the mouse brush.
# The bitmap has no loose lumps: the chunk queries find none and the
# chunk edits (push, pull, eat, break, spawn) do nothing.
extends Node2D

const W := 480
const H := 270
const CELL := 4.0

const ROCK := Color(0.17, 0.14, 0.12)
const ROCK_VAR := Color(0.05, 0.04, 0.03)
const RIM := Color(0.33, 0.28, 0.23)
const CAVE := Color(0.045, 0.04, 0.06)
const WATER := Color(0.07, 0.15, 0.30)
const WATER_TOP := Color(0.18, 0.32, 0.48)
const COPPER := Color(0.85, 0.47, 0.14)   # A vein's cells, drawn bright so they read as glowing
const SAND := Color(0.42, 0.36, 0.23)     # A bed or heap of sand: ground here, loose grains that flow in the sim
const CLAY := Color(0.33, 0.22, 0.14)
const LAVA := Color(0.80, 0.28, 0.05)     # A pool: neither solid nor water here, a glowing liquid in the sim
const LAVA_TOP := Color(0.98, 0.62, 0.20)
const HARD := Color(0.19, 0.19, 0.23)     # Hard rock: several bites to open
const BEDROCK := Color(0.10, 0.09, 0.13)  # Rock no bite opens
const HARD_GIVE := 0.4         # Chance a bite takes a cell of hard rock (the sim's material table says the same)
const WATER_Y := 222           # Cells: empty cells below this row inside the basin are water

# Cell values
const CELL_AIR := 0
const CELL_ROCK := 1
const CELL_WATER := 2
const CELL_COPPER := 3         # Rock to walk on and chew, drawn as a glowing vein; the sim makes it copper
const CELL_SAND := 4           # Loose sand: ground like rock here, grains that flow and pour in the sim
const CELL_CLAY := 5           # Loose clay: the same, sticky and slow in the sim
const CELL_LAVA := 6           # Lava: a drawn pool here (neither solid nor water), a liquid that glows in the sim
const CELL_HARD := 7           # Hard rock: a bite takes HARD_GIVE of its cells
const CELL_BEDROCK := 8        # Bedrock: no bite opens it

var solid := PackedByteArray()
var ignore_chunks := false     # The gecko's senses on the ground: a loose lump is not terrain, only a thing in the way (sim_map.gd; nothing to ignore here)
var ignore_loose := false      # The walk's collision burrowing: loose grains are no wall (sim_map.gd; nothing loose here)

var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D
var _noise: FastNoiseLite
var _dirty := false


func _ready() -> void:
	solid.resize(W * H)
	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_sprite = Sprite2D.new()
	_sprite.texture = _tex
	_sprite.centered = false
	_sprite.scale = Vector2(CELL, CELL)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _process(_dt: float) -> void:
	if _dirty:
		_tex.update(_img)
		_dirty = false


# One rough round chamber with a wobbly rim, a few side pockets, some
# shelves and a stalactite growing out of the rim for climbing practice,
# and a basin in the floor at the left holding a still pool. The pool
# stands in for the particle sim's water until the sim's readback feeds
# this map.
func generate(seed_value: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.frequency = 1.0
	if solid.size() != W * H:
		solid.resize(W * H)
	solid.fill(1)
	var c := Vector2(W * 0.5, H * 0.5)
	var rx := 150.0
	var ry := 95.0
	for y in H:
		for x in W:
			var d := Vector2((x + 0.5 - c.x) / rx, (y + 0.5 - c.y) / ry)
			var a := d.angle()
			var wobble := _noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 0.18
			var grain := _noise.get_noise_2d(x * 0.2, y * 0.2) * 0.02
			if d.length() < 1.0 + wobble + grain:
				solid[y * W + x] = 0
	# Pockets bitten out of the rim
	for i in 4:
		var a := i * TAU / 4.0 + 0.6 + _noise.get_noise_1d(i * 7.0) * 0.5
		var centre := c + Vector2(cos(a) * rx * 0.98, sin(a) * ry * 0.98)
		_carve_blob(centre, 26.0 + i * 4.0, 0)
	# Rock growing back into the room: shelves, a stalactite, and a dome on
	# the floor (its centre at floor level, so it has no undercut)
	_carve_blob(c + Vector2(-rx * 0.62, ry * 0.55), 22.0, 1)
	_carve_blob(c + Vector2(rx * 0.55, ry * 0.98), 26.0, 1)
	_carve_blob(c + Vector2(rx * 0.25, -ry * 0.9), 15.0, 1)
	_carve_blob(c + Vector2(-rx * 0.9, -ry * 0.1), 20.0, 1)
	_carve_blob(c + Vector2(-rx * 0.75, ry * 0.95), 30.0, 0)
	_smooth_rim()
	_smooth_rim()
	for y in range(WATER_Y, H):
		for x in W:
			if solid[y * W + x] == CELL_AIR and x < int(c.x - rx * 0.45):
				solid[y * W + x] = CELL_WATER
	_repaint(0, 0, W - 1, H - 1)


# A majority pass over the rim: a cell becomes what most of its 3x3
# neighbourhood is, which removes single-pixel specks and one-cell
# notches that the gecko would otherwise catch on. Run twice.
func _smooth_rim() -> void:
	var out := solid.duplicate()
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var rock := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if solid[(y + dy) * W + x + dx] == CELL_ROCK:
						rock += 1
			out[y * W + x] = CELL_ROCK if rock >= 5 else CELL_AIR
	solid = out


func _carve_blob(centre: Vector2, radius: float, value: int) -> void:
	var r := int(ceil(radius * 1.3))
	for y in range(int(centre.y) - r, int(centre.y) + r + 1):
		for x in range(int(centre.x) - r, int(centre.x) + r + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var off := Vector2(x + 0.5, y + 0.5) - centre
			var edge := 1.0 + _noise.get_noise_2d(x * 0.3, y * 0.3) * 0.06
			if off.length() < radius * edge:
				solid[y * W + x] = value


func is_solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return true
	var v := solid[y * W + x]
	return v == CELL_ROCK or v == CELL_COPPER or v == CELL_SAND or v == CELL_CLAY or v == CELL_HARD or v == CELL_BEDROCK


# Loose grains live in the particle world only (sim_map.gd): here a bed
# of sand is ground like rock, so the headless suite's runs stay as they
# were.
func is_loose(_x: int, _y: int) -> bool:
	return false


func loose_at_world(_p: Vector2) -> bool:
	return false


func is_water(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	return solid[y * W + x] == CELL_WATER


func is_water_world(p: Vector2) -> bool:
	return is_water(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


# True when any cell within n of the one under p is water. Particle water
# leaves gaps between cells, so a single-cell test flickers.
func water_near(p: Vector2, n: int) -> bool:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if is_water(x, y):
				return true
	return false


func is_solid_world(p: Vector2) -> bool:
	return is_solid(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


# Loose lumps live in the particle world only (see sim_map.gd).
func chunk_at_world(_p: Vector2) -> int:
	return -1


func chunk_piece(_id: int, _p: Vector2, _limit := 400) -> PackedVector2Array:
	return PackedVector2Array()


func pull_chunk(_id: int, _tip: Vector2, _dir: Vector2, _speed: float) -> void:
	pass


func eat_chunk(_id: int, _p: Vector2, _radius: float) -> void:
	pass


func break_circle(_p: Vector2, _radius: float) -> void:
	pass


func spawn_boulder(_p: Vector2, _radius: float) -> int:
	return 0


func spawn_clay(_p: Vector2, _radius: float) -> int:
	return 0


# The body's push on loose grains is the particle world's (sim_map.gd).
func body_capsules(_a0: Vector2, _a1: Vector2, _ra: float, _b0: Vector2, _b1: Vector2, _rb: float) -> void:
	pass


func spawn_sand(_p: Vector2, _radius: float) -> void:
	pass


# True when any cell within n of the one under p is solid.
func solid_near(p: Vector2, n: int) -> bool:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if is_solid(x, y):
				return true
	return false


# True when any solid cell centre lies within radius of p.
func solid_within(p: Vector2, radius: float) -> bool:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var n := int(ceil(radius / CELL))
	var r2 := radius * radius
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if is_solid(x, y) and p.distance_squared_to(Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)) < r2:
				return true
	return false


# The cell that blocks a move from p to next: the nearest solid cell to
# next among those not already within radius of p. Null when none.
func blocking_cell(p: Vector2, next: Vector2, radius: float):
	var cx := int(floor(next.x / CELL))
	var cy := int(floor(next.y / CELL))
	var n := int(ceil(radius / CELL))
	var r2 := radius * radius
	var best_d2 := INF
	var best = null
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if not is_solid(x, y):
				continue
			var c := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			var d2 := next.distance_squared_to(c)
			if d2 >= r2 or p.distance_squared_to(c) < r2:
				continue
			if d2 < best_d2:
				best_d2 = d2
				best = c
	return best


# Looks at every solid cell within radius of p. Returns the nearest one's
# centre and distance, and a normal: the weighted mean of the vectors from
# those cells to p, which is smooth across the jagged bitmap edge and
# cancels out (to zero) in a tunnel with rock on both sides.
func probe(p: Vector2, radius: float) -> Dictionary:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var n := int(ceil(radius / CELL))
	var r2 := radius * radius
	var best_d2 := r2
	var best := Vector2.ZERO
	var found := false
	var sum := Vector2.ZERO
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if not is_solid(x, y):
				continue
			var d := p - Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			var d2 := d.length_squared()
			if d2 > r2:
				continue
			var dist := sqrt(d2)
			sum += d * (1.0 - dist / radius) / maxf(dist, 0.5)
			if d2 < best_d2:
				best_d2 = d2
				best = p - d
				found = true
	var normal := Vector2.ZERO
	if sum.length_squared() > 0.0001:
		normal = sum.normalized()
	return {"found": found, "nearest": best, "dist": sqrt(best_d2), "normal": normal}


# Marches from p along dir in 2 px steps. The first solid point, or null.
func ray_hit(p: Vector2, dir: Vector2, length: float):
	var steps := int(length / 2.0)
	for i in range(steps + 1):
		var q := p + dir * (i * 2.0)
		if is_solid_world(q):
			return q
	return null


# Top edge of the first solid cell straight below p.
func floor_below(p: Vector2) -> Vector2:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	while cy < H and not is_solid(cx, cy):
		cy += 1
	return Vector2(p.x, cy * CELL)


# All rock, no repaint: the test scenes carve their rooms out of this.
func blank() -> void:
	if solid.size() != W * H:
		solid.resize(W * H)
	solid.fill(CELL_ROCK)
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.frequency = 1.0


func repaint_all() -> void:
	_repaint(0, 0, W - 1, H - 1)


# Clears a world-space rectangle to air.
func erase_rect(r: Rect2) -> void:
	_set_rect(r, CELL_AIR)


# Turns the air cells of a world-space rectangle into still water.
func water_rect(r: Rect2) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(ceil(r.end.x / CELL)) - 1
	var y1 := int(ceil(r.end.y / CELL)) - 1
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			if solid[y * W + x] == CELL_AIR:
				solid[y * W + x] = CELL_WATER
	_repaint(x0 - 1, y0 - 1, x1 + 1, y1 + 1)


# Turns a world-space rectangle into copper: a vein in the rock.
func copper_rect(r: Rect2) -> void:
	_set_rect(r, CELL_COPPER)


# A world-space rectangle, or a disc, of one cell kind (sand, clay, lava,
# hard rock, bedrock): the scenes' material ops.
func material_rect(r: Rect2, kind: int) -> void:
	_set_rect(r, kind)


func material_circle(p: Vector2, radius: float, kind: int) -> void:
	_paint_circle(p, radius, kind)


# The map as a PNG, one pixel per cell (GECKO_DUMP_MAP).
func save_png(path: String) -> void:
	if _img:
		_img.save_png(path)


# Rock under the line from a to b (world px), from the line down to the
# bottom of the map, between the two x's: a slope of any angle.
func fill_below_line(a: Vector2, b: Vector2) -> void:
	if b.x < a.x:
		var t := a
		a = b
		b = t
	var x0 := int(floor(a.x / CELL))
	var x1 := int(ceil(b.x / CELL)) - 1
	for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
		var cx := (x + 0.5) * CELL
		var f := clampf((cx - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
		var line_y := lerpf(a.y, b.y, f)
		var y0 := int(floor(line_y / CELL))
		for y in range(maxi(y0, 0), H):
			solid[y * W + x] = CELL_ROCK
	_repaint(x0 - 1, 0, x1 + 1, H - 1)


# Rock over the line from a to b: from the top of the map down to it.
func fill_above_line(a: Vector2, b: Vector2) -> void:
	if b.x < a.x:
		var t := a
		a = b
		b = t
	var x0 := int(floor(a.x / CELL))
	var x1 := int(ceil(b.x / CELL)) - 1
	for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
		var cx := (x + 0.5) * CELL
		var f := clampf((cx - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
		var line_y := lerpf(a.y, b.y, f)
		var y1 := int(ceil(line_y / CELL)) - 1
		for y in range(0, mini(y1, H - 1) + 1):
			solid[y * W + x] = CELL_ROCK
	_repaint(x0 - 1, 0, x1 + 1, H - 1)


# One cell at a world point.
func set_cell_world(p: Vector2, value: int) -> void:
	var x := int(floor(p.x / CELL))
	var y := int(floor(p.y / CELL))
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	solid[y * W + x] = value
	_repaint(x - 1, y - 1, x + 1, y + 1)


# First solid cell straight above p: the underside of a ceiling.
func ceiling_above(p: Vector2) -> Vector2:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	while cy >= 0 and not is_solid(cx, cy):
		cy -= 1
	return Vector2(p.x, (cy + 1) * CELL)


func _set_rect(r: Rect2, value: int) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(ceil(r.end.x / CELL)) - 1
	var y1 := int(ceil(r.end.y / CELL)) - 1
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			solid[y * W + x] = value
	_repaint(x0 - 1, y0 - 1, x1 + 1, y1 + 1)


# Fills a world-space rectangle with rock (a test wall for the demos).
func fill_rect(r: Rect2) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(ceil(r.end.x / CELL)) - 1
	var y1 := int(ceil(r.end.y / CELL)) - 1
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			solid[y * W + x] = CELL_ROCK
	_repaint(x0 - 1, y0 - 1, x1 + 1, y1 + 1)


# A bite: the circle's cells to air, but for bedrock, which stays, and
# hard rock, of which a bite takes HARD_GIVE of the cells. The brush
# (force) takes anything.
func erase_circle(p: Vector2, radius: float, force := false) -> void:
	_paint_circle(p, radius, CELL_AIR, not force)


func fill_circle(p: Vector2, radius: float) -> void:
	_paint_circle(p, radius, CELL_ROCK)


func _paint_circle(p: Vector2, radius: float, value: int, bite := false) -> void:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var n := int(ceil(radius / CELL))
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			if Vector2((x + 0.5) * CELL, (y + 0.5) * CELL).distance_to(p) >= radius:
				continue
			if bite:
				var v := solid[y * W + x]
				if v == CELL_BEDROCK or (v == CELL_HARD and randf() >= HARD_GIVE):
					continue
			solid[y * W + x] = value
	_repaint(cx - n - 1, cy - n - 1, cx + n + 1, cy + n + 1)


# Rock gets a grain from the noise and a lighter rim where it meets air,
# so the surface the gecko walks on reads at a glance. Water and lava
# are flat with a lighter surface row. Sand and clay get the grain in
# their own colours, hard rock and bedrock a fainter rim.
func _repaint(x0: int, y0: int, x1: int, y1: int) -> void:
	if _img == null:
		return
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			var v := solid[y * W + x]
			var col := CAVE
			if is_water(x, y):
				col = WATER_TOP if not is_water(x, y - 1) and not is_solid(x, y - 1) else WATER
			elif v == CELL_LAVA:
				col = LAVA_TOP if y > 0 and solid[(y - 1) * W + x] == CELL_AIR else LAVA
			elif v == CELL_COPPER:
				col = COPPER
			elif is_solid(x, y):
				var rim := not (is_solid(x - 1, y) and is_solid(x + 1, y) and is_solid(x, y - 1) and is_solid(x, y + 1))
				var grain := _noise.get_noise_2d(x * 0.7, y * 0.7)
				match v:
					CELL_SAND:
						col = SAND + ROCK_VAR * grain
					CELL_CLAY:
						col = CLAY + ROCK_VAR * grain
					CELL_HARD:
						col = HARD.lightened(0.12) if rim else HARD + ROCK_VAR * grain * 0.5
					CELL_BEDROCK:
						col = BEDROCK.lightened(0.12) if rim else BEDROCK
					_:
						col = RIM if rim else ROCK + ROCK_VAR * grain
			_img.set_pixel(x, y, col)
	_dirty = true
