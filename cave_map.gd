# Cave map: a CPU bitmap of solid cells standing in for the GPU particle
# world during the gecko spike. One cell is a 2x2 px block on screen, the
# same grid the particle sim renders at, so swapping in the live readback
# later changes only how `solid` gets filled. Queries: probe() finds the
# nearest solid and the surface normal around a point, solid_near() checks
# one anchor. Edits: erase_circle() and fill_circle() for the mouse brush.
# The bitmap has no loose lumps: the chunk queries find none and the
# chunk edits (push, pull, eat, break, spawn) do nothing.
extends Node2D

const DecorPalettes = preload("res://decor_palettes.gd")

const W_FULL := 960            # The cell grid: the sim's render grid, 2 px cells
const H_FULL := 540
const CELL_FULL := 2.0
var W := W_FULL                # This map's grid; the particle world's senses can fold it to 4 px (sim_map.gd)
var H := H_FULL
var CELL := CELL_FULL
# A carve takes the cells whose centres lie within its radius, so its
# opening is the radius plus half a cell each way. The gecko's rules (a
# bite of about 11 px, the clearance of 9) were set on 4 px cells, so a
# carve on finer ones is widened by the half cell lost, and a bite or a
# chewed tunnel comes out the size it did.
const CARVE_PAD := (4.0 - CELL_FULL) * 0.5

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
const SHROOM := Color(0.42, 0.82, 0.46)  # Glowshroom flesh
const MOSS := Color(0.20, 0.42, 0.20)    # Slippery moss
const CRUMBLE := Color(0.46, 0.40, 0.33) # Crumbling rock, paler and dry
const THORN := Color(0.80, 0.82, 0.78)   # Thorns, pale and bony
const GAS := Color(0.05, 0.07, 0.04)     # A gas pocket: air with a tint
const LAVA_TOP := Color(0.98, 0.62, 0.20)
const HARD := Color(0.19, 0.19, 0.23)     # Hard rock: several bites to open
const BEDROCK := Color(0.10, 0.09, 0.13)  # Rock no bite opens
const HARD_GIVE := 0.4         # Chance a bite takes a cell of hard rock (the sim's material table says the same)
const WATER_Y := 444           # Cells: empty cells below this row inside the basin are water

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
const CELL_SHROOM := 9         # Glowshroom: decor that is ground to the gecko and a green light in the sim; a bite takes it
const CELL_MOSS := 10          # Slippery moss: a coat on rock, solid, but the feet cannot hold it off a floor; a bite takes it
const CELL_CRUMBLE := 11       # Crumbling rock: gives way under a hold of a second (gecko.gd), to grains in the sim
const CELL_GAS := 12           # A gas pocket: air that bursts when a bite opens it (main.gd)
const CELL_THORN := 13         # Thorns: a sharp plant on a rock face, solid, but no foot holds it and a touch throws the body off (gecko.gd); a bite takes it
const CELL_DECOR := 16         # Decor, 16 to 47: a stamp's pixel (tests/scene_builder.gd), its colour index kind - 16 & 15 in its band's palette (decor_palettes.gd), a glow from 32 up; solid, ground to the gecko, gone with a bite
const DECOR_PALETTE: Array[Color] = [   # The first decor palette, sage (decor/palette.png, decor_palettes.gd): what tools and tests that know no bands draw with
	Color(0.024, 0.043, 0.016),
	Color(0.114, 0.176, 0.086),
	Color(0.137, 0.224, 0.118),
	Color(0.212, 0.255, 0.145),
	Color(0.251, 0.325, 0.180),
	Color(0.588, 0.616, 0.627),   # A mid grey, a light grey (9) and a white (14): the white moss
	Color(0.278, 0.373, 0.220),
	Color(0.388, 0.416, 0.267),
	Color(0.451, 0.557, 0.369),
	Color(0.839, 0.867, 0.878),
	Color(0.580, 0.616, 0.455),
	Color(0.631, 0.702, 0.529),
	Color(0.710, 0.804, 0.608),
	Color(0.804, 0.824, 0.655),
	Color(0.953, 0.965, 0.957),
	Color(0.945, 0.933, 0.788),
]

