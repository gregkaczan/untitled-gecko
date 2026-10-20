# Scene driver for the gecko game: the first cave (levels/clutch.json,
# the scene named LEVEL, built in the particle sim, or in the bitmap
# stand-in with GECKO_WORLD=bitmap) with its loose lumps and its exit,
# which pulls the camera back over the whole cave when the gecko gets
# there; one gecko; a
# mouse brush for carving (Ctrl+right erases, middle fills, wheel sizes),
# R to start the cave again (a fresh chamber when in a generated one),
# F1 for debug mode (the gecko's overlay and a
# panel down the right: scenes, seed, brush, clock, pixel grid), 1 and 2
# for the gecko's pixel grid (4 px like the rock, or 2 px), Tab for the next test scene
# from tests/scenes.json and Shift+Tab back to the first cave (the
# keys drive the gecko in a scene loaded this way); the panel's New cave
# builds a generated chamber from its seed. GECKO_DUMP_MAP=file.png
# writes the bitmap world's cells as a PNG and quits. The mouse buttons are
# the gecko's: a left press shoots the tongue, which strikes what it
# hits on a tap, grapples on a hold, and sticks and drags it in when the
# right button is held too; right alone chews toward the cursor, and
# with no key held the gecko
# tunnels after the bite, a bite every CHEW_PERIOD. B, C and N drop a
# boulder, a clump of clay or a heap of sand at the cursor, half the
# brush's size, and N held pours sand there. The generated cave gets a
# few lumps and heaps of its own (_scatter_chunks).
# GECKO_DEMO=1 in the environment replaces the keyboard with a scripted
# walk so movie-mode frames show the gecko moving without anyone at the keys.
# GECKO_SCENE=name[:script] runs a test scene from tests/scenes.json the
# same way and quits when the script ends; GECKO_SEED fixes the random
# bites and steps so a run repeats exactly.
extends Node2D

const CAMERA_ZOOM := 2.0
const CAMERA_EASE := 16.0      # How fast the camera closes on the gecko (per second), once it has fallen behind
const CAM_LOCK_SPEED := 220.0  # Up to this speed (px/s) the camera scrolls exactly with the drawn body, so an ordinary walk or climb keeps the body on the same screen pixels
const CAM_GRID := 1.0 / CAMERA_ZOOM  # The camera sits on whole screen pixels: half a world pixel at this zoom
const GLOW_COLOR := Color(1.0, 0.82, 0.58)   # The gecko's own light, warm and small (the sim's light pass)
const GLOW_R := 14.0                         # Px round the head seeded at full glow; the spread carries it on
const DAYLIGHT := Color(0.85, 0.92, 1.0)     # The light at the exit's crack
const VINE_HOLD := 1.2                       # Seconds the gecko may hang on a vine before its anchor gives
const CaveMap = preload("res://cave_map.gd")
const SimMap = preload("res://sim_map.gd")
const Sim = preload("res://sim.gd")
const SoundBank = preload("res://sound.gd")
const Ambience = preload("res://ambience.gd")
const Backdrop = preload("res://backdrop.gd")
const Slug = preload("res://slug.gd")
const Gecko = preload("res://gecko.gd")
const BlobLayer = preload("res://blob_layer.gd")
const SceneBuilder = preload("res://tests/scene_builder.gd")
const DebugPanel = preload("res://debug_panel.gd")
const SCENE_SETTLE := 0.5      # Seconds a test scene runs on after its script
const LEVEL := "clutch"        # The first cave: the scene the game opens on and Shift+Tab returns to
const WIN_ZOOM := 0.85         # The camera's zoom once the gecko is out, the whole cave in view
const WIN_PULL := 0.6          # How fast it pulls back (per second)
const CAM_LIMIT := 1000000     # No camera limit, while the pull-back shows the rock round the cave
const LAB_FLOOR := 800.0       # The tongue demos' flat room: its floor line
const LAB_CEIL := 680.0        # and its ceiling, within the tongue's reach of the floor

