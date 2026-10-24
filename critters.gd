# The chain creatures and plants of the particle world: shrooms that bend
# (shroom.gd), vines that are ropes (vine.gd), slimes (slime.gd) and
# long slugs (long_slug.gd). main.gd calls pre_tick before the sim's tick
# and post_tick after it, both before the gecko's own tick.
#
# pre_tick: which of them the gecko holds (a planted foot on its cells),
# each chain stepped with the gecko's weight on it, the gecko carried by
# the move of what it holds (gecko.gd carry), a shroom's spring handed
# to the gecko's next jump (jump_boost), the slimes' brains set from
# last tick's mass, the long slugs crept and their blobs added to the
# gecko's drawing. post_tick: the bones' counts read back, a stem or a
# vine bitten through let go below or above the bite.
#
# Shrooms and vines are skinned chunks, and need the sim; the bitmap
# world has none (add_* return false). The cost is a few microseconds a
# chain a tick and no map queries for the plants (the long slug's head
# makes one nearest_solid a tick); last_us has the tick's time.
#
# Drawn on the GPU layer (critter_layer.gd), on the 2 px grid: the
# strands (strand.gd, mycelium threads the bodies brush aside), the worms
# (long slugs in a drawn skin) and the jellyfish (jelly.gd); a pixel in
# the water takes the water's hue. The melts the sim saw (sim.gd melts) cut strands, pop
# jellyfish and wake the decor's support check (decor_support.gd).
extends Node2D

const Shroom = preload("res://shroom.gd")
const Vine = preload("res://vine.gd")
const Slime = preload("res://slime.gd")
const LongSlug = preload("res://long_slug.gd")
const Strand = preload("res://strand.gd")
const Jelly = preload("res://jelly.gd")
const CritterLayer = preload("res://critter_layer.gd")
const WORM_SPRITE := "res://decor/critters/worm.png"
const WORM_SMALL := "res://decor/critters/worm_small.png"   # Half the size (tools/pack_import.py halve): about the gecko's length
const JELLY_SHEET := "res://decor/critters/jelly.png"
const BODY_R := 2.0                         # A gecko chain point's reach when it brushes a strand (strand.gd adds its own)

const LAND_WINDOW := 6         # Ticks after the gecko's landing in which a shroom under its feet takes the landing
const JUMP_KICK := 0.15        # Of the gecko's jump speed kicked back into the held place of the vine it leaves
const WHOLE_PART := 0.7       # Of a decor mushroom's pixels that must be set for it to bend (critters.gd plan_decor): fewer, it was laid against rock or a stem was cut, and stays decor
const CATCH_K := 0.4           # Of the gecko's flight speed the vine's held point takes when it catches the vine: the rope swings away with it

var sim: Node2D
var map: Node2D
var gecko: Node2D
var shrooms: Array = []
var vines: Array = []
var slimes: Array = []
var long_slugs: Array = []
var strands: Array = []
var jellies: Array = []
static var _images := {}       # Path -> Image, the creatures' sprites read once
var _layer: Node2D             # critter_layer.gd: where the strands, worms and jellyfish are drawn
var _drawn := false            # Something was drawn last frame (a clear draws the layer empty once)
var last_us := 0               # The last pre_tick and post_tick together, µs
var draw_us := PackedInt32Array([0, 0, 0])   # The last _draw's strands, worms and jellyfish, µs
var parts_us := PackedInt32Array([0, 0, 0, 0, 0])   # Of that: the shrooms, the vines, the slimes, the long slugs, the counts read after the tick
var held: RefCounted = null    # The shroom or vine the gecko holds this tick
var _by_chunk := {}            # Chunk id -> its shroom or vine
var _land_speed := 0.0
var _land_ticks := 0
var _jumped := false
var _air_vel := Vector2.ZERO   # The gecko's speed last tick while it flew, for a catch
var _seed := 0


