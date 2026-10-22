# Particle world: the GPU PBD simulation from untitled-idle-shooter, cut
# down to what the gecko needs. Every particle is a 2 px block; one SSBO
# holds parameters, the material table, the spatial hash, the particles,
# the render buffers, and at its tail a cell-class buffer (air, water,
# static solid, lava, loose grain per render pixel) that render_write.glsl
# fills and the CPU reads back every tick. That readback is the gecko's
# whole world: the same grid the bitmap stand-in uses. It is read from
# a marked copy (cell_post.glsl): a crumb, a bit of matter of at most
# crumb_cells cells, carries CT_CRUMB so the senses pass through it and
# the body loosens it; and a 2x2 fold of it (cell_fold.glsl) is read
# back as well while the senses run on the 4 px grid.
#
# Materials, from the shooter's table: sand (loose, flows), water, clay
# (loose, sticky), rock (static), stone (the loose stuff of lumps), hard
# rock (static, slow to chew), copper (static, a vein), bedrock (static,
# no bite opens it); lava (material 10, never sleeps, glows) is hard
# coded in the shaders. A grain of sand or clay at rest sleeps, and wakes
# when the cell under it opens (pbd_predict.glsl), so a bed of sand
# stays put until it is undermined and then pours.
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
const PIXEL_SZ := 2.0
const CELL_SZ := 6.0
const SUPPORT_R := 6.0
const GW := 320
const GH := 180
const MPC := 32
const RENDER_W := 960
const RENDER_H := 540
const SIM_DT := 1.0 / 60.0
const GRAVITY := 900.0
const WORKGROUP := 256
const SOLVER_ITERS := 6

const O_P := 0
const O_M := 40
const O_GC := 136
const O_GP := 57736
const O_PT := 1900936
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
# The light pass (light_seed.glsl, light_spread.glsl): two halves of
# packed RGB8 light per cell (the spread ping-pongs between them, an odd
# number of passes so the result lands in A), the emission the
# particles write (copper, lava), and its parameters.
const O_LA := O_BD + PARTICLE_COUNT * BD_STRIDE  # 4795470, two uints per cell (16 bits a channel)
const O_LB := O_LA + RENDER_W * RENDER_H * 2     # 5054670
const O_EM := O_LB + RENDER_W * RENDER_H * 2     # 5313870, RGB8 per cell
const O_LO := O_EM + RENDER_W * RENDER_H         # 5443470, RGB8 per cell, the overlay's texture
const O_LP := O_LO + RENDER_W * RENDER_H         # 5573070
const LP_SIZE := 128
const O_LN := O_LP + LP_SIZE                     # 22291598, the cell classes with crumbs marked (cell_post.glsl): the senses' readback
const O_C4 := O_LN + RENDER_W * RENDER_H         # 22809998, the same folded 2x2 to the 4 px grid (cell_fold.glsl)
# Skinned chunks (shrooms, vines: critters.gd): a chunk whose particles
# follow a chain the CPU moves. Per particle [bone + 1 (0 for none),
# the next bone's weight, rest x, rest y]; per bone [x, y, cos, sin of
# its pose now, the same at rest, drive, the stretch along it, pad,
# pad]: pbd_predict.glsl puts a driven particle where its bones carry
# its rest place, a blend of two bones, and the solver leaves it there.
# A bone not driven lets its particles go as an ordinary lump. The
# living bonded particles of each bone are counted (render_write.glsl)
# and read back, so the CPU sees a stem bitten through.
const O_SK := O_C4 + (RENDER_W / 2) * (RENDER_H / 2)   # 22939598
const SK_STRIDE := 4
const MAX_BONES := 2048
const BN_STRIDE := 12                                 # x, y, cos, sin, rest x, rest y, rest cos, rest sin, drive, stretch (a released bone split across: the pieces' width), release id, pieces
const O_BN := O_SK + PARTICLE_COUNT * SK_STRIDE       # 25013198
const O_BC := O_BN + MAX_BONES * BN_STRIDE            # 25037774, counts per bone (grid_clear.glsl zeroes them)
# Slimes (critters.gd): a slime is a blob of material 14, a viscous
# liquid that holds together; up to MAX_SLIMES brains, each [x, y,
# reach, pull, drift x, drift y, drift speed, on], draw the slime's
# particles within reach toward the brain and along its drift
# (pbd_predict.glsl); each brain's particles are counted and summed
# (count, x, y in 1/16 px) for the CPU to follow its mass; the slime is
# drawn from its own density (render_water.glsl).
const MAX_SLIMES := 16
const SB_STRIDE := 8
const O_SB := O_BC + MAX_BONES                        # 25039822
const O_SS := O_SB + MAX_SLIMES * SB_STRIDE           # 25039950, [count, sum x, sum y, pad] per brain
const O_SD := O_SS + MAX_SLIMES * 4                   # 25040014, slime density per cell
const TOTAL_UINTS := O_SD + RENDER_W * RENDER_H
const MAT_SLIME := 14
const CT_SLIME := 8                              # Cell class of slime: sticky, the walk wades through it slowly
const FRAC_SKIN := 0.0900                        # Stone (mat 4) at fraction 0.09 + band * 0.0002 is a skinned chunk's colour (render_write.glsl): bands 0 to 7 SKIN_PAL, 8 to 15 the same glowing, 16 to 31 the decor palette (SKIN_DECOR), 32 to 47 the same glowing
const SKIN_BAND := 0.0002
const SKIN_DECOR := 16
const CT_CRUMB := 256                            # Added to a crumb's class in the O_LN copy: a speck the senses read as air and the body loosens
const LIGHT_PASSES := 19                         # Cells the light travels per tick; odd, see above
const MAX_GLOWS := 10                            # Glow sources (the gecko, the slugs, the level's lights) the seed takes: 8 floats each from [16], x y r g b radius x2 y2, under the currents at [96]
const LIGHT_DECAY := 0.8                         # Of last tick's light kept before this tick's spread: a moved glow leaves a short trail
# Passage per cell. Beyond one tick's passes the light is carried on
# from the decayed field, so the fall-off there is the passage times
# the decay's ninth root (0.976): air comes to 0.961 a cell, half-light
# about 17 cells (70 px) past the bright plateau round a source.
const LIGHT_AIR := 0.9925
const LIGHT_WATER := 0.9644
const LIGHT_LOOSE := 0.7746
const LIGHT_SOLID := 0.6708                        # A rock face lights a cell or two deep
const CT_CHUNK := 16                             # Cell class 16 + id: a cell of chunk id