# Demo steps: seconds, input vector, jump on the first frame, chew held
# (the right button), then optionally the left button held and the
# cursor offset from the body. GECKO_DEMO=climb walks into the boulder
# and over it, tunnel chews through it and walks the tunnel both ways,
# swim drops into the pool, tongue grapples the ceiling on a held left
# button, then strikes the floor from it with taps, pull drags a stone
# in with both buttons and swallows it, then
# drags a boulder to the mouth and walks it along, strike dents the
# floor and breaks the boulder, dig chews after the cursor with no key
# held: down-right, up-right, straight down, back left.
const DEMOS := {
	"pull": [
		[0.6, Vector2.ZERO, false, false],
		[2.4, Vector2.ZERO, false, true, true, Vector2(90, 9)],
		[0.6, Vector2.ZERO, false, false],
		[4.0, Vector2.ZERO, false, true, true, Vector2(190, 1)],
		[0.6, Vector2.ZERO, false, false],
		[3.5, Vector2.RIGHT, false, false],
		[2.0, Vector2.LEFT, false, false],
	],
	"strike": [
		[0.6, Vector2.ZERO, false, false],
		[0.05, Vector2.ZERO, false, false, true, Vector2(70, 30)],
		[1.2, Vector2.ZERO, false, false, false, Vector2(70, 30)],
		[0.05, Vector2.ZERO, false, false, true, Vector2(150, 1)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(150, 1)],
		[0.05, Vector2.ZERO, false, false, true, Vector2(150, 1)],
		[2.5, Vector2.ZERO, false, false, false, Vector2(150, 1)],
	],
	"dig": [
		[0.5, Vector2.ZERO, false, false],
		[2.5, Vector2.ZERO, false, true, false, Vector2(120, 120)],
		[2.5, Vector2.ZERO, false, true, false, Vector2(140, -60)],
		[2.0, Vector2.ZERO, false, true, false, Vector2(0, 140)],
		[2.5, Vector2.ZERO, false, true, false, Vector2(-140, 0)],
	],
	"swim": [
		[0.3, Vector2.ZERO, false, false],
		[2.6, Vector2.LEFT, false, false],
		[0.6, Vector2.LEFT, true, false],
		[1.5, Vector2.DOWN, false, false],
		[1.5, Vector2.LEFT, false, false],
		[2.0, Vector2.UP, false, false],
		[1.5, Vector2.RIGHT, false, false],
		[2.5, Vector2.UP, false, false],
	],
	"gap": [
		[3.5, Vector2.RIGHT, false, false],
		[3.5, Vector2.LEFT, false, false],
	],
	"traverse": [
		[9.0, Vector2.RIGHT, false, false],
		[9.0, Vector2.LEFT, false, false],
	],
	"notch": [
		[4.5, Vector2.RIGHT, false, false],
		[1.5, Vector2.UP, false, false],
		[1.5, Vector2.RIGHT, false, false],
		[1.5, Vector2(1, -1), false, false],
	],
	"crevice": [
		[1.2, Vector2.RIGHT, false, false],
		[1.5, Vector2(1, 1), false, false],
		[1.0, Vector2.DOWN, false, false],
		[1.0, Vector2.LEFT, false, false],
		[2.0, Vector2.UP, false, false],
		[1.5, Vector2(-1, -1), false, false],
	],
	"tongue": [
		[1.0, Vector2.ZERO, false, false, false, Vector2(60, -110)],
		[2.5, Vector2.ZERO, false, false, true, Vector2(60, -110)],
		[1.0, Vector2.ZERO, false, false, false, Vector2(40, 100)],
		[0.08, Vector2.ZERO, false, false, true, Vector2(40, 100)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(40, 100)],
		[0.08, Vector2.ZERO, false, false, true, Vector2(-60, 100)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(-60, 100)],
	],
	"climb": [
		[1.3, Vector2.RIGHT, false, false],
		[3.0, Vector2.UP, false, false],
		[1.5, Vector2(1, -1), false, false],
		[2.5, Vector2.LEFT, false, false],
		[1.0, Vector2.ZERO, false, false],
		[1.5, Vector2.ZERO, true, false],
		[2.0, Vector2.LEFT, false, false],
		[1.0, Vector2.RIGHT, true, false],
		[2.0, Vector2.RIGHT, false, false],
	],
	"tunnel": [
		[0.3, Vector2.ZERO, false, false],
		[3.6, Vector2.RIGHT, false, true],
		[0.5, Vector2.ZERO, false, false],
		[3.0, Vector2.LEFT, false, false],
		[0.5, Vector2.ZERO, false, false],
		[3.0, Vector2.RIGHT, false, false],
		[2.5, Vector2.LEFT, false, false],
	],
}

