# Particle world: the GPU PBD simulation from untitled-idle-shooter, cut
# down to what the gecko needs. Every particle is a 4 px block; one SSBO
# holds parameters, the material table, the spatial hash, the particles,
# the render buffers, and at its tail a cell-class buffer (air, water,
# solid, lava per render pixel) that render_write.glsl fills and the CPU
# reads back every tick. That readback is the gecko's whole world: the
# same 480x270 grid the bitmap stand-in used.
#
# After the cell classes comes a bond record per particle: chunks (a
# boulder, a stone, a clump of clay) are lumps of loose material whose
# particles are bonded to their lattice neighbours, so the lump keeps
# its shape, falls as one, can be pushed, dragged by the tongue, broken
# by a strike and swallowed. A chunk's cells read back as 16 + its id.
#
# The particle count covers the full 1920x1080 (the shooter started at
# its ground line), so every offset after O_PT differs from the shooter's
# and the nine shaders carry the matching literals.
extends Node2D

const CaveMap = preload("res://cave_map.gd")

const WORLD_W := 1920.0
const WORLD_H := 1080.0
const PIXEL_SZ := 4.0
const CELL_SZ := 12.0
const SUPPORT_R := 12.0
const GW := 160
const GH := 90
const MPC := 32
const RENDER_W := 480
const RENDER_H := 270
const SIM_DT := 1.0 / 60.0
const GRAVITY := 900.0
const WORKGROUP := 256
const SOLVER_ITERS := 6

const O_P := 0
const O_M := 40
const O_GC := 136
const O_GP := 14536
const O_PT := 475336
const PARTICLE_COUNT := RENDER_W * RENDER_H     # 129600
const O_RN := O_PT + PARTICLE_COUNT * 8          # 1512136
const O_WD := O_RN + RENDER_W * RENDER_H
const O_LD := O_WD + RENDER_W * RENDER_H
const O_CD := O_LD + RENDER_W * RENDER_H
const O_NF := O_CD + RENDER_W * RENDER_H
const O_NP := O_NF + GW * GH * 2
const MAX_CAPSULES := 8
const O_CAP := O_NP + 3
const O_FB := O_CAP + MAX_CAPSULES * 8
const MAX_IMPACTS := 32
const O_SC := O_FB + 3 + MAX_IMPACTS * 2
const O_CT := O_SC + GW * GH                     # 2073870, see render_write.glsl
const O_BD := O_CT + RENDER_W * RENDER_H         # 2203470, see pbd_predict.glsl
const BD_STRIDE := 20                            # Per particle: chunk id, awake, bond count, pad, 8 x (mate, rest)
const MAX_BONDS := 8
const BOND_NONE := 0xFFFFFFFF
const TOTAL_UINTS := O_BD + PARTICLE_COUNT * BD_STRIDE
const CT_CHUNK := 16                             # Cell class 16 + id: a cell of chunk id

const MAT_SAND := 0
const MAT_WATER := 1
const MAT_CLAY := 2
const MAT_ROCK := 3
const MAT_STONE := 4                             # The shooter's wood slot: loose stone, the stuff of boulders
const MAT_COPPER := 6                            # A vein: rock that glows, from the map's copper cells

# Capsule slots: 0 to 3 melt (chew and brush, in turn), then the pull
# (the tongue's drag, the walk's shove), and one-shot events (eat, break).
const SLOT_PULL := 5
const SLOT_EVENT := 6

const SHADER_FILES := [
	"pbd_predict", "grid_clear", "grid_insert",
	"pbd_lambda", "pbd_delta", "pbd_finalize",
	"render_clear", "render_write", "render_water",
]
enum S { PREDICT, GRID_CLEAR, GRID_INSERT, LAMBDA, DELTA, FINALIZE, RENDER_CLEAR, RENDER_WRITE, RENDER_WATER }

const BACKDROP := Color(0.045, 0.04, 0.06)

var cells := PackedByteArray()      # O_CT readback: one uint per render pixel
var ready_to_run := false
var chunks := {}                    # Chunk id -> {mat, count} as spawned (the GPU owns what is left of each)