const MAT_SAND := 0
const MAT_WATER := 1
const MAT_CLAY := 2
const MAT_ROCK := 3
const MAT_STONE := 4                             # The shooter's wood slot: loose stone, the stuff of boulders
const MAT_HARD := 5                              # The shooter's iron slot: hard rock, several bites to open
const MAT_COPPER := 6                            # A vein: rock that glows, from the map's copper cells
const MAT_BEDROCK := 7                           # The shooter's gold slot: rock no bite opens
const MAT_LAVA := 10                             # Hard coded in the shaders, as in the shooter
const MAT_SMOKE := 9                             # Ephemeral: rises and fades (the shooter's smoke); dust and bubbles here
const MAT_SHROOM := 12                           # Glowshroom: the shooter's purple ore slot, made static, green and a light (hard coded in the shaders)
const CT_SOLID := 2                              # Cell class of static solid (rock, hard rock, bedrock, copper)
const CT_LOOSE := 4                              # Cell class of a loose grain (sand, clay, stone off a lump)
const CT_SLICK := 5                              # Cell class of moss: rock in its top fraction band, solid but no hold for the feet
const CT_CRUMBLE := 6                            # Cell class of crumbling rock: the band below, gives way under a hold
const CT_THORN := 7                              # Cell class of thorns: the band between, no hold and a touch throws the body off
const FRAC_MOSS := 0.097                         # Rock's fraction for moss (render_write.glsl reads the bands)
const FRAC_CRUMBLE := 0.092
const FRAC_THORN := 0.094                        # Rock's fraction for thorns, between the two
const FRAC_BAND := 0.003                         # A decor cell (mat 12, CaveMap.CELL_DECOR and up) sits at 0.0015 + band * 0.003: the band's low four bits its palette colour, 16 and up a glow (render_write.glsl)
const FRAC_SHROOM := 0.098                       # The table glowshroom (kind 9): mat 12 above the bands, the old green flesh
const FRAC_MAX := 0.89                           # Random fractions stay under 0.089, below the bands
const MODE_WAKE := -5.0                          # Capsule mode: nudges loose grains awake (pbd_delta.glsl)

# Capsule slots: 0 to 3 melt (chew and brush, in turn), the body's two
# pushers (loose grains shoved out of its way), the pull (the tongue's
# drag, the walk's shove), and one-shot events (eat, break).
const SLOT_BODY_A := 4
const SLOT_PULL := 5
const SLOT_EVENT := 6
const SLOT_BODY_B := 7
const CARVE_PAD := (4.0 - PIXEL_SZ) * 0.5     # A melt takes the particles within its radius, cell centres: widened by the half cell lost against 4 px cells, so a bite opens what it did (cave_map.gd says the same)
const MELT_BRUSH := 2.0                          # A melt mode past 1.5 takes bedrock too (pbd_delta.glsl)

const SHADER_FILES := [
	"pbd_predict", "grid_clear", "grid_insert",
	"pbd_lambda", "pbd_delta", "pbd_finalize",
	"render_clear", "render_write", "render_water",
	"light_seed", "light_spread", "light_out",
	"cell_post", "cell_fold",
]
enum S { PREDICT, GRID_CLEAR, GRID_INSERT, LAMBDA, DELTA, FINALIZE, RENDER_CLEAR, RENDER_WRITE, RENDER_WATER, LIGHT_SEED, LIGHT_SPREAD, LIGHT_OUT, CELL_POST, CELL_FOLD }

const BACKDROP := Color(0.045, 0.04, 0.06)

var cells := PackedByteArray()      # O_LN readback: one uint per render pixel, the class with CT_CRUMB added on a crumb
var cells4 := PackedByteArray()     # O_C4 readback while fold_on: the classes folded to the 4 px grid, crumbs as air
var fold_on := false                # Read the folded grid back each tick (the coarse senses, sim_map.gd)
var crumb_cells := 4                # A bit of matter of at most this many cells (of its 5x5) is a crumb: air to the senses, loosened at the body's touch; 0 for none
var ready_to_run := false
var light_on := OS.get_environment("GECKO_LIGHT") == "1"  # The light pass and its overlay: off unless GECKO_LIGHT=1 or the panel turns it on, the whole cave lit (the user's choice, 2026-10-21)
var chunks := {}                    # Chunk id -> {mat, count} as spawned (the GPU owns what is left of each)