func setup(sim_in: Node2D, map_in: Node2D, gecko_in: Node2D) -> void:
	sim = sim_in
	map = map_in
	gecko = gecko_in
	_layer = CritterLayer.new()
	add_child(_layer)
	var cell: float = sim.PIXEL_SZ if sim else 2.0
	_layer.setup(cell, int(1920.0 / cell), int(1080.0 / cell), _draw_layer)
	if sim:
		_layer.set_cells_tex(sim.cells_tex)
	gecko.landed.connect(func(speed: float) -> void:
		_land_speed = speed
		_land_ticks = LAND_WINDOW)
	gecko.jumped.connect(func() -> void: _jumped = true)


# Everything gone (the world is rebuilt: the sim's bones and slime brains
# start over with it).
func clear() -> void:
	shrooms.clear()
	vines.clear()
	slimes.clear()
	long_slugs.clear()
	strands.clear()
	jellies.clear()
	_by_chunk.clear()
	if _layer:
		_layer.redraw()
	held = null
	if map:
		map.anchored.clear()
		if "slime_on" in map:
			map.slime_on = false
	_seed = 0


func _sim_ok() -> bool:
	return sim != null and sim.ready_to_run


# A shroom standing on the floor under p, size 1 to Shroom.MAX_SIZE
# (shroom.gd sprite_cells: the one sprite, scaled, mirrored on an odd
# variant).
func add_shroom(p: Vector2, size: int, variant := 0) -> bool:
	if not _sim_ok():
		return false
	var cells: Array = Shroom.sprite_cells(map, p, size, variant, sim.PIXEL_SZ)
	return add_shroom_plan(Shroom.plan(cells, Vector2i(0, -1), sim.PIXEL_SZ), size)


# A shroom from its plan (shroom.gd plan: a decor mushroom's cells and
# the way it grows), of size (its mass) size, or one read off its
# height for 0.
func add_shroom_plan(pl: Dictionary, size := 0) -> bool:
	if pl.get("strand", false):
		return add_strand_plan(pl)
	if not _sim_ok() or pl.is_empty():
		return false
	var s := Shroom.new()
	_seed += 1
	if not s.setup_plan(sim, map, pl, size if size > 0 else Shroom.size_of(pl, sim.PIXEL_SZ)):
		return false
	shrooms.append(s)
	_by_chunk[s.chunk] = s
	return true


# A decor stamp's cells, as SceneBuilder.stamp sets them ([x, y, kind,
# part] each), split into its mushrooms (the sprite's parts, a cluster's
# single ones) and each planned as a shroom growing along up_v; part_n
# holds each part's pixels. A part not nearly all set (laid against
# rock or other decor) or with no stem to bend stays decor. A plant
# (plant true) is the whole sprite as one, leaves and all. Returns
# [plans, the cells no plan took].
static func plan_decor(cells: Array, up_v: Vector2i, cell: float, part_n: Array, plant := false) -> Array:
	var by := {}
	for c in cells:
		var k: int = (c[3] if c.size() > 3 else -1) if not plant else 0
		if not by.has(k):
			by[k] = []
		by[k].append(c)
	var left: Array = []
	var plans: Array = []
	for k in by:
		var part: Array = by[k]
		var all_n := 0
		for n in part_n:
			all_n += int(n)
		var whole: bool = (part.size() >= int(all_n * WHOLE_PART)) if plant else (k >= 0 and k < part_n.size() and part.size() >= int(part_n[k] * WHOLE_PART))
		var pl := Shroom.plan(part, up_v, cell, plant) if whole else {}
		if pl.is_empty():
			left.append_array(part)
		else:
			plans.append(pl)
	return [plans, left]


# A vine hanging from the ceiling over p, length px.
func add_vine(p: Vector2, length: float) -> bool:
	if not _sim_ok():
		return false
	var c: Vector2 = map.ceiling_above(p)
	var v := Vine.new()
	_seed += 1
	if not v.setup(sim, map, Vector2(p.x, c.y + 2.0), length, 311 + _seed):
		return false
	vines.append(v)
	_by_chunk[v.chunk] = v
	return true


# A slime of radius r about p (on the air there).
func add_slime(p: Vector2, r: float) -> bool:
	if not _sim_ok() or slimes.size() >= sim.MAX_SLIMES:
		return false
	var s := Slime.new()
	_seed += 1
	if not s.setup(sim, p, r, slimes.size(), 523 + _seed):
		return false
	slimes.append(s)
	map.slime_on = true
	return true