var map: CaveMap
var sim: Sim
var gecko: Gecko
var blobs: BlobLayer
var brush_r := 24.0
var seed_value := 7
var _label: Label
var _camera: Camera2D
var _cam := Vector2.ZERO       # The camera's eased position before pixel snapping
var _cam_target := Vector2.ZERO  # The drawn body's base the camera last followed, for its move this tick
var _cam_seat := Vector2.ZERO  # The base's place on the screen's pixels: where the blob layer's grid is anchored
var _seat_off := Vector2.ZERO  # That place as an offset from the camera, kept until the lag has left it by a screen pixel
var _demo: Array = []
var _hint_t := 0.0
var _trace := OS.get_environment("GECKO_TRACE") != ""
var _demo_name := OS.get_environment("GECKO_DEMO")
var _demo_step := -1
var _demo_t := 0.0
var _scene: Dictionary = {}    # The test scene being run, empty outside the suite
var _scene_bases: Dictionary = {}
var _scene_done := -1.0        # Seconds since the scene script ended, -1 while it runs
var _scene_all: Dictionary = {}  # tests/scenes.json, loaded on the first Tab
var _scene_i := -1             # Index of the scene Tab loaded, -1 in the generated cave
var _hint := ""                # Label text while the hint timer runs; empty for the controls hint
var _panel: DebugPanel
var _debug := false            # F1: the panel and the gecko's overlay
var _step_ticks := 0           # Physics ticks left to run before pausing again (the panel's step)
var _exit := Rect2()           # The level's exit, empty in a scene without one
var _sound: Node2D              # sound.gd: the one-shots on the gecko's events, the drone and the hum
var _ambience: Node2D           # ambience.gd: drips, bite dust, bubbles
var _vines := {}                # Chunk id -> {top, load}: the vines hanging in the level and how long the gecko has hung on each
var _backdrop: Node2D           # backdrop.gd: the far wall and the near dripstone, particle world only
var _slugs: Array = []          # slug.gd: the glow slugs in the level
var _won := false              # The gecko reached the exit: the camera pulls back


func _ready() -> void:
	InputSetup.ensure_actions()
	var seed_env := OS.get_environment("GECKO_SEED")
	if seed_env != "":
		seed(int(seed_env))
	var scene_spec := OS.get_environment("GECKO_SCENE")
	var picked: Dictionary = {}
	if scene_spec != "":
		picked = SceneBuilder.pick(scene_spec)
		if picked.is_empty():
			get_tree().quit(2)
			return
		_scene = picked.scene
		_scene_bases = picked.bases
	# The particle sim is the world unless GECKO_WORLD=bitmap asks for the
	# static stand-in (faster to start, and what the demo strips were tuned on).
	if OS.get_environment("GECKO_WORLD") == "bitmap":
		map = CaveMap.new()
	else:
		sim = Sim.new()
		add_child(sim)
		var sm := SimMap.new()
		sm.sim = sim
		map = sm
	add_child(map)
	blobs = BlobLayer.new()
	add_child(blobs)
	gecko = Gecko.new()
	gecko.map = map
	# The camera follows after the gecko's tick, so the pixel grid it
	# anchors is the one the body is drawn on this tick (main ticks
	# before its children).
	gecko.ticked.connect(_follow)
	_sound = SoundBank.new()
	add_child(_sound)
	_sound.listen(gecko)
	_ambience = Ambience.new()
	add_child(_ambience)
	_ambience.setup(map, gecko, _sound)
	if sim:
		_backdrop = Backdrop.new()
		_backdrop.set_grid(CAM_GRID)
		add_child(_backdrop)
		_backdrop.attach_far(sim)
	gecko.blobs = blobs
	add_child(gecko)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(CaveMap.W * CaveMap.CELL)
	_camera.limit_bottom = int(CaveMap.H * CaveMap.CELL)
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 20)
	hud.add_child(_label)
	# The panel keeps working while the world is paused: this node runs
	# always and guards its own ticks, the world's nodes pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	map.process_mode = Node.PROCESS_MODE_PAUSABLE
	gecko.process_mode = Node.PROCESS_MODE_PAUSABLE
	if sim:
		sim.process_mode = Node.PROCESS_MODE_PAUSABLE
	_panel = DebugPanel.new()
	_panel.visible = false
	hud.add_child(_panel)
	_ensure_scenes()
	_panel.set_scenes(_scene_all.get("scenes", {}).keys())
	_panel.set_seed(seed_value)
	_panel.set_brush(brush_r)
	_panel.set_pixel_size(blobs.pixel_sz)
	_panel.scene_picked.connect(_load_scene)
	_panel.main_cave.connect(_main_cave)
	_panel.reload.connect(_reset)
	_panel.regenerate.connect(func(sv: int) -> void:
		seed_value = sv
		_scene = {}
		_scene_i = -1
		_panel.select_scene(-1)
		_reset())
	_panel.brush_changed.connect(func(v: float) -> void: brush_r = v)
	_panel.time_scale_changed.connect(func(v: float) -> void: Engine.time_scale = v)
	_panel.paused.connect(func(on: bool) -> void: get_tree().paused = on)
	_panel.step.connect(func() -> void:
		_step_ticks = 1
		get_tree().paused = false)
	_panel.pixel_size_changed.connect(func(v: float) -> void: blobs.set_pixel_size(v))
	_panel.overlay_changed.connect(func(on: bool) -> void: gecko.debug = on)
	if picked.is_empty() and _demo_name == "":
		_pick_level()
	_reset()
	var dump := OS.get_environment("GECKO_DUMP_MAP")
	if dump != "":
		if not sim:
			map.save_png(dump)
		get_tree().quit()
		return
	if not picked.is_empty():
		_demo = picked.steps
		_demo_step = 0
		_demo_t = 0.0
		gecko.input_override = Vector2.ZERO
	elif _demo_name != "":
		_demo = DEMOS.get(_demo_name, DEMOS["climb"])
		_demo_step = 0
		_demo_t = 0.0
		gecko.input_override = Vector2.ZERO