var _rd: RenderingDevice
var _buf: RID
var _uniform_set: RID
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _display_img: Image
var _display_tex: ImageTexture
var _sprite: Sprite2D
var _light_img: Image
var _light_tex: ImageTexture
var _light_sprite: Sprite2D
var _light := PackedByteArray()      # O_LP: the light pass's parameters, uploaded every tick
var _push := PackedByteArray()       # The spread's push constant: the pass index
var _params := PackedByteArray()
var _capsules := PackedByteArray()
var _capsule_once: Array[bool] = []  # Slots to switch off after the next dispatch
var _zero12 := PackedByteArray()
var _zero4 := PackedByteArray()
var _zero_bd := PackedByteArray()
var _next_chunk := 1
var _explosions: Array[Dictionary] = []
var _dead: Array[int] = []           # Free particle slots
var _bones := PackedFloat32Array()   # O_BN as the CPU keeps it: the critters' bone poses, uploaded every tick up to _bones_used
var _bones_used := 0                 # Bones handed out since the build (alloc_bones); they are not handed out again until the next build
var bone_counts := PackedByteArray() # O_BC readback: the living bonded particles of each bone, last tick
var bone_counts_i := PackedInt32Array()   # The same as ints, for the critters' checks
var _slimes := PackedFloat32Array()  # O_SB: the slime brains
var _slimes_on := false
var slime_sums := PackedByteArray()  # O_SS readback: per brain the count of its particles and the sums of their places
var t_parts := Vector3i.ZERO         # The last tick's upload, dispatch (the GPU's work and the wait for it) and readback, µs
var _tick := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	assert(O_CT == 8294670, "O_CT must match the literal in render_write.glsl, render_clear.glsl, pbd_finalize.glsl and pbd_predict.glsl")
	assert(O_BD == 8813070, "O_BD must match the literal in pbd_predict.glsl, pbd_delta.glsl and render_write.glsl")
	assert(O_LN == 22291598 and O_C4 == 22809998, "the crumb offsets must match the literals in cell_post.glsl, cell_fold.glsl and pbd_predict.glsl")
	assert(O_SK == 22939598 and O_BN == 25013198 and O_BC == 25037774 and O_SB == 25039822 and O_SS == 25039950 and O_SD == 25040014, "the skin and slime offsets must match the literals in pbd_predict.glsl, pbd_delta.glsl, pbd_finalize.glsl, grid_clear.glsl, render_clear.glsl, render_write.glsl and render_water.glsl")
	assert(O_LA == 19181070 and O_EM == 21254670 and O_LO == 21773070 and O_LP == 22291470, "the light offsets must match the literals in light_seed.glsl, light_spread.glsl, light_out.glsl, render_clear.glsl and render_write.glsl")
	z_index = -1
	_params.resize(40 * 4)
	_light.resize(LP_SIZE * 4)
	_light.encode_float(0, LIGHT_DECAY)
	_light.encode_float(11 * 4, LIGHT_AIR)
	_light.encode_float(12 * 4, LIGHT_WATER)
	_light.encode_float(13 * 4, LIGHT_LOOSE)
	_light.encode_float(14 * 4, LIGHT_SOLID)
	_push.resize(16)
	_capsules.resize(MAX_CAPSULES * 8 * 4)
	_capsule_once.resize(MAX_CAPSULES)
	_capsule_once.fill(false)
	_zero12.resize(12)
	_zero4.resize(4)
	_zero_bd.resize(BD_STRIDE * 4)
	_bones.resize(MAX_BONES * BN_STRIDE)
	_slimes.resize(MAX_SLIMES * SB_STRIDE)
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
	# The light over the world: the light map multiplied over the
	# particles and the backdrop (shaders/light_overlay.gdshader), as
	# blocky as the rock. It sits under the gecko (z 4 to 6), which is
	# drawn unlit, its whole body the same brightness, by the user's
	# choice: a shaded gecko read as a different creature.
	_light_img = Image.create(RENDER_W, RENDER_H, false, Image.FORMAT_RGBA8)
	_light_tex = ImageTexture.create_from_image(_light_img)
	_light_sprite = Sprite2D.new()
	_light_sprite.texture = _light_tex
	_light_sprite.centered = false
	_light_sprite.scale = Vector2(PIXEL_SZ, PIXEL_SZ)
	_light_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_light_sprite.z_as_relative = false
	_light_sprite.z_index = 2
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/light_overlay.gdshader")
	_light_sprite.material = mat
	_light_sprite.visible = light_on
	add_child(_light_sprite)


# The light pass and its overlay on or off (the debug panel).
func set_light(on: bool) -> void:
	light_on = on
	_light_sprite.visible = on


# Daylight: the open cells of rect (world px) are lit with colour every
# tick, and the light spreads from there. An empty rect is no daylight.
func set_daylight(rect: Rect2, color: Color) -> void:
	_light.encode_float(4 * 4, rect.position.x)
	_light.encode_float(5 * 4, rect.position.y)
	_light.encode_float(6 * 4, rect.end.x)
	_light.encode_float(7 * 4, rect.end.y)
	_light.encode_float(8 * 4, color.r)
	_light.encode_float(9 * 4, color.g)
	_light.encode_float(10 * 4, color.b)