var solid := PackedByteArray()
var ignore_chunks := false     # The gecko's senses on the ground: a loose lump is not terrain, only a thing in the way (sim_map.gd; nothing to ignore here)
var ignore_loose := false      # The walk's collision burrowing: loose grains are no wall (sim_map.gd; nothing loose here)
var anchored := {}             # Chunk ids that are ground to the gecko, not lumps: the critters' skinned chunks (critters.gd, sim_map.gd)

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
	var rx := 300.0
	var ry := 190.0
	for y in H:
		for x in W:
			var d := Vector2((x + 0.5 - c.x) / rx, (y + 0.5 - c.y) / ry)
			var a := d.angle()
			var wobble := _noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 0.18
			var grain := _noise.get_noise_2d(x * 0.1, y * 0.1) * 0.02
			if d.length() < 1.0 + wobble + grain:
				solid[y * W + x] = 0
	# Pockets bitten out of the rim
	for i in 4:
		var a := i * TAU / 4.0 + 0.6 + _noise.get_noise_1d(i * 7.0) * 0.5
		var centre := c + Vector2(cos(a) * rx * 0.98, sin(a) * ry * 0.98)
		_carve_blob(centre, 52.0 + i * 8.0, 0)
	# Rock growing back into the room: shelves, a stalactite, and a dome on
	# the floor (its centre at floor level, so it has no undercut)
	_carve_blob(c + Vector2(-rx * 0.62, ry * 0.55), 44.0, 1)
	_carve_blob(c + Vector2(rx * 0.55, ry * 0.98), 52.0, 1)
	_carve_blob(c + Vector2(rx * 0.25, -ry * 0.9), 30.0, 1)
	_carve_blob(c + Vector2(-rx * 0.9, -ry * 0.1), 40.0, 1)
	_carve_blob(c + Vector2(-rx * 0.75, ry * 0.95), 60.0, 0)
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
	return v == CELL_ROCK or v == CELL_COPPER or v == CELL_SAND or v == CELL_CLAY or v == CELL_HARD or v == CELL_BEDROCK \
			or v == CELL_SHROOM or v == CELL_MOSS or v == CELL_CRUMBLE or v == CELL_THORN or v >= CELL_DECOR


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


# The surface rules' senses (gecko.gd): moss under a point, crumbling
# rock under a point, lava within n cells, a falling drop (a water cell
# with air under it) within n cells.
func slick_world(p: Vector2) -> bool:
	return _kind_world(p) == CELL_MOSS


func crumble_world(p: Vector2) -> bool:
	return _kind_world(p) == CELL_CRUMBLE


func thorn_world(p: Vector2) -> bool:
	return _kind_world(p) == CELL_THORN


func _kind_world(p: Vector2) -> int:
	var x := int(floor(p.x / CELL))
	var y := int(floor(p.y / CELL))
	if x < 0 or y < 0 or x >= W or y >= H:
		return CELL_AIR
	return solid[y * W + x]


func lava_near(p: Vector2, n: int) -> bool:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	for y in range(maxi(cy - n, 0), mini(cy + n, H - 1) + 1):
		for x in range(maxi(cx - n, 0), mini(cx + n, W - 1) + 1):
			if solid[y * W + x] == CELL_LAVA:
				return true
	return false


func drop_near(p: Vector2, n: int) -> bool:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	# A drop is water over air with no water for 12 px below it: a crest
	# of a pool's surface, or the spray a 2 px water line throws up a
	# bank, is not one (the gecko climbing out of a pool was knocked off
	# by its own splash every other tick).
	var depth := int(ceil(12.0 / CELL))
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if not is_water(x, y) or is_water(x, y + 1) or is_solid(x, y + 1):
				continue
			var falling := true
			for k in range(2, depth + 1):
				if is_water(x, y + k):
					falling = false
					break
			if falling:
				return true
	return false