var _rd: RenderingDevice
var _buf: RID
var _uniform_set: RID
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _display_img: Image
var _display_tex: ImageTexture
var _sprite: Sprite2D
var _params := PackedByteArray()
var _capsules := PackedByteArray()
var _capsule_once: Array[bool] = []  # Slots to switch off after the next dispatch
var _zero12 := PackedByteArray()
var _zero4 := PackedByteArray()
var _zero_bd := PackedByteArray()
var _next_chunk := 1
var _explosions: Array[Dictionary] = []
var _dead: Array[int] = []           # Free particle slots
var _tick := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	assert(O_CT == 2073870, "O_CT must match the literal in render_write.glsl, render_clear.glsl and pbd_finalize.glsl")
	assert(O_BD == 2203470, "O_BD must match the literal in pbd_predict.glsl, pbd_delta.glsl and render_write.glsl")
	z_index = -1
	_params.resize(40 * 4)
	_capsules.resize(MAX_CAPSULES * 8 * 4)
	_capsule_once.resize(MAX_CAPSULES)
	_capsule_once.fill(false)
	_zero12.resize(12)
	_zero4.resize(4)
	_zero_bd.resize(BD_STRIDE * 4)
	_rd = RenderingServer.create_local_rendering_device()
	for shader_name in SHADER_FILES:
		var shader_file := load("res://shaders/%s.glsl" % shader_name) as RDShaderFile
		var spirv := shader_file.get_spirv()
		var err := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if err != "":
			push_error("Shader %s: %s" % [shader_name, err])
		var shader := _rd.shader_create_from_spirv(spirv)
		_shaders.append(shader)
		_pipelines.append(_rd.compute_pipeline_create(shader))
	_display_img = Image.create(RENDER_W, RENDER_H, false, Image.FORMAT_RGBA8)
	_display_tex = ImageTexture.create_from_image(_display_img)
	_sprite = Sprite2D.new()
	_sprite.texture = _display_tex
	_sprite.centered = false
	_sprite.scale = Vector2(PIXEL_SZ, PIXEL_SZ)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, WORLD_W, WORLD_H), BACKDROP)


# Builds (or rebuilds) the whole buffer for the chamber with this seed.
# Builds the world from the generator's cave for seed_value, or from a
# cell map (one byte per render cell, CaveMap's values) when one is given.
func build(seed_value: int, kinds := PackedByteArray()) -> void:
	_rng.seed = seed_value
	_dead.clear()
	_explosions.clear()
	_capsules.fill(0)
	chunks.clear()
	_next_chunk = 1
	var data := _create_initial_data(seed_value, kinds)
	if _buf.is_valid():
		_rd.buffer_update(_buf, 0, data.size(), data)
	else:
		_buf = _rd.storage_buffer_create(data.size(), data)
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = 0
		uniform.add_id(_buf)
		_uniform_set = _rd.uniform_set_create([uniform], _shaders[0], 0)
	ready_to_run = true


# One simulation step: upload parameters and capsules, run the pipeline,
# read the cell classes back. Called from the main physics tick, before
# the gecko moves.
func tick() -> void:
	if not ready_to_run:
		return
	_update_params()
	_dispatch()
	cells = _rd.buffer_get_data(_buf, O_CT * 4, RENDER_W * RENDER_H * 4)
	for i in MAX_CAPSULES:
		if _capsule_once[i]:
			_capsule_once[i] = false
			set_capsule(i, Vector2.ZERO, Vector2.DOWN, 1.0, 1.0, false)


# Once per frame: the rendered pixels into the display texture.
func read_render() -> void:
	if not ready_to_run:
		return
	var bytes := _rd.buffer_get_data(_buf, O_RN * 4, RENDER_W * RENDER_H * 4)
	_display_img.set_data(RENDER_W, RENDER_H, false, Image.FORMAT_RGBA8, bytes)
	_display_tex.update(_display_img)


# Queue a blast; the GPU takes two per tick from the queue.
func trigger_explosion_at(pos: Vector2, radius: float, implode := false) -> void:
	_explosions.append({"pos": pos, "radius": radius, "implode": implode})