# The glows this tick: up to MAX_GLOWS of [position, colour, radius]
# or [position, colour, radius, end]: a point, a strip of light along
# the segment to the end, or with a negative radius a cone from the
# position to the end (light_seed.glsl),
# the gecko's head, the slugs and the level's lights. Set before tick().
func set_glows(glows: Array) -> void:
	var n := mini(glows.size(), MAX_GLOWS)
	_light.encode_float(1 * 4, float(n))
	for i in n:
		var g: Array = glows[i]
		var b := (16 + i * 8) * 4
		var p2: Vector2 = g[3] if g.size() > 3 else g[0]
		_light.encode_float(b, g[0].x)
		_light.encode_float(b + 4, g[0].y)
		_light.encode_float(b + 8, g[1].r)
		_light.encode_float(b + 12, g[1].g)
		_light.encode_float(b + 16, g[1].b)
		_light.encode_float(b + 20, g[2])
		_light.encode_float(b + 24, p2.x)
		_light.encode_float(b + 28, p2.y)


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
	_bones.fill(0.0)
	_bones_used = 0
	bone_counts = PackedByteArray()
	bone_counts_i = PackedInt32Array()
	_slimes.fill(0.0)
	_slimes_on = false
	slime_sums = PackedByteArray()
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
	var t0 := Time.get_ticks_usec()
	_update_params()
	var t1 := Time.get_ticks_usec()
	_dispatch()
	var t2 := Time.get_ticks_usec()
	cells = _rd.buffer_get_data(_buf, O_LN * 4, RENDER_W * RENDER_H * 4)
	if _bones_used > 0:
		bone_counts = _rd.buffer_get_data(_buf, O_BC * 4, _bones_used * 4)
		bone_counts_i = bone_counts.to_int32_array()
	if _slimes_on:
		slime_sums = _rd.buffer_get_data(_buf, O_SS * 4, MAX_SLIMES * 16)
	t_parts = Vector3i(t1 - t0, t2 - t1, Time.get_ticks_usec() - t2)
	if fold_on:
		read_fold()
	for i in MAX_CAPSULES:
		if _capsule_once[i]:
			_capsule_once[i] = false
			set_capsule(i, Vector2.ZERO, Vector2.DOWN, 1.0, 1.0, false)


# The folded grid (cell_fold.glsl) for the coarse senses: each tick
# while fold_on, and once when the senses switch to it.
func read_fold() -> void:
	if not ready_to_run:
		return
	cells4 = _rd.buffer_get_data(_buf, O_C4 * 4, (RENDER_W / 2) * (RENDER_H / 2) * 4)


# Once per frame: the rendered pixels into the display texture.
func read_render() -> void:
	if not ready_to_run:
		return
	var bytes := _rd.buffer_get_data(_buf, O_RN * 4, RENDER_W * RENDER_H * 4)
	_display_img.set_data(RENDER_W, RENDER_H, false, Image.FORMAT_RGBA8, bytes)
	_display_tex.update(_display_img)
	if light_on:
		var lb := _rd.buffer_get_data(_buf, O_LO * 4, RENDER_W * RENDER_H * 4)
		_light_img.set_data(RENDER_W, RENDER_H, false, Image.FORMAT_RGBA8, lb)
		_light_tex.update(_light_img)


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


# A bite: deletes the ground particles in the circle on the next tick,
# each with the chance its material gives (the table's give column:
# all of rock, a part of hard rock, none of bedrock). The brush (force)
# takes everything.
func melt_circle(pos: Vector2, radius: float, slot: int, force := false) -> void:
	set_capsule(slot, pos, Vector2.RIGHT, radius + CARVE_PAD, 0.0, true, MELT_BRUSH if force else 1.0)
	_capsule_once[slot] = true


# The gecko's body as two capsules (head to mid-body, mid-body to the
# tail's root) that shove loose grains out of their way every tick, so
# sand poured on the gecko piles on its back instead of passing through
# it, and a body burrowing through a heap pushes the grains aside. The
# ground and lumps are untouched (pbd_delta.glsl, mode -1).
func set_body_capsules(a0: Vector2, a1: Vector2, ra: float, b0: Vector2, b1: Vector2, rb: float) -> void:
	_set_segment(SLOT_BODY_A, a0, a1, ra)
	_set_segment(SLOT_BODY_B, b0, b1, rb)


func clear_body_capsules() -> void:
	set_capsule(SLOT_BODY_A, Vector2.ZERO, Vector2.DOWN, 1.0, 1.0, false)
	set_capsule(SLOT_BODY_B, Vector2.ZERO, Vector2.DOWN, 1.0, 1.0, false)