# Crumbling rock within radius of p gives way: to air here, to grains
# in the sim (sim_map.gd).
func crumble(p: Vector2, radius: float) -> void:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var n := int(ceil((radius + CARVE_PAD) / CELL)) + 1
	for y in range(maxi(cy - n, 0), mini(cy + n, H - 1) + 1):
		for x in range(maxi(cx - n, 0), mini(cx + n, W - 1) + 1):
			if solid[y * W + x] == CELL_CRUMBLE and Vector2((x + 0.5) * CELL, (y + 0.5) * CELL).distance_to(p) < radius + CARVE_PAD:
				solid[y * W + x] = CELL_AIR
	_repaint(cx - n - 1, cy - n - 1, cx + n + 1, cy + n + 1)


# Moss on the rock faces inside r: rock cells with an open neighbour.
func coat_moss(r: Rect2) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(ceil(r.end.x / CELL)) - 1
	var y1 := int(ceil(r.end.y / CELL)) - 1
	var coat: Array[Vector2i] = []
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			if solid[y * W + x] != CELL_ROCK:
				continue
			if not is_solid(x - 1, y) or not is_solid(x + 1, y) or not is_solid(x, y - 1) or not is_solid(x, y + 1):
				coat.append(Vector2i(x, y))
	for c in coat:
		solid[c.y * W + c.x] = CELL_MOSS
	_repaint(x0 - 1, y0 - 1, x1 + 1, y1 + 1)


# Cells of one kind inside r become another (crumbling rock out of rock).
func paint_kind(r: Rect2, from_kind: int, to_kind: int) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(ceil(r.end.x / CELL)) - 1
	var y1 := int(ceil(r.end.y / CELL)) - 1
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			if solid[y * W + x] == from_kind:
				solid[y * W + x] = to_kind
	_repaint(x0 - 1, y0 - 1, x1 + 1, y1 + 1)