# A strand from its plan (strand.gd plan: a myc_strand stamp's cells).
func add_strand_plan(pl: Dictionary) -> bool:
	var s := Strand.new()
	if not s.setup(map, pl):
		return false
	strands.append(s)
	return true


static func image(path: String) -> Image:
	if not _images.has(path):
		var img := Image.new()
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
			img = null
		else:
			img.convert(Image.FORMAT_RGBA8)
		_images[path] = img
	return _images[path]


# A worm on the surface nearest p: a long slug in the worm's skin, as
# long as the sprite (a pixel a cell): sizes 1 to 3 the small one, about
# the gecko's length, 4 and 5 the sprite as drawn, twice that.
func add_worm(p: Vector2, size := 1) -> bool:
	var img := image(WORM_SPRITE if size >= 4 else WORM_SMALL)
	if img == null:
		return false
	var cell: float = sim.PIXEL_SZ if sim else 2.0
	var s := LongSlug.new()
	_seed += 1
	s.setup(map, p, img.get_width() * cell, 707 + _seed)
	s.set_sprite(img, cell)
	long_slugs.append(s)
	return true


# A jellyfish in the water about p.
func add_jelly(p: Vector2) -> bool:
	var img := image(JELLY_SHEET)
	if img == null:
		return false
	var j := Jelly.new()
	_seed += 1
	j.setup(map, p, img, 911 + _seed)
	jellies.append(j)
	return true


# A long slug on the surface nearest p, length px.
func add_long_slug(p: Vector2, length: float) -> bool:
	var s := LongSlug.new()
	_seed += 1
	s.setup(map, p, length, 707 + _seed)
	long_slugs.append(s)
	return true


# What the gecko's planted feet stand on, among the shrooms and vines
# (or what is under its body).
func _held() -> RefCounted:
	if not gecko.clinging:
		return null
	for f in gecko.feet:
		if f.planted:
			var id: int = map.anchored_at_world(f.anchor)
			if id < 0:
				id = map.anchored_at_world(f.pos)
			if _by_chunk.has(id):
				return _by_chunk[id]
	# No foot planted on one: what is under the body (the feet plant a
	# few ticks after a landing, and lift in turn on a walk).
	for d in [gecko.RIDE_H + 1.0, gecko.RIDE_H + 3.0]:
		var id: int = map.anchored_at_world(gecko.pos - gecko.up * d)
		if _by_chunk.has(id):
			return _by_chunk[id]
	return null


func pre_tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var was: RefCounted = held
	held = _held()
	var land := 0.0
	if _land_ticks > 0:
		_land_ticks -= 1
		if held != null and held is Shroom:
			land = _land_speed
			_land_ticks = 0
	var carry := Vector2.ZERO
	var t1 := Time.get_ticks_usec()
	for s in shrooms:
		var on: bool = s == held
		var frames: Array = s.bone_frames() if on else []
		s.step(dt, gecko.pos if on else Vector2.INF, land if on else 0.0)
		if on:
			carry = _ride(gecko.pos, frames, s.bone_frames())
	gecko.jump_boost = held.boost() if (held != null and held is Shroom and gecko.up.dot(held.cap_up()) > 0.3) else Vector2.ZERO
	var t2 := Time.get_ticks_usec()
	for v in vines:
		var at: float = v.nearest(gecko.pos) if v == held else -1.0
		var kick := Vector2.ZERO
		if v == held and v != was:
			# Caught in flight: the rope takes the gecko's momentum and
			# swings away with it (the gecko rides it, carry below).
			kick = _air_vel * CATCH_K
		elif _jumped and v == was:
			# The gecko leapt off it: the rope is kicked back.
			at = v.nearest(gecko.pos)
			kick = -gecko.vel * JUMP_KICK
		var d: Vector2 = v.step(dt, at, kick, gecko.pos if v == held else Vector2.INF)
		if v == held:
			carry = d
	_jumped = false
	_air_vel = Vector2.ZERO if gecko.clinging else gecko.vel
	if carry != Vector2.ZERO:
		gecko.carry(carry)
	var t3 := Time.get_ticks_usec()
	for s in slimes:
		s.step(dt)
	var any := false
	for s in slimes:
		any = any or s.alive
	if "slime_on" in map:
		map.slime_on = any
	var t4 := Time.get_ticks_usec()
	if not long_slugs.is_empty():
		var bl: Array = gecko.extra_blobs.duplicate()
		for s in long_slugs:
			s.tick(dt, gecko)
			if s.sprite.is_empty():
				bl.append_array(s.blobs())
		gecko.extra_blobs = bl
	var bites: Array = sim.melts if sim else []
	for j in jellies:
		j.tick(dt, gecko, bites)
	if not strands.is_empty():
		var bodies := _bodies()
		for st in strands:
			st.step(dt, bodies)
	if not long_slugs.is_empty() or not jellies.is_empty() or not strands.is_empty() or _drawn:
		_layer.redraw()
		_drawn = not long_slugs.is_empty() or not jellies.is_empty() or not strands.is_empty()
	var t5 := Time.get_ticks_usec()
	last_us = t5 - t0
	parts_us[0] = t2 - t1
	parts_us[1] = t3 - t2
	parts_us[2] = t4 - t3
	parts_us[3] = t5 - t4