func _set_segment(slot: int, a: Vector2, b: Vector2, radius: float) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	var half := d.length() * 0.5
	var dir := d / (half * 2.0) if half > 0.001 else Vector2.RIGHT
	set_capsule(slot, mid, dir, radius, half, true, -1.0)


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
func spawn_particle(pos: Vector2, mat: int, vel := Vector2.ZERO, life := -1.0) -> void:
	if _dead.is_empty() or not ready_to_run:
		return
	var idx: int = _dead.pop_back()
	# The fraction is the material's variation, or for fire and smoke
	# the life left (pbd_finalize.glsl: smoke loses about 0.00008 a
	# tick, fire 0.00055), random unless given.
	var encoded := float(mat) + (life if life >= 0.0 else _rng.randf_range(0.0, FRAC_MAX) * 0.1)
	var p := PackedFloat32Array([pos.x, pos.y, vel.x, vel.y, pos.x, pos.y, 0.0, encoded])
	_rd.buffer_update(_buf, (O_PT + idx * 8) * 4, 32, p.to_byte_array())
	# A slot that once held a chunk's particle keeps its bonds: cleared.
	_rd.buffer_update(_buf, (O_BD + idx * BD_STRIDE) * 4, _zero_bd.size(), _zero_bd)


# A lump of loose material: one particle per cell (Vector2i render
# cells), each bonded to its lattice neighbours, the eight around it, at
# their rest distance. The lump holds its shape, falls, can be pushed or
# dragged as one, and comes apart where its bonds are broken. Returns
# the chunk id, or 0 when there are no cells or not enough free slots.
func spawn_chunk(list: Array, mat: int, mats := {}, frac := -1.0, skin := {}, fracs := {}) -> int:
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
		# mats overrides the material per cell (a vine's rock anchor);
		# frac, if given, is the fraction for the rest (a look: a vine's
		# clay sits in the top band, render_write.glsl).
		# skin gives a cell its bones, [bone, weight of the next], and
		# its particle follows them (skinned chunks, critters.gd); fracs
		# a fraction of its own (a skinned chunk's colours).
		var cm: int = mats.get(c, mat)
		var f: float = _rng.randf_range(0.0, FRAC_MAX) * 0.1 if (frac < 0.0 or mats.has(c)) else frac
		if fracs.has(c):
			f = fracs[c]
		if skin.has(c):
			var sk := PackedFloat32Array([0.0, skin[c][1], p.x, p.y]).to_byte_array()
			sk.encode_u32(0, int(skin[c][0]) + 1)
			_rd.buffer_update(_buf, (O_SK + idx * SK_STRIDE) * 4, sk.size(), sk)
		var encoded := float(cm) + f
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


# Bones for a skinned chunk: n in a row, the index of the first, -1
# when the table is full. They stay the caller's until the next build.
func alloc_bones(n: int) -> int:
	if _bones_used + n > MAX_BONES:
		return -1
	var base := _bones_used
	_bones_used += n
	return base


# A bone's pose: where its joint is, the way it points (radians), and
# the stretch of its particles along it (1 for none: a stem squashed
# under a load is less). Driven, its particles are carried there on the
# next tick.
func set_bone(i: int, pos: Vector2, angle: float, stretch := 1.0) -> void:
	var b := i * BN_STRIDE
	_bones[b] = pos.x
	_bones[b + 1] = pos.y
	_bones[b + 2] = cos(angle)
	_bones[b + 3] = sin(angle)
	_bones[b + 9] = stretch


# The pose the particles were laid out in: their rest places are read
# in this frame.
func set_bone_rest(i: int, pos: Vector2, angle: float) -> void:
	var b := i * BN_STRIDE
	_bones[b + 4] = pos.x
	_bones[b + 5] = pos.y
	_bones[b + 6] = cos(angle)
	_bones[b + 7] = sin(angle)
	_bones[b + 9] = 1.0


# A bone let go of is an ordinary lump from then on: its particles fall,
# roll and break as any chunk's.
func set_bone_drive(i: int, on: bool) -> void:
	_bones[i * BN_STRIDE + 8] = 1.0 if on else 0.0


# Bones from to to (not included) let go: their particles become a lump
# of their own, a new chunk id (bonds to the rest's particles break,
# pbd_delta.glsl), that falls and can be shoved. Returns the id. With
# split, each bone is a lump of its own instead, and the last one is
# cut across its axis into split pieces split_w px wide (a shroom's
# stem in its links, the cap in pieces): the pieces fall apart and are
# shoved one by one; returns the first id. Chunk ids past 239 read as
# air (the class byte), so a split takes few.
func release_bones(from: int, to: int, split := 0, split_w := 0.0) -> int:
	var first := _next_chunk
	for i in range(from, to):
		var n := split if (split > 1 and i == to - 1) else 1
		if i == from or split > 0:
			for k in n:
				chunks[_next_chunk + k] = {"mat": MAT_STONE, "count": 0}
			_bones[i * BN_STRIDE + 10] = float(_next_chunk)
			_next_chunk += n
		else:
			_bones[i * BN_STRIDE + 10] = float(first)
		_bones[i * BN_STRIDE + 8] = 0.0
		_bones[i * BN_STRIDE + 11] = float(n)
		if n > 1:
			_bones[i * BN_STRIDE + 9] = split_w
	return first


# The bonded particles of bone i still alive last tick.
func bone_count(i: int) -> int:
	if i < 0 or i >= bone_counts_i.size():
		return -1
	return bone_counts_i[i]