func _reset() -> void:
	if not _scene.is_empty():
		if sim:
			# The scene is built on a CPU map and the particles are made
			# from it, as the generated cave's are.
			var gen := CaveMap.new()
			SceneBuilder.build(gen, _scene, _scene_bases)
			map.build_cells(gen.solid)
			_backdrop.build(gen.solid, CaveMap.W, CaveMap.H, seed_value)
			gen.free()
		else:
			SceneBuilder.build(map, _scene, _scene_bases)
		_vines.clear()
		for v in SceneBuilder.spawn_lumps(map, _scene):
			_vines[v[0]] = {"top": v[1], "load": 0.0}
		_clear_slugs()
		var k := 0
		for at in SceneBuilder.slug_points(_scene):
			var s := Slug.new()
			s.setup(map, at, 31 + k)
			add_child(s)
			_slugs.append(s)
			k += 1
		_exit = SceneBuilder.exit_rect(_scene)
		if sim:
			sim.set_daylight(_exit, DAYLIGHT)
		_sound.set_exit(_exit)
		_ambience.reset()
		var sp := SceneBuilder.spawn_point(map, _scene, Gecko.RIDE_H)
		gecko.spawn(sp.pos, sp.up)
		_camera_home()
		_cam_reset()
		return
	_exit = Rect2()
	_clear_slugs()
	if sim:
		sim.set_daylight(_exit, DAYLIGHT)
	_sound.set_exit(_exit)
	_ambience.reset()
	_camera_home()
	if sim and _demo_name in ["pull", "strike", "tongue"]:
		_lab()
		return
	map.generate(seed_value)
	if _backdrop:
		# The generated cave: the far wall only (its cells are the sim's).
		_backdrop.build(PackedByteArray(), CaveMap.W, CaveMap.H, seed_value)
	var spawn := _flat_spawn()
	if _demo_name == "climb":
		# A straight pillar to the right of the spawn: the wall test
		map.fill_rect(Rect2(spawn.x + 110.0, spawn.y - 170.0, 32.0, 200.0))
	elif _demo_name == "gap":
		# A hole the body can span, then one it cannot
		map.erase_circle(Vector2(spawn.x + 80.0, spawn.y + 6.0), 15.0)
		map.erase_circle(Vector2(spawn.x + 220.0, spawn.y + 10.0), 26.0)
	elif _demo_name == "crevice":
		# A funnel in the floor, 44 px wide at the top narrowing to nothing
		for i in range(9):
			map.erase_circle(Vector2(spawn.x + 90.0, spawn.y + 6.0 + i * 8.0), 22.0 - i * 2.0)
	if sim and _demo_name == "":
		_scatter_chunks(spawn)
	gecko.spawn(spawn - Vector2(0.0, Gecko.RIDE_H))
	_cam_reset()