# Slot layout: [pos.x, pos.y, dir.x, dir.y, radius, half_length, active,
# mode]. Mode 0 is a plain collider, above 0 a melter (that probability
# per tick), -1 a pusher of loose material only, -2 a pull on chunk
# half_length (dir, speed in radius), -3 eats chunk half_length within
# radius, -4 breaks the bonds within radius.
func set_capsule(i: int, pos: Vector2, dir: Vector2, radius: float, half_length: float, active: bool, mode := 0.0) -> void:
	var base := i * 8 * 4
	_capsules.encode_float(base + 0, pos.x)
	_capsules.encode_float(base + 4, pos.y)
	_capsules.encode_float(base + 8, dir.x)
	_capsules.encode_float(base + 12, dir.y)
	_capsules.encode_float(base + 16, radius)
	_capsules.encode_float(base + 20, half_length)
	_capsules.encode_float(base + 24, 1.0 if active else 0.0)
	_capsules.encode_float(base + 28, mode)


# Deletes every ground particle in the circle on the next tick.
func melt_circle(pos: Vector2, radius: float, slot: int) -> void:
	set_capsule(slot, pos, Vector2.RIGHT, radius, 0.0, true, 1.0)
	_capsule_once[slot] = true


# Moves the whole of chunk id along dir at speed (px/s) on the next
# tick; the tongue re-issues it every tick it drags, the walk every
# tick it shoves a lump ahead of it. (Mode -1, a pusher capsule that
# shoves loose particles out of its way, is in the shaders but unused:
# it rolls or flattens a lump against itself instead of moving it.)
func pull_chunk(id: int, tip: Vector2, dir: Vector2, speed: float) -> void:
	set_capsule(SLOT_PULL, tip, dir, speed, float(id), true, -2.0)
	_capsule_once[SLOT_PULL] = true


# Deletes chunk id's particles within radius of pos on the next tick.
func eat_chunk(id: int, pos: Vector2, radius: float) -> void:
	set_capsule(SLOT_EVENT, pos, Vector2.RIGHT, radius, float(id), true, -3.0)
	_capsule_once[SLOT_EVENT] = true


# Breaks every bond within radius of pos on the next tick: a lump hit
# there comes apart into grains, and in two if the circle cuts it.
func break_circle(pos: Vector2, radius: float) -> void:
	set_capsule(SLOT_EVENT, pos, Vector2.RIGHT, radius, 0.0, true, -4.0)
	_capsule_once[SLOT_EVENT] = true


# A particle at rest sleeps until something moves it; loose material
# that should settle (a heap of sand) is spawned with a little velocity.
func spawn_particle(pos: Vector2, mat: int, vel := Vector2.ZERO) -> void:
	if _dead.is_empty() or not ready_to_run:
		return
	var idx: int = _dead.pop_back()
	var encoded := float(mat) + _rng.randf_range(0.0, 0.99) * 0.1
	var p := PackedFloat32Array([pos.x, pos.y, vel.x, vel.y, pos.x, pos.y, 0.0, encoded])
	_rd.buffer_update(_buf, (O_PT + idx * 8) * 4, 32, p.to_byte_array())
	# A slot that once held a chunk's particle keeps its bonds: cleared.
	_rd.buffer_update(_buf, (O_BD + idx * BD_STRIDE) * 4, _zero_bd.size(), _zero_bd)


# A lump of loose material: one particle per cell (Vector2i render
# cells), each bonded to its lattice neighbours, the eight around it, at
# their rest distance. The lump holds its shape, falls, can be pushed or
# dragged as one, and comes apart where its bonds are broken. Returns
# the chunk id, or 0 when there are no cells or not enough free slots.
func spawn_chunk(list: Array, mat: int) -> int:
	if not ready_to_run or list.is_empty() or _dead.size() < list.size():
		return 0
	var id := _next_chunk
	_next_chunk += 1
	var index := {}
	var at := {}
	for c in list:
		var idx: int = _dead.pop_back()
		index[c] = idx
		at[idx] = Vector2((c.x + 0.5) * PIXEL_SZ, (c.y + 0.5) * PIXEL_SZ)
	for c in list:
		var idx: int = index[c]
		var p: Vector2 = at[idx]
		var encoded := float(mat) + _rng.randf_range(0.0, 0.99) * 0.1
		var rec := PackedFloat32Array([p.x, p.y, 0.0, 0.0, p.x, p.y, 0.0, encoded])
		_rd.buffer_update(_buf, (O_PT + idx * 8) * 4, 32, rec.to_byte_array())
		var bd := PackedByteArray()
		bd.resize(BD_STRIDE * 4)
		bd.encode_u32(0, id)
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var m := Vector2i(c.x + dx, c.y + dy)
				if n >= MAX_BONDS or not index.has(m):
					continue
				var j: int = index[m]
				bd.encode_u32((4 + n * 2) * 4, j)
				bd.encode_float((5 + n * 2) * 4, p.distance_to(at[j]))
				n += 1
		bd.encode_u32(8, n)
		for k in range(n, MAX_BONDS):
			bd.encode_u32((4 + k * 2) * 4, BOND_NONE)
		_rd.buffer_update(_buf, (O_BD + idx * BD_STRIDE) * 4, bd.size(), bd)
	chunks[id] = {"mat": mat, "count": list.size()}
	return id