# A slime's brain i: its particles within reach are drawn toward pos
# (pull per second) and drift along dir at speed. Off, they are an
# inert puddle.
func set_slime(i: int, pos: Vector2, reach: float, pull: float, dir: Vector2, speed: float, on: bool) -> void:
	var b := i * SB_STRIDE
	_slimes[b] = pos.x
	_slimes[b + 1] = pos.y
	_slimes[b + 2] = reach
	_slimes[b + 3] = pull
	_slimes[b + 4] = dir.x
	_slimes[b + 5] = dir.y
	_slimes[b + 6] = speed
	_slimes[b + 7] = 1.0 if on else 0.0
	if on:
		_slimes_on = true


# Brain i's particles last tick: [count, their centre].
func slime_mass(i: int) -> Array:
	if (i + 1) * 16 > slime_sums.size():
		return [0, Vector2.ZERO]
	var n := slime_sums.decode_u32(i * 16)
	if n == 0:
		return [0, Vector2.ZERO]
	var sx := float(slime_sums.decode_u32(i * 16 + 4)) / 16.0
	var sy := float(slime_sums.decode_u32(i * 16 + 8)) / 16.0
	return [n, Vector2(sx / n, sy / n)]


# A blob of slime on the air cells within radius of centre.
func spawn_slime(centre: Vector2, radius: float) -> int:
	var n := 0
	var cx := int(floor(centre.x / PIXEL_SZ))
	var cy := int(floor(centre.y / PIXEL_SZ))
	var k := int(ceil(radius / PIXEL_SZ)) + 1
	for y in range(cy - k, cy + k + 1):
		for x in range(cx - k, cx + k + 1):
			if x < 0 or y < 0 or x >= RENDER_W or y >= RENDER_H:
				continue
			if cells.size() >= RENDER_W * RENDER_H * 4 and cells.decode_u32((y * RENDER_W + x) * 4) != 0:
				continue
			var p := Vector2((x + 0.5) * PIXEL_SZ, (y + 0.5) * PIXEL_SZ)
			if p.distance_to(centre) < radius:
				spawn_particle(p + Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)), MAT_SLIME)
				n += 1
	return n


# A puff: n wisps of smoke (material 9, rising, fading) about pos, each
# with a little of the velocity given plus a spread, living life
# (about 0.00008 a tick: 0.003 is some 40 ticks). Bite dust, bubbles.
func spawn_puff(pos: Vector2, n: int, vel: Vector2, spread: float, life: float) -> void:
	for i in n:
		var p := pos + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
		var v := vel + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))
		spawn_particle(p, MAT_SMOKE, v, life * _rng.randf_range(0.7, 1.3))


# One drop of water at pos, falling.
func spawn_drop(pos: Vector2) -> void:
	spawn_particle(pos, MAT_WATER, Vector2(0.0, 30.0))


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