# A gas pocket burst: its cells are plain air now.
func clear_gas(r: Rect2) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var y0 := int(floor(r.position.y / CELL))
	var x1 := int(ceil(r.end.x / CELL)) - 1
	var y1 := int(ceil(r.end.y / CELL)) - 1
	for y in range(maxi(y0, 0), mini(y1, H - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
			if solid[y * W + x] == CELL_GAS:
				solid[y * W + x] = CELL_AIR
	_repaint(x0 - 1, y0 - 1, x1 + 1, y1 + 1)


# Currents: [rect, unit direction, speed] each (the scene's ops). The
# gecko swimming in one is carried; the sim's water runs with it.
var currents: Array = []


func add_current(r: Rect2, dir: Vector2, speed: float) -> void:
	currents.append([r, dir.normalized(), speed])


func clear_currents() -> void:
	currents.clear()


func current_at(p: Vector2) -> Vector2:
	for c in currents:
		if c[0].has_point(p):
			return c[1] * c[2]
	return Vector2.ZERO


# The bitmap's grains do not move: nothing to wake.
func wake(_p: Vector2, _radius: float) -> void:
	pass


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


func anchored_at_world(_p: Vector2) -> int:
	return -1


# No slime in the bitmap (sim_map.gd).
func slime_near(_p: Vector2, _n: int) -> bool:
	return false


func rock_world(p: Vector2) -> bool:
	return is_solid_world(p)


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


# The bitmap has no drops or wisps (ambience.gd).
func spawn_drop(_p: Vector2) -> void:
	pass


func spawn_puff(_p: Vector2, _n: int, _vel: Vector2, _spread: float, _life: float) -> void:
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
# The nearest solid cell within radius of p: found, dist and nearest as
# probe gives them, without the normal. Ring by ring out from p's cell,
# stopping once no further ring can hold a nearer cell (a ring's cells
# are at least half a cell further than the ring before), so a point
# riding over a floor scans a few rings, not the whole square: the
# drawn body's ten points cost 1.8 ms a tick on probe's full square.
func nearest_solid(p: Vector2, radius: float) -> Dictionary:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var n := int(ceil(radius / CELL))
	var best_d2 := radius * radius
	var best := Vector2.ZERO
	var found := false
	var half := CELL * 0.5
	for k in range(0, n + 1):
		if found and (k - 0.5) * CELL >= sqrt(best_d2):
			break
		var y0 := cy - k
		var y1 := cy + k
		for x in range(cx - k, cx + k + 1):
			if is_solid(x, y0):
				var d2 := p.distance_squared_to(Vector2(x * CELL + half, y0 * CELL + half))
				if d2 < best_d2:
					best_d2 = d2
					best = Vector2(x * CELL + half, y0 * CELL + half)
					found = true
			if k > 0 and is_solid(x, y1):
				var d2 := p.distance_squared_to(Vector2(x * CELL + half, y1 * CELL + half))
				if d2 < best_d2:
					best_d2 = d2
					best = Vector2(x * CELL + half, y1 * CELL + half)
					found = true
		if k > 0:
			var x0 := cx - k
			var x1 := cx + k
			for y in range(cy - k + 1, cy + k):
				if is_solid(x0, y):
					var d2 := p.distance_squared_to(Vector2(x0 * CELL + half, y * CELL + half))
					if d2 < best_d2:
						best_d2 = d2
						best = Vector2(x0 * CELL + half, y * CELL + half)
						found = true
				if is_solid(x1, y):
					var d2 := p.distance_squared_to(Vector2(x1 * CELL + half, y * CELL + half))
					if d2 < best_d2:
						best_d2 = d2
						best = Vector2(x1 * CELL + half, y * CELL + half)
						found = true
	return {"found": found, "nearest": best, "dist": sqrt(best_d2)}


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


# The near edge of the first solid cell to the right (dir 1) or the
# left (dir -1) of p on p's row, or the world's edge.
func wall_beside(p: Vector2, dir: int) -> Vector2:
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	while cx >= 0 and cx < W and not is_solid(cx, cy):
		cx += dir
	return Vector2((cx + (1 if dir < 0 else 0)) * CELL, p.y)


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


# The cells as a PNG for a level file (editor.gd): one pixel a cell,
# its kind in the red channel, so it loads back exactly; the dump above
# is the drawn look, for a glance.
func save_cells_png(path: String) -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			img.set_pixel(x, y, Color8(solid[y * W + x], 0, 0, 255))
	img.save_png(path)


func load_cells_png(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.get_width() != W or img.get_height() != H:
		push_error("no cell map at " + path)
		return false
	for y in H:
		for x in W:
			solid[y * W + x] = img.get_pixel(x, y).r8
	repaint_all()
	return true


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


# A decor cell's kind: a palette colour and whether it glows.
static func decor_kind(colour: int, glow: bool) -> int:
	return CELL_DECOR + (colour & 15) + (16 if glow else 0)


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
	_paint_circle(p, radius + CARVE_PAD, CELL_AIR, not force)


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
			elif v == CELL_GAS:
				col = GAS
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
					CELL_SHROOM:
						col = SHROOM.lightened(0.15) if rim else SHROOM
					CELL_MOSS:
						col = MOSS.lightened(0.1) if rim else MOSS
					CELL_CRUMBLE:
						col = CRUMBLE.lightened(0.12) if rim else CRUMBLE + ROCK_VAR * grain
					CELL_THORN:
						col = THORN.lightened(0.1) if rim else THORN - ROCK_VAR * grain
					_:
						if v >= CELL_DECOR:
							col = DecorPalettes.colour_at(v - CELL_DECOR, x, y, CELL)   # A stamp's pixel, as drawn, in its band's palette
						else:
							col = RIM if rim else ROCK + ROCK_VAR * grain
			_img.set_pixel(x, y, col)
	_dirty = true