# Loose sand on the air cells within radius of centre: a heap that
# flows down and settles.
func spawn_sand_disc(centre: Vector2, radius: float) -> void:
	var cx := int(floor(centre.x / PIXEL_SZ))
	var cy := int(floor(centre.y / PIXEL_SZ))
	var n := int(ceil(radius / PIXEL_SZ)) + 1
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if x < 0 or y < 0 or x >= RENDER_W or y >= RENDER_H:
				continue
			if cells.size() >= RENDER_W * RENDER_H * 4 and cells.decode_u32((y * RENDER_W + x) * 4) != 0:
				continue
			var p := Vector2((x + 0.5) * PIXEL_SZ, (y + 0.5) * PIXEL_SZ)
			if p.distance_to(centre) < radius:
				spawn_particle(p + Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)), MAT_SAND, Vector2(0.0, 20.0))


# A roughly round lump about centre: a disc with a wobbly edge, on the
# air cells only, so it never overlaps the ground.
func spawn_chunk_disc(centre: Vector2, radius: float, mat: int) -> int:
	var list: Array = []
	var cx := int(floor(centre.x / PIXEL_SZ))
	var cy := int(floor(centre.y / PIXEL_SZ))
	var n := int(ceil(radius / PIXEL_SZ)) + 1
	var wobble := _rng.randf() * 100.0
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if x < 0 or y < 0 or x >= RENDER_W or y >= RENDER_H:
				continue
			if cells.size() >= RENDER_W * RENDER_H * 4 and cells.decode_u32((y * RENDER_W + x) * 4) != 0:
				continue
			var p := Vector2((x + 0.5) * PIXEL_SZ, (y + 0.5) * PIXEL_SZ)
			var a := (p - centre).angle()
			var edge := radius * (1.0 + 0.22 * sin(a * 3.0 + wobble) + 0.1 * sin(a * 5.0 - wobble))
			if p.distance_to(centre) < edge:
				list.append(Vector2i(x, y))
	return spawn_chunk(list, mat)