# A flat room for the tongue demos (particle world only): a stone small
# enough to swallow and a boulder the tongue can drag but not swallow
# for pull, a boulder for strike, the ceiling in reach for tongue.
func _lab() -> void:
	var gen := CaveMap.new()
	gen.blank()
	gen.erase_rect(Rect2(0.0, LAB_CEIL, 1920.0, LAB_FLOOR - LAB_CEIL))
	map.build_cells(gen.solid)
	gen.free()
	var x := 900.0
	if _demo_name == "pull":
		_lump_on_floor(x + 90.0, 5.0, false, LAB_CEIL + 8.0)
		_lump_on_floor(x + 190.0, 13.0, false, LAB_CEIL + 8.0)
	elif _demo_name == "strike":
		_lump_on_floor(x + 150.0, 12.0, false, LAB_CEIL + 8.0)
	gecko.spawn(Vector2(x, LAB_FLOOR - Gecko.RIDE_H))
	_cam_reset()


# A lump resting on the first floor below (x, from_y): a boulder (or a
# stone, when small) or a clump of clay. Returns its chunk id, 0 when
# it did not fit.
func _lump_on_floor(x: float, radius: float, clay: bool, from_y := 540.0) -> int:
	var fl: Vector2 = map.floor_below(Vector2(x, from_y))
	var p := Vector2(x, fl.y - radius - 2.0)
	if map.solid_within(p, radius + 2.0):
		return 0
	return map.spawn_clay(p, radius) if clay else map.spawn_boulder(p, radius)