# Every cell the rect touches, as cave_map.gd _set_rect takes them, so
# a cone drawn on both (the editor's stamps) is the same cells.
func fill_rect(r: Rect2, mat := MAT_ROCK, frac := -1.0) -> void:
	var y := floorf(r.position.y / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
	while y - PIXEL_SZ * 0.5 < r.end.y:
		var x := floorf(r.position.x / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
		while x - PIXEL_SZ * 0.5 < r.end.x:
			spawn_particle(Vector2(x, y), mat, Vector2.ZERO, frac)
			x += PIXEL_SZ
		y += PIXEL_SZ


func fill_circle(centre: Vector2, radius: float, mat := MAT_ROCK, frac := -1.0) -> void:
	var y := floorf((centre.y - radius) / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
	while y < centre.y + radius:
		var x := floorf((centre.x - radius) / PIXEL_SZ) * PIXEL_SZ + PIXEL_SZ * 0.5
		while x < centre.x + radius:
			if Vector2(x, y).distance_to(centre) < radius:
				spawn_particle(Vector2(x, y), mat, Vector2.ZERO, frac)
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
	p.encode_float(88, 0.0)       # [22] melted this tick (a GPU counter)
	p.encode_float(92, float(crumb_cells))  # [23] the crumb threshold (cell_post.glsl, pbd_predict.glsl)
	for i in range(24, 27):
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
	_rd.buffer_update(_buf, O_LP * 4, _light.size(), _light)
	if _bones_used > 0:
		_rd.buffer_update(_buf, O_BN * 4, _bones_used * BN_STRIDE * 4, _bones.slice(0, _bones_used * BN_STRIDE).to_byte_array())
	if _slimes_on:
		_rd.buffer_update(_buf, O_SB * 4, _slimes.size() * 4, _slimes.to_byte_array())
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
	_bind(cl, S.CELL_POST, rg)
	_rd.compute_list_add_barrier(cl)
	_bind(cl, S.CELL_FOLD, ceili(float((RENDER_W / 2) * (RENDER_H / 2)) / WORKGROUP))
	_rd.compute_list_add_barrier(cl)
	if light_on:
		_bind(cl, S.LIGHT_SEED, rg)
		_rd.compute_list_add_barrier(cl)
		for i in LIGHT_PASSES:
			_push.encode_u32(0, i)
			_bind(cl, S.LIGHT_SPREAD, rg, _push)
			_rd.compute_list_add_barrier(cl)
		# No barrier after this one: a barrier re-applies the last push
		# constant to the pipeline it re-binds, and this pass has none
		# (a validation error a tick); the water pass does not read the
		# light, and the readback waits for the sync.
		_bind(cl, S.LIGHT_OUT, rg)
	_bind(cl, S.RENDER_WATER, rg)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()


func _bind(cl: int, idx: int, groups: int, push := PackedByteArray()) -> void:
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines[idx])
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	if not push.is_empty():
		_rd.compute_list_set_push_constant(cl, push, push.size())
	_rd.compute_list_dispatch(cl, groups, 1, 1)


# The chamber as particles: the bitmap generator decides what each cell
# is (air, rock, water), one particle per cell with a little jitter.
# The last build's seed, cells, data and each row's free slots: the next
# build with the seed copies the data and writes again only the rows
# whose cells changed (the editor makes the world again after each
# move). A cell's particle depends on its kind, its index and the seed
# alone (_cell_rand), so that is the data a whole build would make.
var _built := {}


func _create_initial_data(seed_value: int, kinds: PackedByteArray) -> PackedByteArray:
	if kinds.is_empty():
		var gen := CaveMap.new()
		gen.generate(seed_value)
		kinds = gen.solid
		gen.free()

	if not _built.is_empty() and int(_built.seed) == seed_value and (_built.kinds as PackedByteArray).size() == kinds.size():
		var data: PackedByteArray = (_built.data as PackedByteArray).duplicate()
		_write_rows(data, seed_value, kinds, _built.kinds, _built.rows)
		_built = {"seed": seed_value, "kinds": kinds.duplicate(), "data": data.duplicate(), "rows": _built.rows}
		return data
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

	# [rest_density, stiffness, viscosity, cohesion, friction, yield, R, G, B, give, pad, pad]
	# A yield of 5 or more holds a particle in place as rock is held
	# (pbd_predict.glsl): the static materials. Give is the chance a
	# bite takes a particle (pbd_delta.glsl): 1 for most, less for hard
	# rock, 0 for bedrock.
	# Sand: pale and warm, so a heap of it reads apart from the ground.
	var sand :=    [3.0, 1.0, 0.02,  0.0, 0.3, 0.0, 0.64, 0.56, 0.38, 1.0, 0.0, 0.0]
	var water :=   [1.8, 1.2, 0.008, 0.0, 0.0, 0.0, 0.15, 0.40, 0.85, 1.0, 0.0, 0.0]
	var clay :=    [3.5, 0.8, 0.15,  0.4, 0.4, 0.2, 0.55, 0.38, 0.25, 1.0, 0.0, 0.0]
	var rock :=    [4.0, 2.0, 0.00,  0.9, 0.8, 8.0, 0.34, 0.29, 0.25, 1.0, 0.0, 0.0]
	# Stone: the lattice's own density, no yield (its bonds hold
	# the shape), some friction so a lump stops rolling; pale, so a lump
	# stands out from the ground it lies on.
	var stone :=   [3.0, 1.2, 0.02,  0.0, 0.5, 0.0, 0.60, 0.58, 0.54, 1.0, 0.0, 0.0]
	# Hard rock: rock in all but colour (cooler, darker) and give, so a
	# hole takes several bites.
	var hard :=    [4.0, 2.0, 0.00,  0.9, 0.8, 8.0, 0.27, 0.27, 0.31, 0.4, 0.0, 0.0]
	# Copper: static, so a vein stays in its wall.
	var copper :=  [3.5, 1.3, 0.00,  0.5, 0.4, 8.0, 0.95, 0.50, 0.10, 1.0, 0.0, 0.0]
	# Bedrock: no bite opens it; the dark slab under everything.
	var bedrock := [4.0, 2.0, 0.00,  0.9, 0.8, 8.0, 0.19, 0.18, 0.23, 0.0, 0.0, 0.0]
	var mats := [sand, water, clay, rock, stone, hard, copper, bedrock]
	for mi in mats.size():
		for fi in 12:
			_wf(data, O_M + mi * 12 + fi, mats[mi][fi])

	var rows: Array = []
	rows.resize(RENDER_H)
	_write_rows(data, seed_value, kinds, PackedByteArray(), rows)
	_built = {"seed": seed_value, "kinds": kinds.duplicate(), "data": data.duplicate(), "rows": rows}
	return data


# The particles of the rows whose cells differ from old (every row when
# old is empty) written into data, a cell's particle at its own index;
# rows[y] keeps each row's free slots, and _dead is made from them. The
# cell classes start as the map says (the first predict pass reads them
# before any render pass has written them), so a bed of sand does not
# see air under it and wake on the first tick.
func _write_rows(data: PackedByteArray, seed_value: int, kinds: PackedByteArray, old: PackedByteArray, rows: Array) -> void:
	for yi in RENDER_H:
		var a := yi * RENDER_W
		if not old.is_empty() and kinds.slice(a, a + RENDER_W) == old.slice(a, a + RENDER_W):
			continue
		var free := PackedInt32Array()
		for xi in RENDER_W:
			var idx := a + xi
			var kind := kinds[idx]
			var b := O_PT + idx * 8
			if kind == CaveMap.CELL_AIR or kind == CaveMap.CELL_GAS:
				data.encode_u32((O_CT + idx) * 4, 0)
				_wf(data, b + 0, -1000.0)
				_wf(data, b + 1, -1000.0)
				_wf(data, b + 4, -1000.0)
				_wf(data, b + 5, -1000.0)
				_wf(data, b + 7, 0.0)
				free.append(idx)
			else:
				# Static matter sits on its cell's centre, as the editor's
				# fills put it (fill_circle), so a brush's melt, which
				# takes particles by position, takes the cells the
				# authoring map erases; what moves starts a little off it.
				var mat := material_of(kind)
				var still := mat == MAT_ROCK or mat == MAT_HARD or mat == MAT_COPPER or mat == MAT_BEDROCK or mat == MAT_SHROOM
				var jx := 0.0 if still else _cell_rand(seed_value, idx, 1) - 0.5
				var jy := 0.0 if still else _cell_rand(seed_value, idx, 2) - 0.5
				var x := clampf(xi * PIXEL_SZ + PIXEL_SZ * 0.5 + jx, 1.0, WORLD_W - 1.0)
				var y := clampf(yi * PIXEL_SZ + PIXEL_SZ * 0.5 + jy, 1.0, WORLD_H - 1.0)
				var cls := CT_SOLID
				if mat == MAT_WATER:
					cls = 1
				elif mat == MAT_LAVA:
					cls = 3
				elif mat == MAT_SAND or mat == MAT_CLAY:
					cls = CT_LOOSE
				elif kind == CaveMap.CELL_MOSS:
					cls = CT_SLICK
				elif kind == CaveMap.CELL_CRUMBLE:
					cls = CT_CRUMBLE
				data.encode_u32((O_CT + yi * RENDER_W + xi) * 4, cls)
				_wf(data, b + 0, x)
				_wf(data, b + 1, y)
				_wf(data, b + 4, x)
				_wf(data, b + 5, y)
				var fr := frac_of(kind)
				_wf(data, b + 7, float(mat) + (fr if fr >= 0.0 else _cell_rand(seed_value, idx, 3) * FRAC_MAX * 0.1))
			_wf(data, b + 2, 0.0)
			_wf(data, b + 3, 0.0)
			_wf(data, b + 6, 0.0)
		rows[yi] = free
	_dead.clear()
	for r in rows:
		_dead.append_array(Array(r))


# A number in 0..1 for a cell's particle: its index, the seed and which
# draw, hashed, so a build gives each cell the same whatever the rest.
static func _cell_rand(seed_value: int, idx: int, k: int) -> float:
	var h := (idx * 374761393 + seed_value * 668265263 + k * 1442695041) & 0xffffffff
	h = ((h ^ (h >> 15)) * 2246822519) & 0xffffffff
	h = ((h ^ (h >> 13)) * 3266489917) & 0xffffffff
	h ^= h >> 16
	return float(h & 0xffffff) / 16777216.0


# The fraction a cell of the map's kind is built with, or -1 for random:
# moss and crumbling rock are rock in a band of their own, a decor cell
# mat 12 in the band of its colour, the table glowshroom above them.
static func frac_of(kind: int) -> float:
	match kind:
		CaveMap.CELL_MOSS:
			return FRAC_MOSS
		CaveMap.CELL_CRUMBLE:
			return FRAC_CRUMBLE
		CaveMap.CELL_SHROOM:
			return FRAC_SHROOM
		CaveMap.CELL_THORN:
			return FRAC_THORN
		_:
			return FRAC_BAND * (float(kind - CaveMap.CELL_DECOR) + 0.5) if kind >= CaveMap.CELL_DECOR else -1.0


# Two currents at most (pbd_predict.glsl): [rect, dir, speed] each.
func set_currents(list: Array) -> void:
	for i in 2:
		var b := (96 + i * 8) * 4
		if i < list.size():
			var r: Rect2 = list[i][0]
			var d: Vector2 = list[i][1]
			_light.encode_float(b, r.position.x)
			_light.encode_float(b + 4, r.position.y)
			_light.encode_float(b + 8, r.end.x)
			_light.encode_float(b + 12, r.end.y)
			_light.encode_float(b + 16, d.x)
			_light.encode_float(b + 20, d.y)
			_light.encode_float(b + 24, float(list[i][2]))
			_light.encode_float(b + 28, 1.0)
		else:
			_light.encode_float(b + 28, 0.0)


# Wakes the loose grains within radius of pos on the next tick (a foot
# on a steep heap), when the event slot is free this tick.
func wake_circle(pos: Vector2, radius: float) -> void:
	if _capsule_once[SLOT_EVENT]:
		return
	set_capsule(SLOT_EVENT, pos, Vector2.RIGHT, radius, 0.0, true, MODE_WAKE)
	_capsule_once[SLOT_EVENT] = true


# The material a cell of the map's kind is built from.
static func material_of(kind: int) -> int:
	match kind:
		CaveMap.CELL_WATER:
			return MAT_WATER
		CaveMap.CELL_COPPER:
			return MAT_COPPER
		CaveMap.CELL_SAND:
			return MAT_SAND
		CaveMap.CELL_CLAY:
			return MAT_CLAY
		CaveMap.CELL_LAVA:
			return MAT_LAVA
		CaveMap.CELL_HARD:
			return MAT_HARD
		CaveMap.CELL_BEDROCK:
			return MAT_BEDROCK
		CaveMap.CELL_SHROOM:
			return MAT_SHROOM
		CaveMap.CELL_MOSS, CaveMap.CELL_CRUMBLE:
			return MAT_ROCK
		_:
			return MAT_SHROOM if kind >= CaveMap.CELL_DECOR else MAT_ROCK


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