func fill_rect(r: Rect2, mat := MAT_ROCK) -> void:
	var y := floorf(r.position.y / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
	while y < r.end.y:
		var x := floorf(r.position.x / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
		while x < r.end.x:
			spawn_particle(Vector2(x, y), mat)
			x += PIXEL_SZ
		y += PIXEL_SZ


func fill_circle(centre: Vector2, radius: float, mat := MAT_ROCK) -> void:
	var y := floorf((centre.y - radius) / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
	while y < centre.y + radius:
		var x := floorf((centre.x - radius) / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
		while x < centre.x + radius:
			if Vector2(x, y).distance_to(centre) < radius:
				spawn_particle(Vector2(x, y), mat)
			x += PIXEL_SZ
		y += PIXEL_SZ


func _update_params() -> void:
	var p := _params
	p.encode_float(0, SIM_DT)
	p.encode_float(4, GRAVITY)
	p.encode_float(8, WORLD_W)
	p.encode_float(12, WORLD_H)
	p.encode_float(16, float(GW))
	p.encode_float(20, float(GH))
	p.encode_float(24, CELL_SZ)
	p.encode_float(28, SUPPORT_R)
	p.encode_float(32, float(PARTICLE_COUNT))
	p.encode_float(36, -1000.0)   # [9..15] the shooter's drill: parked off world, inactive
	p.encode_float(40, -1000.0)
	p.encode_float(44, 0.0)
	p.encode_float(48, 1.0)
	p.encode_float(52, 20.0)
	p.encode_float(56, 30.0)
	p.encode_float(60, 0.0)
	p.encode_float(64, float(RENDER_W))
	p.encode_float(68, float(RENDER_H))
	p.encode_float(72, PIXEL_SZ)
	p.encode_float(76, 0.0)       # [19] resistance (GPU -> CPU)
	p.encode_float(80, 0.0)       # [20] ram flag
	_tick += 1
	p.encode_float(84, float(_tick % 65536))  # [21] tick, GPU randomness
	for i in range(22, 27):
		p.encode_float(i * 4, 0.0)
	p.encode_float(108, 0.0)      # [27] lighting off: flat material colours
	var exp1_r := 0.0
	var exp1_enc := 0.0
	var exp2_r := 0.0
	var exp2_enc := 0.0
	if _explosions.size() > 0:
		var e1: Dictionary = _explosions.pop_front()
		exp1_r = e1.radius
		exp1_enc = _encode_explosion_pos(e1.pos, e1.implode)
	if _explosions.size() > 0:
		var e2: Dictionary = _explosions.pop_front()
		exp2_r = e2.radius
		exp2_enc = _encode_explosion_pos(e2.pos, e2.implode)
	p.encode_float(112, exp1_r)   # [28]
	p.encode_float(116, exp1_enc) # [29]
	for i in range(30, 37):
		p.encode_float(i * 4, 0.0)
	p.encode_float(144, float(_tick))  # [36] frame counter
	p.encode_float(148, exp2_r)   # [37]
	p.encode_float(152, exp2_enc) # [38]
	p.encode_float(156, 0.0)      # [39] active particle counter
	_rd.buffer_update(_buf, 0, 160, p)
	_rd.buffer_update(_buf, O_CAP * 4, _capsules.size(), _capsules)
	_rd.buffer_update(_buf, (O_M + 9) * 4, 12, _zero12)
	_rd.buffer_update(_buf, (O_P + 34) * 4, 4, _zero4)
	_rd.buffer_update(_buf, O_FB * 4, 12, _zero12)


# floor(y) * 2048 + floor(x), negative for an implosion.
func _encode_explosion_pos(pos: Vector2, implode: bool) -> float:
	var x := floorf(clampf(pos.x, 0.0, WORLD_W - 1.0))
	var y := floorf(clampf(pos.y, 0.0, WORLD_H - 1.0))
	var encoded := y * 2048.0 + x
	return -encoded if implode else encoded


func _dispatch() -> void:
	var pg := ceili(float(PARTICLE_COUNT) / WORKGROUP)
	var gg := ceili(float(GW * GH) / WORKGROUP)
	var rg := ceili(float(RENDER_W * RENDER_H) / WORKGROUP)
	var cl := _rd.compute_list_begin()
	_bind(cl, S.PREDICT, pg)
	_rd.compute_list_add_barrier(cl)
	_bind(cl, S.GRID_CLEAR, gg)
	_rd.compute_list_add_barrier(cl)
	_bind(cl, S.GRID_INSERT, pg)
	_rd.compute_list_add_barrier(cl)
	for _i in SOLVER_ITERS:
		_bind(cl, S.LAMBDA, pg)
		_rd.compute_list_add_barrier(cl)
		_bind(cl, S.DELTA, pg)
		_rd.compute_list_add_barrier(cl)
	_bind(cl, S.FINALIZE, pg)
	_rd.compute_list_add_barrier(cl)
	_bind(cl, S.RENDER_CLEAR, rg)
	_rd.compute_list_add_barrier(cl)
	_bind(cl, S.RENDER_WRITE, pg)
	_rd.compute_list_add_barrier(cl)
	_bind(cl, S.RENDER_WATER, rg)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()


func _bind(cl: int, idx: int, groups: int) -> void:
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines[idx])
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	_rd.compute_list_dispatch(cl, groups, 1, 1)


# The chamber as particles: the bitmap generator decides what each cell
# is (air, rock, water), one particle per cell with a little jitter.
func _create_initial_data(seed_value: int, kinds: PackedByteArray) -> PackedByteArray:
	if kinds.is_empty():
		var gen := CaveMap.new()
		gen.generate(seed_value)
		kinds = gen.solid
		gen.free()

	var data := PackedByteArray()
	data.resize(TOTAL_UINTS * 4)
	_wf(data, O_P + 0, SIM_DT)
	_wf(data, O_P + 1, GRAVITY)
	_wf(data, O_P + 2, WORLD_W)
	_wf(data, O_P + 3, WORLD_H)
	_wf(data, O_P + 4, float(GW))
	_wf(data, O_P + 5, float(GH))
	_wf(data, O_P + 6, CELL_SZ)
	_wf(data, O_P + 7, SUPPORT_R)
	_wf(data, O_P + 8, float(PARTICLE_COUNT))
	_wf(data, O_P + 16, float(RENDER_W))
	_wf(data, O_P + 17, float(RENDER_H))
	_wf(data, O_P + 18, PIXEL_SZ)

	# [rest_density, stiffness, viscosity, cohesion, friction, yield, R, G, B, pad, pad, pad]
	# Sand: pale and warm, so a heap of it reads apart from the ground.
	var sand :=   [3.0, 1.0, 0.02,  0.0, 0.3, 0.0, 0.64, 0.56, 0.38, 0.0, 0.0, 0.0]
	var water :=  [1.8, 1.2, 0.008, 0.0, 0.0, 0.0, 0.15, 0.40, 0.85, 0.0, 0.0, 0.0]
	var clay :=   [3.5, 0.8, 0.15,  0.4, 0.4, 0.2, 0.55, 0.38, 0.25, 0.0, 0.0, 0.0]
	var rock :=   [4.0, 2.0, 0.00,  0.9, 0.8, 8.0, 0.34, 0.29, 0.25, 0.0, 0.0, 0.0]
	# Stone: the 4 px lattice's own density, no yield (its bonds hold
	# the shape), some friction so a lump stops rolling; pale, so a lump
	# stands out from the ground it lies on.
	var wood :=   [3.0, 1.2, 0.02,  0.0, 0.5, 0.0, 0.60, 0.58, 0.54, 0.0, 0.0, 0.0]
	var iron :=   [3.8, 1.5, 0.00,  0.6, 0.5, 2.0, 0.30, 0.55, 0.90, 0.0, 0.0, 0.0]
	# Copper: a yield of 5 or more holds a particle in place as rock is
	# held (pbd_predict.glsl), so a vein stays in its wall.
	var copper := [3.5, 1.3, 0.00,  0.5, 0.4, 8.0, 0.95, 0.50, 0.10, 0.0, 0.0, 0.0]
	var gold :=   [4.5, 1.8, 0.00,  0.7, 0.6, 2.5, 1.00, 0.88, 0.08, 0.0, 0.0, 0.0]
	var mats := [sand, water, clay, rock, wood, iron, copper, gold]
	for mi in mats.size():
		for fi in 12:
			_wf(data, O_M + mi * 12 + fi, mats[mi][fi])

	var idx := 0
	for yi in RENDER_H:
		for xi in RENDER_W:
			var kind := kinds[yi * RENDER_W + xi]
			var b := O_PT + idx * 8
			if kind == CaveMap.CELL_AIR:
				_wf(data, b + 0, -1000.0)
				_wf(data, b + 1, -1000.0)
				_wf(data, b + 4, -1000.0)
				_wf(data, b + 5, -1000.0)
				_wf(data, b + 7, 0.0)
				_dead.append(idx)
			else:
				var x := clampf(xi * PIXEL_SZ + PIXEL_SZ * 0.5 + _rng.randf_range(-0.5, 0.5), 1.0, WORLD_W - 1.0)
				var y := clampf(yi * PIXEL_SZ + PIXEL_SZ * 0.5 + _rng.randf_range(-0.5, 0.5), 1.0, WORLD_H - 1.0)
				var mat := MAT_ROCK
				if kind == CaveMap.CELL_WATER:
					mat = MAT_WATER
				elif kind == CaveMap.CELL_COPPER:
					mat = MAT_COPPER
				_wf(data, b + 0, x)
				_wf(data, b + 1, y)
				_wf(data, b + 4, x)
				_wf(data, b + 5, y)
				_wf(data, b + 7, float(mat) + _rng.randf_range(0.0, 0.99) * 0.1)
			_wf(data, b + 2, 0.0)
			_wf(data, b + 3, 0.0)
			_wf(data, b + 6, 0.0)
			idx += 1
	return data


func _wf(data: PackedByteArray, offset: int, value: float) -> void:
	data.encode_float(offset * 4, value)


func _exit_tree() -> void:
	if _rd:
		if _uniform_set.is_valid():
			_rd.free_rid(_uniform_set)
		for p in _pipelines:
			_rd.free_rid(p)
		for s in _shaders:
			_rd.free_rid(s)
		if _buf.is_valid():
			_rd.free_rid(_buf)
		_rd.free()
		_rd = null