# Loose lumps about the chamber's floor: a boulder too heavy for the
# tongue, two it can drag, some stones and clumps of clay, and two heaps
# of sand, clear of the spawn so the gecko starts on plain ground and
# clear of the pool.
func _scatter_chunks(spawn: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var lumps := [[18.0, false], [13.0, false], [10.0, false], [4.0, false], [5.0, false],
		[3.5, false], [4.5, false], [11.0, true], [8.0, true]]
	for lump in lumps:
		for _try in 8:
			var x := rng.randf_range(720.0, 1400.0)
			if absf(x - spawn.x) < 140.0:
				continue
			if _lump_on_floor(x, lump[0], lump[1]) > 0:
				break
	for r in [26.0, 18.0]:
		for _try in 8:
			var x := rng.randf_range(720.0, 1400.0)
			if absf(x - spawn.x) < 160.0:
				continue
			var fl: Vector2 = map.floor_below(Vector2(x, 540.0))
			var p := Vector2(x, fl.y - r - 2.0)
			if map.solid_within(p, r + 2.0):
				continue
			map.spawn_sand(p, r)
			break


# The floor point near the middle of the chamber with the least slope
# across a body length, so the gecko starts level.
func _flat_spawn() -> Vector2:
	var best := Vector2.ZERO
	var best_slope := INF
	for x in range(800, 1121, 8):
		var y0 := map.floor_below(Vector2(x - 24.0, 540.0)).y
		var y1 := map.floor_below(Vector2(x + 24.0, 540.0)).y
		var slope := absf(y1 - y0)
		if slope < best_slope:
			best_slope = slope
			best = map.floor_below(Vector2(x, 540.0))
	return best


func _physics_process(dt: float) -> void:
	if get_tree().paused and _step_ticks == 0:
		return
	if _step_ticks > 0:
		# One tick for the panel's step button, then paused again after
		# the frame, so the world's nodes get their tick too.
		_step_ticks -= 1
		if _step_ticks == 0:
			get_tree().set_deferred("paused", true)
			_panel.set_paused(true)
	_update_slugs(dt)
	if sim:
		var glows: Array = [[gecko.chain.head(), GLOW_COLOR.lerp(Color(0.8, 1.0, 0.6), 0.5 if gecko.glow_boost > 0.0 else 0.0),
				GLOW_R * (1.8 if gecko.glow_boost > 0.0 else 1.0)]]
		for s in _slugs:
			glows.append(s.glow())
		sim.set_glows(glows)
		sim.tick()
		_update_vines(dt)
	if not _won and _exit.has_area() and _exit.has_point(gecko.pos):
		_win()
	if _demo_step >= 0:
		_run_demo(dt)
	# The state readout only with the debug overlay; the controls hint for
	# the first seconds of a run.
	_hint_t += dt
	if _debug:
		_label.text = gecko.debug_text()
		_panel.set_status(gecko.debug_text())
	elif _hint_t < 10.0:
		_label.text = _hint if _hint != "" else "WASD move   Space jump   LMB tap strike, hold grapple   LMB+RMB drag, eat   RMB chew at cursor   B boulder  C clay  N sand (hold: pour)   R again   Tab test scene   F1 debug"
	else:
		_label.text = ""


# The slugs creep (slug.gd), one swallowed at the mouth is gone and the
# gecko's glow brightens, and their blobs go to the gecko's drawing.
func _update_slugs(dt: float) -> void:
	var blobs_out: Array = []
	for i in range(_slugs.size() - 1, -1, -1):
		var s: Node2D = _slugs[i]
		s.tick(dt, gecko)
		if s.eaten:
			gecko.gulp_slug()
			_slugs.remove_at(i)
			s.queue_free()
			continue
		for b in s.blobs():
			blobs_out.append(b)
	gecko.extra_blobs = blobs_out


func _clear_slugs() -> void:
	for s in _slugs:
		s.queue_free()
	_slugs.clear()
	gecko.extra_blobs = []


# A vine the gecko hangs on (a planted foot on its cells) takes the
# load for VINE_HOLD, then its anchor's bonds are broken and it comes
# down, gecko and all; the load eases off a vine let go of.
func _update_vines(dt: float) -> void:
	if _vines.is_empty():
		return
	var held := -1
	if gecko.clinging:
		for f in gecko.feet:
			if f.planted:
				var id: int = map.chunk_at_world(f.pos)
				if _vines.has(id):
					held = id
					break
	for id in _vines.keys():
		var v: Dictionary = _vines[id]
		v.load = v.load + dt if id == held else maxf(v.load - dt * 2.0, 0.0)
		if v.load >= VINE_HOLD:
			map.break_circle(v.top, 7.0)
			_vines.erase(id)


# The camera, after the gecko's tick (its ticked signal). Out of the
# cave it lets go of the gecko and pulls back over the whole cave, the
# rock round it in view. Otherwise it follows the drawn body's base:
# it scrolls exactly with the base's own move up to CAM_LOCK_SPEED, so
# an ordinary walk keeps the body on the same screen pixels and the
# small unevenness of its speed goes into the scroll, where the eye
# does not see it, rather than into the body's place on the screen;
# whatever lag is left (a fall, a landing's jolt, a long move in one
# tick) eases out at CAMERA_EASE. It sits on whole screen pixels
# (CAM_GRID), held inside the world's edges, so the world scrolls a
# screen pixel at a time and every edge stays crisp. The body's own
# pixel grid is anchored on the base's place on the screen's pixels
# (the blob layer's origin), so the body is drawn with the same pixels
# tick after tick and moves on the screen only as the camera's lag
# changes, a screen pixel at a time. Before, the camera was rounded to
# the body's 2 px grid and the body to the world's: the two crossed
# pixel boundaries at different moments and the body shook a pixel
# back and forth as it walked, while the world scrolled in 2 px steps.
func _follow() -> void:
	var dt := get_physics_process_delta_time()
	if _won:
		var k := 1.0 - exp(-WIN_PULL * dt)
		_cam = _cam.lerp(Vector2(CaveMap.W * CaveMap.CELL, CaveMap.H * CaveMap.CELL) * 0.5, k)
		_camera.position = _cam
		_camera.zoom = _camera.zoom.lerp(Vector2(WIN_ZOOM, WIN_ZOOM), k)
		return
	var target := gecko.draw_pos()
	_cam += (target - _cam_target).limit_length(CAM_LOCK_SPEED * dt)
	_cam_target = target
	_cam = _cam.lerp(target, 1.0 - exp(-CAMERA_EASE * dt))
	_camera.position = _cam_clamped((_cam / CAM_GRID).round() * CAM_GRID)
	# The seat moves to the lag's nearest screen pixel only once the lag
	# has left the seat by a whole one: the camera's own rounding to the
	# grid puts a quarter pixel of noise on the lag, which would rock a
	# seat at a boundary between two pixels.
	var lag := target - _camera.position
	for k in 2:
		if absf(lag[k] - _seat_off[k]) >= CAM_GRID:
			_seat_off[k] = roundf(lag[k] / CAM_GRID) * CAM_GRID
	_cam_seat = _camera.position + _seat_off
	blobs.set_origin(_cam_seat.posmodv(Vector2(blobs.pixel_sz, blobs.pixel_sz)))
	if _backdrop:
		_backdrop.follow(_camera.position)


# The camera straight onto the gecko, as at a spawn.
func _cam_reset() -> void:
	_cam = gecko.draw_pos()
	_cam_target = _cam
	_camera.position = _cam_clamped((_cam / CAM_GRID).round() * CAM_GRID)
	_seat_off = Vector2.ZERO
	_cam_seat = _camera.position
	blobs.set_origin(_cam_seat.posmodv(Vector2(blobs.pixel_sz, blobs.pixel_sz)))


# The camera centre held inside its limits, as Camera2D itself would
# hold it, so the position set is the position shown and the blob grid
# can be anchored to it; on the camera's grid, so the view at an edge
# stays on whole screen pixels.
func _cam_clamped(p: Vector2) -> Vector2:
	var half := get_viewport().get_visible_rect().size * 0.5 / _camera.zoom
	half = (half / CAM_GRID).ceil() * CAM_GRID
	return Vector2(clampf(p.x, _camera.limit_left + half.x, _camera.limit_right - half.x),
			clampf(p.y, _camera.limit_top + half.y, _camera.limit_bottom - half.y))


# The gecko is out of the cave. Input stays with the player; the camera
# pulls back (see _physics_process) and R starts the cave again.
func _win() -> void:
	_won = true
	_camera.limit_left = -CAM_LIMIT
	_camera.limit_top = -CAM_LIMIT
	_camera.limit_right = CAM_LIMIT
	_camera.limit_bottom = CAM_LIMIT
	_hint = "out, into the light.   R hatches again"
	_hint_t = 0.0


# The camera back on the gecko at the game's zoom, held to the world.
func _camera_home() -> void:
	_won = false
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(CaveMap.W * CaveMap.CELL)
	_camera.limit_bottom = int(CaveMap.H * CaveMap.CELL)


# The first cave as the scene to build: its index in the scene list, so
# Tab goes on from it.
func _pick_level() -> void:
	_ensure_scenes()
	var scenes: Dictionary = _scene_all.get("scenes", {})
	if not scenes.has(LEVEL):
		push_error("no level named " + LEVEL)
		_scene = {}
		_scene_i = -1
		return
	_scene = scenes[LEVEL]
	_scene_bases = _scene_all.get("bases", {})
	_scene_i = scenes.keys().find(LEVEL)
	_panel.select_scene(_scene_i)


func _in_level() -> bool:
	return not _scene.is_empty() and _scene_i >= 0 and _scene_all.get("scenes", {}).keys()[_scene_i] == LEVEL


func _ensure_scenes() -> void:
	if _scene_all.is_empty():
		_scene_all = SceneBuilder.load_all()


# Tab: the next test scene from tests/scenes.json, built in this world,
# with the keys driving the gecko instead of the scene's script.
func _next_scene() -> void:
	_ensure_scenes()
	var n: int = _scene_all.get("scenes", {}).size()
	if n > 0:
		_load_scene((_scene_i + 1) % n)


func _load_scene(i: int) -> void:
	_ensure_scenes()
	var names: Array = _scene_all.get("scenes", {}).keys()
	if names.is_empty() or i < 0 or i >= names.size():
		return
	_scene_i = i
	var name: String = names[i]
	_scene = _scene_all.scenes[name]
	_scene_bases = _scene_all.bases
	_demo_step = -1
	gecko.input_override = null
	gecko.chew_override = false
	gecko.lmb_override = false
	_reset()
	_panel.select_scene(i)
	_hint = "scene %d/%d  %s   (Tab next, Shift+Tab main cave)" % [i + 1, names.size(), name]
	_hint_t = 5.0


# Shift+Tab: back to the first cave.
func _main_cave() -> void:
	_pick_level()
	_demo_step = -1
	gecko.input_override = null
	gecko.chew_override = false
	gecko.lmb_override = false
	_reset()
	_hint = "the clutch"
	_hint_t = 7.0


func _run_demo(dt: float) -> void:
	if _demo_step >= _demo.size():
		gecko.input_override = Vector2.ZERO
		gecko.chew_override = false
		gecko.lmb_override = false
		gecko.aim_override = Vector2.ZERO
		if not _scene.is_empty():
			_scene_done = maxf(_scene_done, 0.0) + dt
			if _scene_done >= SCENE_SETTLE:
				get_tree().quit()
		return
	var step: Array = _demo[_demo_step]
	if _demo_t == 0.0 and step[2]:
		gecko.jump_override = true
	gecko.input_override = step[1]
	gecko.chew_override = step[3]
	gecko.lmb_override = step[4] if step.size() > 4 else false
	gecko.aim_override = step[5] if step.size() > 5 else Vector2.ZERO
	_demo_t += dt
	if _demo_t >= step[0]:
		_demo_step += 1
		_demo_t = 0.0


func _process(_dt: float) -> void:
	if sim:
		sim.read_render()
	if _trace:
		# One line per drawn frame, for tools/analyze.py's camera metrics
		# and the sheet tools: the body centre's screen position in the
		# movie frame (the window is unstretched, project.godot, so the
		# frame is the window's size, one pixel per pixel, whatever size
		# the compositor gave it), the tick, the camera's centre in the
		# world (as shown: held to the world's edges), the drawn body's
		# base on the screen where the blob layer's grid seats it, that
		# base in the world, and 1 once the gecko is out and the camera
		# has let go of it.
		var half := get_viewport().get_visible_rect().size * 0.5
		var cam := _camera.get_screen_center_position()
		var screen := (gecko.pos - cam) * CAMERA_ZOOM + half
		var base := gecko.draw_pos()
		var body := (_cam_seat - cam) * CAMERA_ZOOM + half
		print("F%d %d %d %d %.2f %.2f %.1f %.1f %.2f %.2f %d" % [Engine.get_frames_drawn(), int(screen.x), int(screen.y), gecko._tick,
			cam.x, cam.y, body.x, body.y, base.x, base.y, 1 if _won else 0])
	var m := get_global_mouse_position()
	var over_panel := _panel.has_mouse(get_viewport().get_mouse_position())
	gecko.mouse_blocked = over_panel
	if over_panel or get_tree().paused:
		pass
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.is_key_pressed(KEY_CTRL):
		map.erase_circle(m, brush_r, true)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		map.fill_circle(m, brush_r)
	if not over_panel and Input.is_action_just_pressed("drop_boulder"):
		map.spawn_boulder(m, maxf(brush_r * 0.5, 4.0))
	if not over_panel and Input.is_action_just_pressed("drop_clay"):
		map.spawn_clay(m, maxf(brush_r * 0.5, 4.0))
	# N held pours: the heap tops itself up every frame as it flows away.
	if not over_panel and Input.is_action_pressed("drop_sand"):
		map.spawn_sand(m, maxf(brush_r * 0.5, 4.0))
	if Input.is_action_just_pressed("regenerate"):
		if _in_level():
			_reset()
		else:
			seed_value += 1
			_scene = {}
			_scene_i = -1
			_panel.select_scene(-1)
			_panel.set_seed(seed_value)
			_reset()
	# Exact matches, so Tab with Shift held is only the one action.
	if Input.is_action_just_pressed("scene_next", true):
		_next_scene()
	if Input.is_action_just_pressed("scene_main", true):
		_main_cave()
	if Input.is_action_just_pressed("debug_toggle"):
		_debug = not _debug
		_panel.visible = _debug
		gecko.debug = _debug
		_panel.set_overlay(_debug)
	if Input.is_action_just_pressed("render_coarse"):
		blobs.set_pixel_size(BlobLayer.PIXEL_SZ_COARSE)
		_panel.set_pixel_size(BlobLayer.PIXEL_SZ_COARSE)
	if Input.is_action_just_pressed("render_fine"):
		blobs.set_pixel_size(BlobLayer.PIXEL_SZ_FINE)
		_panel.set_pixel_size(BlobLayer.PIXEL_SZ_FINE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_r = minf(brush_r + 4.0, 80.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_r = maxf(brush_r - 4.0, 8.0)
		_panel.set_brush(brush_r)