# How the point p moved with the bone nearest it, from the old frames to
# the new.
func _ride(p: Vector2, old: Array, now: Array) -> Vector2:
	var best := INF
	var k := 0
	for i in old.size():
		var d: float = p.distance_squared_to((old[i] as Transform2D).origin)
		if d < best:
			best = d
			k = i
	var local: Vector2 = (old[k] as Transform2D).affine_inverse() * p
	return (now[k] as Transform2D) * local - p


# What brushes the strands aside: the gecko's chain, the long slugs and
# worms, the jellyfish. [centre, reach] each.
func _bodies() -> Array:
	var out: Array = []
	if gecko and gecko.chain:
		for p in gecko.chain.points:
			out.append([p, BODY_R])
	for s in long_slugs:
		for i in range(0, s.points.size(), 2):
			out.append([s.points[i], 2.0])
	for j in jellies:
		if j.alive:
			out.append([j.pos, 6.0])
	return out


func post_tick() -> void:
	var t0 := Time.get_ticks_usec()
	if sim:
		for m in sim.melts:
			for st in strands:
				st.bite(m[0], m[1])
			if "support" in map:
				map.support.melted(m[0], m[1])
		sim.melts.clear()
		if "support" in map:
			map.support.tick()
	for i in range(jellies.size() - 1, -1, -1):
		if not jellies[i].alive:
			jellies.remove_at(i)
	for s in shrooms:
		s.check_counts()
	for v in vines:
		v.check_counts()
	parts_us[4] = Time.get_ticks_usec() - t0
	last_us += parts_us[4]


# The glows of the long slugs, for the light pass.
func glows() -> Array:
	var out: Array = []
	for s in long_slugs:
		if s.sprite.is_empty():
			out.append(s.glow())
	for j in jellies:
		if j.alive:
			out.append(j.glow())
	return out


# The drawn creatures and threads on the GPU layer (critter_layer.gd),
# the canvas there taking world px: the strands, the worms, the
# jellyfish, each a few textured quads.
func _draw_layer(c: CanvasItem) -> void:
	var cell: float = sim.PIXEL_SZ if sim else 2.0
	var t0 := Time.get_ticks_usec()
	for st in strands:
		st.draw_on(c, cell)
	var t1 := Time.get_ticks_usec()
	for s in long_slugs:
		if not s.sprite.is_empty():
			s.draw_on(c)
	var t2 := Time.get_ticks_usec()
	for j in jellies:
		j.draw_on(c, cell)
	draw_us = PackedInt32Array([t1 - t0, t2 - t1, Time.get_ticks_usec() - t2])


# The vine the gecko hangs on, for main.gd's snap; null for none.
func held_vine() -> RefCounted:
	return held if (held != null and held is Vine) else null
